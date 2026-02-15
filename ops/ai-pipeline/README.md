# Chronicle AI Pipeline (V2)

This folder is the single source of truth for the two-AI workflow:

- `AI1 Builder`: implements only the command from `commands/next_command.md`.
- `AI2 QA Commander`: runs baseline checks, updates failures/status/report, then dispatches next command.

## Workflow

1. Run baseline:
   - `ops/ai-pipeline/scripts/run_baseline_and_extract.sh`
2. Update and review:
   - `failures/open_failures.yaml`
   - `baseline/test_baseline.md`
   - `status_board.md`
   - `reports/cycle-<N>.md`
3. Dispatch next task:
   - write `commands/next_command.md`
   - enforce highest-priority-open-failure rule
   - direct-dispatch to Codex:
     - `ops/ai-pipeline/scripts/dispatch_to_codex.sh`

## Artifacts

- Persistent artifacts are tracked in git (backlog, status, command, reports, failures, baseline summary).
- Raw per-run logs are written to `baseline/runs/` and intentionally git-ignored.

## Stage Gate

- Feature track remains blocked while any blocking stabilization failure is open.
- Unlock condition is defined in `backlog.yaml` (`STAB-001`, `STAB-002`, `STAB-003` all done).
