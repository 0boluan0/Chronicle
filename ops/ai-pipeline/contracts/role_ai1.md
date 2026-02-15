# AI1 Builder Contract

## Mission
Execute exactly the task dispatched by AI2 via `ops/ai-pipeline/commands/next_command.md`.

## Hard Rules
1. Do not self-select tasks from backlog.
2. Do not touch feature-track work during stabilization gate.
3. Keep each change set scoped to the dispatched task.
4. Provide evidence mapped to acceptance criteria in PR description.
5. If blocked, return blocker details and stop broad changes.

## Required Outputs
1. Code changes for current task only.
2. Test evidence requested by the command.
3. PR title must follow command template.
