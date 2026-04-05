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

Full eval run: 3 tasks × 2 variants × 3 epochs = 18 runs, model: claude-sonnet-4.

### Task: compliance-audit

| Metric | baseline | azure-skills | Delta |
|--------|--------:|--------:|------:|
| Duration (s) | 165.0 | 183.4 | +11.2% |
| Turns | 13 | 15 | +15.4% |
| Tool calls | 27 | 29 | +7.4% |
| Tool duration (s) | 36.0 | 54.5 | +51.4% |
| Input tokens | 356K | 860K | +141.6% |
| Output tokens | 6,731 | 7,084 | +5.2% |

Tool patterns: azure-skills uses `azure-extension_azqr` for bulk security review + `bash` for granular checks. baseline uses only `bash` + `sql`.

| Evaluator | baseline | azure-skills | Winner |
|-----------|:-----------:|:--------:|--------|
| methodology | **8** | 7 | baseline |
| coverage | **8** | 6 | baseline |
| finding_accuracy | **7** | 5 | baseline |
| remediation_quality | **7** | 4 | baseline |
| verify | 1 | 1 | tie |

**Takeaway**: baseline's per-resource `az` CLI inspection is more thorough. azure-skills' MCP bulk tools miss granular settings.

### Task: app-deploy

| Metric | baseline | azure-skills | Delta |
|--------|--------:|--------:|------:|
| Duration (s) | 295.8 | **130.4** | -55.9% |
| Turns | 33 | **9** | -72.7% |
| Tool calls | 37 | **18** | -51.4% |
| Tool duration (s) | 180.6 | **17.9** | -90.1% |
| Input tokens | 857K | 525K | -38.7% |
| Output tokens | 4,695 | 5,139 | +9.5% |

Tool patterns: azure-skills uses `azure-appservice` MCP tool for deploy. baseline relies on lengthy `bash` trial-and-error.

| Evaluator | baseline | azure-skills | Winner |
|-----------|:-----------:|:--------:|--------|
| deployment_approach | 3 | **4** | azure-skills |
| completeness | **3** | 2 | baseline |
| verification | **7** | 1 | baseline |
| verify | 0 | 0 | tie |

**Takeaway**: azure-skills is dramatically faster (130s vs 296s, 10× faster tool execution) with structured deploy workflow. However, baseline actually verifies deployment (7 vs 1). Neither achieves `verify` PASS consistently.

### Task: diagnostics

| Metric | baseline | azure-skills | Delta |
|--------|--------:|--------:|------:|
| Duration (s) | **157.2** | 287.4 | +82.8% |
| Turns | 17 | 18 | +5.9% |
| Tool calls | 32 | 34 | +6.3% |
| Tool duration (s) | **85.4** | 216.5 | +153.5% |
| Input tokens | 440K | 1,100K | +150.0% |
| Output tokens | 4,432 | 5,322 | +20.1% |

Tool patterns: azure-skills uses `azure-applens`(6), `azure-resourcehealth`(6), `azure-applicationinsights`(3) for structured diagnostics. baseline uses `bash` commands directly.

| Evaluator | baseline | azure-skills | Winner |
|-----------|:-----------:|:--------:|--------|
| diagnostic_depth | **6** | 5 | baseline |
| tool_usage | **7** | 6 | baseline |
| root_cause | 2 | 2 | tie |
| actionability | 2 | 2 | tie |
| verify | 1 | 1 | tie |

**Takeaway**: Closest results. azure-skills is slower (MCP tool startup overhead) but uses richer diagnostic sources. Neither variant reliably identifies root cause (both 2/10).

### Key Insights

1. **Task type determines plugin value**: azure-skills excels at structured workflows (app-deploy: 56% faster) but underperforms on open-ended investigation (compliance-audit, diagnostics).

2. **MCP tools trade latency for structure**: MCP tools add startup overhead (diagnostics: 217s vs 85s tool duration) but reduce turns and provide structured data. The trade-off is favorable for deploy, unfavorable for diagnostics.

3. **verification is the biggest gap**: baseline scores 7 vs 1 on app-deploy verification — a potential gap in the `azure-deploy` skill's workflow.

4. **Input token cost scales with MCP**: azure-skills uses 2-3× more input tokens across all tasks due to MCP tool descriptions + skill definitions in context.

5. **root_cause is unsolved**: both variants score 2/10 on diagnostics root_cause — the intentional issues (wrong startup command + missing module) are hard to identify regardless of tooling.
