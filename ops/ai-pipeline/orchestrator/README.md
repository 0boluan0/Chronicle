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
