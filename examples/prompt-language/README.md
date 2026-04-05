# Prompt Language A/B Evaluation

Compares English vs Japanese prompts on identical code tasks to measure the impact of prompt language on token consumption, response quality, and execution speed.

## Overview

Same Copilot CLI, same model, same code — the only difference is the language of the prompt and expected response.

| Variant | Description |
|---------|-------------|
| **english** | Prompt and response in English |
| **japanese** | Prompt and response in Japanese |

## Tasks

### code-review

Review a Node.js Express app with intentional security issues (eval injection, plaintext passwords, missing auth).

### explain-architecture

Explain the architecture and design patterns of the same app.

## Prerequisites

1. Build base image:
   ```bash
   uv run copilot-eval build --config-dir examples/prompt-language
   ```

2. Start Jaeger:
   ```bash
   docker compose up -d
   ```

## Running

```bash
# All tasks, full parallel (12 runs in ~5 min)
uv run copilot-eval run --config-dir examples/prompt-language

# Analyze
uv run copilot-eval analyze --run-id <RUN_ID> --config-dir examples/prompt-language -o markdown
```

## Results

Run ID: `20260406-014831`, model: gpt-5.4-mini, judge: claude-sonnet-4.6, 2 tasks × 2 variants × 3 epochs = 12 runs.

### code-review

| Metric | english | japanese | Δ (paired) |
|--------|--------:|--------:|------:|
| Duration (s) | **24.6** | 31.9 | +23.5% |
| Turns | **5** | 7 | +40.0% |
| Input tokens | **92K** | 130K | +39.8% |
| Output tokens | **1,247** | 1,542 | +10.9% |
| Tool calls | **6** | 10 | +66.7% |

**Tools**: english: `view`(9), `report_intent`(3), `glob`(3), `apply_patch`(3). japanese: `view`(9), `report_intent`(6), `apply_patch`(5), `glob`(3), `sql`(2), `bash`(1).

| Evaluator | english | japanese | Δ |
|-----------|:-----------:|:--------:|--------|
| thoroughness | 9 | **10** | +11% |
| actionability | 7 | 7 | 0% |

**Per-run scores**:

| Variant | Epoch | thoroughness | actionability |
|---------|------:|:---:|:---:|
| english | 1 | 9 | 7 |
| english | 2 | 7 | 6 |
| english | 3 | 9 | 8 |
| japanese | 1 | 10 | 8 |
| japanese | 2 | 8 | 7 |
| japanese | 3 | 10 | 5 |

**Takeaway**: Both languages perform well. Japanese is slightly better on thoroughness (10 vs 9) but English is faster and more token-efficient.

### explain-architecture

| Metric | english | japanese | Δ (paired) |
|--------|--------:|--------:|------:|
| Duration (s) | **19.6** | 25.1 | +14.6% |
| Turns | 5 | 5 | 0% |
| Input tokens | **92K** | 112K | +20.9% |
| Output tokens | **1,235** | 1,986 | +46.2% |
| Tool calls | **6** | 8 | +33.3% |

**Tools**: english: `view`(9), `apply_patch`(3), `glob`(3), `report_intent`(3). japanese: `view`(13), `report_intent`(4), `glob`(4), `apply_patch`(3).

| Evaluator | english | japanese | Δ |
|-----------|:-----------:|:--------:|--------|
| completeness | **10** | 8 | -10% |
| clarity | 9 | 9 | 0% |

**Per-run scores**:

| Variant | Epoch | completeness | clarity |
|---------|------:|:---:|:---:|
| english | 1 | 9 | 9 |
| english | 2 | 10 | 9 |
| english | 3 | 10 | 9 |
| japanese | 1 | 9 | 9 |
| japanese | 2 | 8 | 9 |
| japanese | 3 | 8 | 9 |

**Takeaway**: English edges out on completeness (10 vs 8) with fewer tokens.

### Key Insights

1. **Language gap is small**: code-review thoroughness 9 vs 10, actionability 7 vs 7. explain-architecture completeness 10 vs 8, clarity 9 vs 9. No dramatic quality difference.

2. **Task type determines winner**: code-review slightly favors Japanese. explain-architecture favors English.

3. **English is more token-efficient**: 30-40% fewer input tokens across both tasks. The model takes fewer turns in English.

4. **Behavioral differences**: Japanese uses more tools (10 vs 6 on code-review) and takes more turns, but doesn't translate to proportionally higher scores.
