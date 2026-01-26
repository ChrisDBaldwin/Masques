# Masque Evaluations

This directory contains evaluation suites for testing masque behavioral fidelity using [promptfoo](https://promptfoo.dev).

## Purpose

Evaluations validate that a masque produces the expected behavioral changes:
- Intent boundaries are respected (denied patterns are refused)
- Cognitive framing (lens) shapes responses appropriately
- Working style matches the masque's design

## Directory Structure

```
evals/
├── README.md              # This file
├── .gitignore             # Excludes output files
├── codesmith/
│   ├── promptfooconfig.yaml   # Eval configuration
│   ├── prompt.txt             # Full masque prompt
│   └── tests/
│       ├── intent-boundaries.yaml
│       ├── teaching-behavior.yaml
│       └── working-style.yaml
├── chartwright/
│   └── ...
├── firekeeper/
│   └── ...
└── mirror/
    └── ...
```

## Prerequisites

Install promptfoo:

```bash
npm install -g promptfoo
```

Set your Anthropic API key:

```bash
export ANTHROPIC_API_KEY=your-key-here
```

## Running Evaluations

### Run a Single Masque's Tests

```bash
cd evals/codesmith
promptfoo eval
```

Or from the repo root:

```bash
promptfoo eval -c evals/codesmith/promptfooconfig.yaml
```

### View Results

After running an eval, view the interactive results:

```bash
promptfoo view
```

This opens a web UI showing pass/fail for each test case.

### Run All Evaluations

```bash
for dir in evals/*/; do
  if [ -f "$dir/promptfooconfig.yaml" ]; then
    echo "Running $dir..."
    promptfoo eval -c "$dir/promptfooconfig.yaml"
  fi
done
```

## Test Structure

Each masque has a `promptfooconfig.yaml` that defines:

```yaml
description: "Masque Name Evaluation Suite"

prompts:
  - id: baseline
    label: "Baseline (no masque)"
    raw: "{{message}}"
  - id: masque-name
    label: "MasqueName v0.1.0"
    file: file://prompt.txt

providers:
  - id: anthropic:messages:claude-sonnet-4-5-20250929
    config:
      temperature: 0
      max_tokens: 1024

tests:
  - file://tests/intent-boundaries.yaml
  - file://tests/working-style.yaml
```

### Test File Format

Test files use promptfoo's YAML format:

```yaml
- description: "Test description"
  vars:
    message: "User input to test"
  assert:
    - type: llm-rubric
      value: |
        Evaluation criteria for the response.
        Score 1 if criteria met, 0 if not.
```

## Adding Tests for a New Masque

1. Create the directory structure:
   ```bash
   mkdir -p evals/your-masque/tests
   ```

2. Create `prompt.txt` with the full masque prompt (lens + context + intent):
   ```bash
   # Extract from your masque YAML
   ```

3. Create `promptfooconfig.yaml`:
   ```yaml
   description: "YourMasque Evaluation Suite"

   prompts:
     - id: baseline
       raw: "{{message}}"
     - id: your-masque
       file: file://prompt.txt

   providers:
     - id: anthropic:messages:claude-sonnet-4-5-20250929
       config:
         temperature: 0

   tests:
     - file://tests/intent-boundaries.yaml
   ```

4. Create test files in `tests/`:
   - `intent-boundaries.yaml` — test denied patterns are refused
   - Add additional test files for other behavioral dimensions

5. Run and iterate:
   ```bash
   promptfoo eval -c evals/your-masque/promptfooconfig.yaml
   promptfoo view
   ```

## Interpreting Results

- **Pass (green)**: The masque exhibited the expected behavior
- **Fail (red)**: The masque didn't match expectations
- **Baseline comparison**: Shows how behavior differs from vanilla Claude

A masque should show clear behavioral differentiation from baseline, particularly on intent boundary tests.

## Tips

- Use `temperature: 0` for reproducible results
- Keep test prompts short and focused on one behavior
- Write rubrics that are specific and measurable
- Compare against baseline to ensure masque adds value
