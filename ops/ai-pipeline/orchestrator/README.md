# Chronicle Dual Codex Orchestrator

## Commands

```bash
bash /Users/fengyihang/Chronicle/Chronicle/ops/ai-pipeline/orchestrator/orchestrator.sh start
bash /Users/fengyihang/Chronicle/Chronicle/ops/ai-pipeline/orchestrator/orchestrator.sh start --attach
bash /Users/fengyihang/Chronicle/Chronicle/ops/ai-pipeline/orchestrator/orchestrator.sh status
bash /Users/fengyihang/Chronicle/Chronicle/ops/ai-pipeline/orchestrator/orchestrator.sh stop
bash /Users/fengyihang/Chronicle/Chronicle/ops/ai-pipeline/orchestrator/orchestrator.sh resume
bash /Users/fengyihang/Chronicle/Chronicle/ops/ai-pipeline/orchestrator/orchestrator.sh monitor
```

## Dry Run

```bash
bash /Users/fengyihang/Chronicle/Chronicle/ops/ai-pipeline/orchestrator/orchestrator.sh start --dry-run
bash /Users/fengyihang/Chronicle/Chronicle/ops/ai-pipeline/orchestrator/orchestrator.sh start --dry-run --attach
```

## Real-Time Monitor

Recommended workflow:

```bash
# Terminal 1
bash /Users/fengyihang/Chronicle/Chronicle/ops/ai-pipeline/orchestrator/orchestrator.sh start

# Terminal 2
bash /Users/fengyihang/Chronicle/Chronicle/ops/ai-pipeline/orchestrator/orchestrator.sh monitor
```

You can also attach immediately:

```bash
bash /Users/fengyihang/Chronicle/Chronicle/ops/ai-pipeline/orchestrator/orchestrator.sh start --attach
```

Monitor hotkeys:

- `s`: stop orchestrator
- `u`: resume orchestrator
- `r`: restart (`stop` then `start`)
- `q`: quit monitor only
- `1`: toggle events panel
- `2`: toggle logs panel
- `a`: toggle AI1 log panel
- `b`: toggle AI2 log panel
- `n`: switch events lines (`10/30/100`)
- `h`: toggle help panel

Alert rules:

- Entered `WORKER_EXIT` / `FUSE_STOP` / `BUDGET_STOP`
- Latest event `level=error`
- Any worker transitions `alive -> dead`

Alert behavior:

- Red highlighted alert line
- Terminal bell (`\a`)
- Deduplicated to avoid repeated beeps for the same alert

Troubleshooting:

- No sound: check terminal bell settings
- No color: check terminal ANSI support
- Missing command tools: ensure `jq`, `awk`, `sed`, `tail`, `tput` are installed

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
