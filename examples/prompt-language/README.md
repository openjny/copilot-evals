# Prompt Language A/B Evaluation

Compares English vs Japanese prompts on identical code tasks.

| Variant | Description |
|---------|-------------|
| **english** | Prompt and response in English |
| **japanese** | Prompt and response in Japanese |

## Tasks

- **code-review** — Review a Node.js Express app with 7 intentional security issues
- **explain-architecture** — Explain architecture and design patterns of the same app

## Run

```bash
uv run copilot-eval build --config-dir examples/prompt-language
docker compose up -d
uv run copilot-eval run --config-dir examples/prompt-language
uv run copilot-eval analyze --run-id <RUN_ID> --config-dir examples/prompt-language -o markdown
```

## Results

Model: gpt-5.4-mini, judge: claude-sonnet-4.6, 2 tasks × 2 variants × 3 epochs = 12 runs.

### code-review

| Metric | english | japanese | Δ |
|--------|--------:|--------:|------:|
| Duration (s) | **24.6** | 31.9 | +23.5% |
| Input tokens | **92K** | 130K | +39.8% |

| Evaluator | english | japanese | Δ |
|-----------|:---:|:---:|---|
| thoroughness | 9 | **10** | +11% |
| actionability | 7 | 7 | 0% |

### explain-architecture

| Metric | english | japanese | Δ |
|--------|--------:|--------:|------:|
| Duration (s) | **19.6** | 25.1 | +14.6% |
| Input tokens | **92K** | 112K | +20.9% |

| Evaluator | english | japanese | Δ |
|-----------|:---:|:---:|---|
| completeness | **10** | 8 | -10% |
| clarity | 9 | 9 | 0% |

### Takeaways

- Language gap is small — no dramatic quality difference
- code-review slightly favors Japanese, explain-architecture favors English
- English is 30-40% more token-efficient across both tasks
