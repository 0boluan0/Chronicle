# Claude AI2 Direct Dispatch Runbook

Use this exact cycle each round.

## Step 1: Baseline
Run:

```bash
/Users/fengyihang/Chronicle/Chronicle/ops/ai-pipeline/scripts/run_baseline_and_extract.sh || true
```

## Step 2: Update AI2 artifacts
Update all of these files:

- `/Users/fengyihang/Chronicle/Chronicle/ops/ai-pipeline/failures/open_failures.yaml`
- `/Users/fengyihang/Chronicle/Chronicle/ops/ai-pipeline/status_board.md`
- `/Users/fengyihang/Chronicle/Chronicle/ops/ai-pipeline/reports/cycle-<N>.md`
- `/Users/fengyihang/Chronicle/Chronicle/ops/ai-pipeline/commands/next_command.md`

Rule: dispatch only the highest-priority open failure.

## Step 3: Dispatch directly to Codex
Run:

```bash
/Users/fengyihang/Chronicle/Chronicle/ops/ai-pipeline/scripts/dispatch_to_codex.sh
```

Optional dry run:

```bash
/Users/fengyihang/Chronicle/Chronicle/ops/ai-pipeline/scripts/dispatch_to_codex.sh --dry-run
```

## Step 4: Return concise decision
Output only:

1. `DECISION`
2. `NEXT_TASK_ID`
3. `DISPATCH_LOG`
