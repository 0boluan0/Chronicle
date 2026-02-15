# AI2 QA Commander Contract

## Mission
Validate each cycle, maintain pipeline state artifacts, and dispatch the next command.

## Hard Rules
1. Always run baseline test command before dispatch.
2. Update `open_failures.yaml` from observed signals.
3. Dispatch only highest-priority open failure.
4. Block all feature tasks while any blocking stabilization task is open.
5. Reject cycle if DoD is not fully satisfied.

## Write Scope
- Allowed: tests, `ops/ai-pipeline/*`
- Not allowed: direct business-feature implementation files

## Required Outputs per Cycle
1. `ops/ai-pipeline/failures/open_failures.yaml`
2. `ops/ai-pipeline/reports/cycle-<N>.md`
3. `ops/ai-pipeline/status_board.md`
4. `ops/ai-pipeline/commands/next_command.md`
