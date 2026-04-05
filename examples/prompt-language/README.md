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

Full eval run: 2 tasks × 2 variants × 3 epochs = 12 runs, model: claude-sonnet-4, parallel: full.

### code-review

| Metric | english | japanese | Δ (paired) |
|--------|--------:|--------:|------:|
| Duration (s) | 71.3 | **46.0** | -30.7% |
| Turns | 6 | **3** | -33.3% |
| Input tokens | 146K | **68K** | -35.9% |
| Output tokens | 3,732 | **2,816** | -31.5% |

**Tools**: english uses more `bash`(9) commands to run the code. japanese is more concise, using mainly `view`(9) + `create`(3).

| Evaluator | english | japanese | Δ |
|-----------|:-----------:|:--------:|--------|
| thoroughness | 6 | **7** | +33% |
| actionability | 4 | **7** | +75% |

**Takeaway**: Japanese prompts produce faster, more token-efficient, AND higher quality code reviews. Japanese responses are 31% fewer output tokens but score higher on both thoroughness and actionability. The model appears to be more focused and less verbose in Japanese.

### explain-architecture

| Metric | english | japanese | Δ (paired) |
|--------|--------:|--------:|------:|
| Duration (s) | **56.3** | 81.9 | +45.4% |
| Turns | **4** | 7 | +75.0% |
| Input tokens | **93K** | 167K | +79.9% |
| Output tokens | **3,118** | 4,261 | +36.7% |

**Tools**: english uses only `view`(10) + `create`(6) — read and write. japanese adds `bash`(10) — actually runs the code to understand it.

| Evaluator | english | japanese | Δ |
|-----------|:-----------:|:--------:|--------|
| clarity | **7** | 6 | -14% |
| completeness | 6 | 6 | 0% |

**Takeaway**: English is faster and clearer for architecture explanation. Japanese takes more turns and tokens, partly because it runs the code (`bash` 10 calls) to supplement understanding. The extra investigation doesn't improve completeness.

### Key Insights

1. **Task type matters**: Japanese wins on code-review (more concise, higher quality) but loses on explain-architecture (slower, more verbose). The model's behavior changes significantly based on the combination of task + language.

2. **Token efficiency is not consistent**: Japanese is 2× more efficient on code-review (68K vs 146K input) but 2× less efficient on explain-architecture (167K vs 93K). There's no universal "cheaper language."

3. **Quality vs efficiency trade-off varies**: For code-review, Japanese is both cheaper AND better. For explain-architecture, English is cheaper AND clearer. The common assumption that "English = better LLM performance" does not hold uniformly.

4. **Behavioral differences**: Japanese prompts cause the model to take different approaches — fewer tool calls on code-review but more on explain-architecture. The prompt language influences not just the output format but the problem-solving strategy.

5. **Low variance**: With termination conditions in prompts ("write to /workspace/*.md when done"), run-to-run variance is low — especially for English (46.9-58.8s on explain-architecture).
