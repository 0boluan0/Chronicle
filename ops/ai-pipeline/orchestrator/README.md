# Chronicle Dual Codex Orchestrator

## Commands

```bash
bash /Users/fengyihang/Chronicle/Chronicle/ops/ai-pipeline/orchestrator/orchestrator.sh start
bash /Users/fengyihang/Chronicle/Chronicle/ops/ai-pipeline/orchestrator/orchestrator.sh status
bash /Users/fengyihang/Chronicle/Chronicle/ops/ai-pipeline/orchestrator/orchestrator.sh stop
bash /Users/fengyihang/Chronicle/Chronicle/ops/ai-pipeline/orchestrator/orchestrator.sh resume
```

## Dry Run

```bash
bash /Users/fengyihang/Chronicle/Chronicle/ops/ai-pipeline/orchestrator/orchestrator.sh start --dry-run
```

## Runtime Files

- State: `ops/ai-pipeline/runtime/state.yaml`
- Events: `ops/ai-pipeline/runtime/events/*.jsonl`
- Inbox: `ops/ai-pipeline/runtime/inbox/dispatch-<N>.json`
- Outbox: `ops/ai-pipeline/runtime/outbox/ai1-result-<N>.json`
- Logs: `ops/ai-pipeline/runtime/logs/*`

## Where To Put Master Requirements

- Edit this file:
  - `ops/ai-pipeline/contracts/master_requirement.md`
- The orchestrator injects this document into AI2 prompt every cycle.
- AI1 does not read this document directly; AI1 only follows `commands/next_command.md`.
- Path is configurable in:
  - `ops/ai-pipeline/orchestrator/config.env` (`MASTER_REQUIREMENTS_FILE=...`)
