# Azure Skills Plugin A/B Evaluation

An eval set that measures the impact of adding Azure Skills Plugin (`microsoft/azure-skills`) to Copilot CLI through A/B comparison.

## Overview

Runs Copilot CLI inside Docker containers and compares Azure resource operation tasks across two variants:

| Variant | Description |
|---------|-------------|
| **baseline** | Copilot CLI + Azure CLI (no plugins) |
| **azure-skills** | Copilot CLI + Azure Skills Plugin |

Each task is executed over multiple epochs and scored using LLM-as-Judge + script-based verification.

## Tasks

### 1. compliance-audit

Audit the security and compliance posture of all resources in the resource group.

- **Prompt**: `Audit the security and compliance posture of the resources in resource group {resource_group}...`
- **Evaluators**: verify (script), coverage (judge), finding_accuracy (judge), remediation_quality (judge), methodology (judge)
- **Features demonstrated**: Script evaluator validates actual Azure config + judge evaluators assess audit quality

### 2. app-deploy

Deploy a Node.js Express app to an existing App Service.

- **Prompt**: `I have a simple Node.js Express app in the current directory. Deploy it to the existing Azure App Service...`
- **Fixture**: `fixtures/app-deploy/` (Express app mounted at `/workspace`)
- **Evaluators**: verify (script), deployment_approach (judge), completeness (judge), verification (judge)
- **Features demonstrated**: Fixture mounting + post-deployment HTTP verification

### 3. diagnostics

Diagnose an intentionally broken App Service.

- **Prompt**: `There is an App Service in resource group {resource_group} that seems to be having issues...`
- **before_run hook**: `prepare-diagnostics.sh` (resets environment, then deploys a broken app + sets a wrong startup command)
- **Evaluators**: verify (script), diagnostic_depth (judge), root_cause (judge), actionability (judge), tool_usage (judge)
- **Features demonstrated**: Custom before_run hook to construct a failure scenario

## Directory Structure

```
examples/azure-skills/
├── eval-config.yaml          # Task, variant, and evaluator definitions
├── .env.example              # Azure SP credentials template
├── docker/
│   ├── Dockerfile.baseline   # Variant: Copilot CLI + Azure CLI
│   └── Dockerfile.azure-skills # Variant: + Azure Skills Plugin + MCP
├── infra/
│   ├── main.bicep            # Baseline Azure environment (VNet, App Service, SQL, Storage, ...)
│   └── main.bicepparam.example
├── fixtures/
│   ├── app-deploy/           # Node.js Express app for app-deploy task
│   │   ├── index.js
│   │   └── package.json
│   └── diagnostics/          # Intentionally broken Node.js app for diagnostics task
│       ├── index.js          # require('./config') — module does not exist
│       └── package.json
└── scripts/
    ├── azure-login.sh        # SP login inside container (run script)
    ├── reset-environment.sh  # Reset environment via Bicep Complete mode (shared hook)
    ├── prepare-diagnostics.sh # diagnostics: reset + deploy broken app
    ├── verify-compliance-audit.sh   # compliance-audit verification
    ├── verify-app-deploy.sh         # app-deploy verification
    └── verify-diagnostics.sh        # diagnostics verification
```

## Azure Environment

`infra/main.bicep` deploys the following resources:

- VNet (2 subnets: app + private endpoint)
- App Service Plan (B1) + App Service (Node 20, HTTPS only, VNet integrated)
- Storage Account (private endpoint, public access disabled)
- SQL Server (Entra-only auth) + Database
- Log Analytics + Application Insights
- Private Endpoints (Storage, SQL)

## Prerequisites

1. Create an Azure Service Principal and configure `.env`:
   ```bash
   cp .env.example .env
   # Set AZURE_TENANT_ID, AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, AZURE_SUBSCRIPTION_ID
   ```

2. Create resource groups and grant the SP permissions:
   ```bash
   # Each task uses its own resource group for parallel execution
   SUBSCRIPTION_ID="<your-subscription-id>"
   SP_APP_ID="<your-sp-client-id>"

   for RG in rg-copilot-eval-compliance rg-copilot-eval-deploy rg-copilot-eval-diag; do
     az group create --name "$RG" --location southeastasia
     az role assignment create \
       --assignee "$SP_APP_ID" \
       --role Contributor \
       --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG"
   done

   # SQL Server Entra admin requires Directory Readers or the SP's object ID
   SP_OBJECT_ID=$(az ad sp show --id "$SP_APP_ID" --query id -o tsv)
   ```

3. Build Docker images:
   ```bash
   uv run copilot-eval build --config-dir examples/azure-skills
   ```

4. Start Jaeger:
   ```bash
   docker compose up -d
   ```

## Running

```bash
# Run all tasks in parallel (epoch=3)
uv run copilot-eval run --config-dir examples/azure-skills --epochs 3

# Run a single task
uv run copilot-eval run --config-dir examples/azure-skills --task compliance-audit --epochs 3

# Analyze results
uv run copilot-eval analyze --run-id <RUN_ID> -o markdown
```

## Cleanup

```bash
# Delete all eval resource groups after testing
for RG in rg-copilot-eval-compliance rg-copilot-eval-deploy rg-copilot-eval-diag; do
  az group delete --name "$RG" --yes --no-wait
done
```

## Evaluation Methodology

### Scoring

- **Script evaluators** (verify): Pass/Fail — inspect the actual Azure environment (resource existence, HTTP response)
- **Judge evaluators**: 1-10 scale — an LLM evaluates the Copilot CLI output

### Environment Reset

Before each run, `reset-environment.sh` (or `prepare-diagnostics.sh`) resets the Azure environment using Bicep Complete mode deployment. This reverts any resources Copilot created or modified in a previous run, ensuring reproducibility.

### Isolation

Each Copilot CLI execution runs in an isolated Docker container. Containers are ephemeral (disposable), preventing environment contamination between variants.

## Results

Full eval run: 3 tasks × 2 variants × 3 epochs = 18 runs, model: claude-sonnet-4. Aggregation: paired comparison (per-epoch delta → median).

### compliance-audit

| Metric | baseline | azure-skills | Δ (paired) |
|--------|--------:|--------:|------:|
| Duration (s) | 142.8 | 186.7 | +48.1% |
| Turns | 12 | 20 | +66.7% |
| Tool calls | 29 | 23 | +3.4% |
| Tool duration (s) | 39.0 | 49.7 | +56.6% |
| Input tokens | 304K | 1,074K | +253.0% |
| Output tokens | 6,127 | 5,965 | +14.0% |

**Tools**: baseline uses `bash`(64) + `sql`(9). azure-skills adds `azure-extension_azqr`(3), `azure-group_resource_list`(3).

| Evaluator | baseline | azure-skills | Δ |
|-----------|:-----------:|:--------:|--------|
| coverage | 7 | 7 | 0% |
| accuracy | 5 | **6** | +20% |
| remediation | 6 | 6 | -17% |

**Takeaway**: Near-parity on quality. azure-skills slightly better on accuracy (+20% paired delta), using MCP's `azqr` tool for structured checks. Baseline is faster and uses 3× fewer input tokens.

### app-deploy

| Metric | baseline | azure-skills | Δ (paired) |
|--------|--------:|--------:|------:|
| Duration (s) | 296.1 | **142.9** | -32.2% |
| Turns | 14 | 13 | -64.3% |
| Tool calls | 19 | 20 | -36.8% |
| Tool duration (s) | 236.7 | **18.4** | -53.4% |
| Input tokens | 332K | 803K | +33.3% |
| Output tokens | 2,636 | 5,233 | +5.3% |

**Tools**: baseline uses `bash`(47) with lengthy trial-and-error. azure-skills finishes faster with fewer retries.

| Evaluator | baseline | azure-skills | Δ |
|-----------|:-----------:|:--------:|--------|
| approach | 5 | **7** | +40% |
| deploy_success | 1 | 1 | 0% |
| post_check | **9** | 1 | -89% |

**Takeaway**: azure-skills has clearly better deployment approach (7 vs 5) and is 2× faster. But baseline excels at post-deployment verification (9 vs 1) — it actually checks the app is running. Both successfully deploy (deploy_success = 1).

### diagnostics

| Metric | baseline | azure-skills | Δ (paired) |
|--------|--------:|--------:|------:|
| Duration (s) | 230.9 | 286.9 | +24.0% |
| Turns | 18 | 15 | -33.3% |
| Tool calls | 37 | 35 | -10.8% |
| Tool duration (s) | 107.1 | 211.6 | +127.2% |
| Input tokens | 523K | 899K | +44.9% |
| Output tokens | 6,643 | 6,317 | -1.7% |

**Tools**: azure-skills uses `azure-appservice`(22), `azure-resourcehealth`(6), `azure-applens`(6), `azure-monitor`(5) — rich MCP diagnostic sources. baseline relies on `bash`(89).

| Evaluator | baseline | azure-skills | Δ |
|-----------|:-----------:|:--------:|--------|
| breadth | 5 | **7** | +40% |
| evidence | 6 | **7** | +17% |
| root_cause | **5** | 2 | -60% |

**Takeaway**: Most interesting results. azure-skills uses richer data sources (breadth 7 vs 5, evidence 7 vs 6) via MCP tools, but baseline is better at identifying root cause (5 vs 2). MCP provides structured access to diagnostic data, but the `azure-compliance` skill doesn't guide toward root cause identification as effectively as manual `az` CLI investigation.

### Key Insights

1. **compliance-audit: near-parity**. Similar scores, but azure-skills uses 3× more input tokens for marginal accuracy improvement. The plugin doesn't provide a clear advantage on compliance tasks.

2. **app-deploy: plugin wins on approach, loses on verification**. azure-skills' structured workflow (approach 7 vs 5) and speed (143s vs 296s) are clear wins. The gap is in post-deployment checking (1 vs 9) — the plugin deploys but doesn't verify.

3. **diagnostics: breadth vs depth trade-off**. azure-skills gathers more evidence from more sources (MCP tools), but baseline's manual investigation is better at pinpointing root cause (5 vs 2). This suggests MCP tools surface data well but the Skills layer doesn't synthesize it into conclusions.

4. **Token cost is significant**. azure-skills consistently uses 2-3× more input tokens due to MCP tool definitions + skill content loaded into context. This is a real cost concern for production use.

5. **Termination conditions helped**. Prompts now include "write to /workspace/*.md when done," which reduced run-to-run variance compared to previous results.
