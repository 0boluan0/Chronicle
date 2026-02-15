# Chronicle Master Requirement (From PRD)

## 1. North Star
Chronicle 是一个 **纯离线（offline-first）** 的 macOS 菜单栏时间线活动追踪器。
核心价值：
- 自动记录用户在 Mac 上的活动上下文（App + Window Title + Idle）。
- 允许用户用快速标记（Marker）补充上下文。
- 基于用户规则自动分类（Tagging）。
- 以时间线与统计视图帮助用户复盘时间分配。
- **所有数据仅本地保存，不上传、不联网、不遥测。**

本文件为 **AI2（测试与派发）唯一产品北极星依据**。
AI2 下发给 AI1 的每条任务都必须与本文件一致。

## 2. Product Invariants (Hard Constraints)
以下为不可违反的产品硬约束：
1. Offline-only: 禁止新增任何网络依赖、在线 API 调用、遥测或自动更新检查。
2. Local data only: 活动数据、规则、设置必须本地持久化（SQLite + 本地规则文件）。
3. Privacy first: 必须支持权限提示与降级（无权限时给出明确状态，不静默失败）。
4. Deterministic behavior: 规则引擎与时间线聚合结果必须可预测、可复现。
5. Stability gate: 任意功能迭代不得破坏现有测试可运行性。
6. Small-slice delivery: 每轮只做一个可验证的小切片，避免大范围重构。

## 3. PRD Must-Have Functional Scope

### 3.1 Continuous Activity Logging
必须实现并保持稳定：
- 实时记录前台 App 与窗口标题变化。
- 记录每段会话的 start/end 时间。
- 当用户空闲超过阈值（默认 5 分钟，可配置）生成 Idle 段。
- 上下文切换（App 切换或窗口标题变化）应产生新的会话边界。

### 3.2 Session Merging Rules
- 相邻且上下文相同的会话应合并，避免重复碎片。
- 被 Idle 或其他 App 打断后回到同一上下文，必须视为新会话。
- 手动 Marker 不应强制切断会话（Marker 是注释层，不是会话层）。

### 3.3 Manual Marker
- 支持快速添加 Marker（菜单栏入口 + 全局快捷键）。
- Marker 需带文本与精确时间戳。
- Marker 要可在时间线可视化，并可持久化。
- 需支持基本编辑/删除能力（至少可删除误加项）。

### 3.4 Rule Engine (Auto Tagging)
- 规则条件至少支持：App 名、窗口标题 contains（大小写不敏感）。
- 支持优先级，冲突时高优先级胜出。
- 同优先级需有确定性 tie-break（不能随机）。
- 规则修改后对新数据立即生效；历史重算能力为高优先级可选项。

### 3.5 Stats & Time Ranges
- 提供日/周/月/年统计汇总。
- 至少支持按 Tag 或 App 的时长聚合。
- Idle 在统计中可见（默认纳入）。

### 3.6 Persistence
- 核心数据写入 SQLite，支持长期运行与查询性能。
- 规则文件采用本地可编辑格式（YAML/JSON）。

## 4. PRD Non-Goals (Current Stage)
以下默认不进入当前迭代：
- 云同步、多人协作、任何服务端能力。
- 跨平台客户端（仅 macOS Apple Silicon 优先）。
- 大规模视觉重设计（除非直接阻塞当前功能闭环）。

## 5. Current Delivery Order (Execution Priority)
AI2 派发任务时，默认按以下顺序推进：
1. 测试稳定性与回归安全（必须始终满足）
2. Quick Marker 端到端闭环（当前目标：FEAT-001）
3. 规则引擎正确性与可解释性
4. 统计汇总正确性（day/week/month/year）
5. 隐私与可控性（ignore list、权限状态、本地数据可见性）

## 6. AI2 Dispatch Policy (Must Follow)
每轮 AI2 必须：
1. 先运行基线测试并更新 failure 视图。
2. 若存在 open failure：按 P0 > P1 > P2 派发修复，不得派发新功能。
3. 若无 open failure：派发 backlog 中最高优先级 ready feature。
4. 派发命令必须包含：Objective / Scope In / Scope Out / Required Tests / Acceptance。
5. 派发命令必须显式约束 AI1 不越界重构。

## 7. Definition of Done (Product + Pipeline)
一个目标任务可标记 done，至少满足：
1. 对应功能达到 PRD 最小可用行为。
2. 相关测试通过，且全量测试可运行并可判定。
3. 未违反 Offline/Privacy/Local-data 三大约束。
4. `open_failures.yaml` 中 blocking failures 为 closed。
5. `next_command.md` 与 `cycle report` 已完整记录决策与证据。

整体流程可停止（terminal）需同时满足：
- 目标任务 ID（`GOAL_TASK_IDS`）全部完成。
- 无 blocking open failures。
- AI2 将 `next_command.md` 写为 `Task DONE` 或 `Task NONE`。

## 8. Engineering Guardrails
- 默认不新增数据库迁移，除非任务明确需要且有回滚/兼容说明。
- 禁止“顺手”改动与当前任务无关的模块。
- 优先最小改动实现可验证结果。
- 所有关键决策应可在 `ops/ai-pipeline/reports/cycle-<N>.md` 追溯。

## 9. Source of Truth
本文件依据以下 PRD抽取：
- `Product Requirements Document_ Offline Timeline Activity Tracker (macOS).pdf`

如与临时需求冲突，以本文件 + 当前 backlog 显式任务为准；
任何偏离都应先由 AI2 在派发命令中写明原因与边界。
