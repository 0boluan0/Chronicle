# Chronicle

**EN**
Chronicle is a macOS menu bar app for offline activity tracking. It records foreground app sessions into SQLite and provides a Timeline/Stats popover plus a larger Dashboard for analytics and browsing, with Preferences for tagging and exports.

**中文**
Chronicle 是一个 macOS 菜单栏离线活动追踪应用。它将前台应用会话记录到 SQLite，并提供 Timeline/Stats 弹窗与 Dashboard（分析与浏览），配置与导出在偏好设置中完成。

## Current Status / 当前状态

**EN**
- Menu bar popover with Timeline/Stats and a separate Dashboard window (Timeline / Overview / Stats / Markers / Debug).
- Foreground app tracking + idle detection; sessions, markers, tags, app mappings and raw events stored in SQLite.
- Tagging supports rules, app mappings and manual overrides; stats and reports use effective tags.
- Preferences: Apps mapping, Tags & Rules, and Export (CSV + Markdown daily/weekly reports with editable templates and security-scoped folder access).
- Backend refactors (normalization, replay, maintenance, aggregation) are in progress; some areas may still be unstable or under active development.

**中文**
- 菜单栏弹窗包含 Timeline/Stats，另有独立 Dashboard 窗口（Timeline / Overview / Stats / Markers / Debug）。
- 前台应用追踪 + Idle 检测；会话、标记、标签、App 映射与 Raw Events 存储在 SQLite 中。
- 标签系统支持规则、App 映射与手动覆盖；统计与导出使用“有效标签”。
- 偏好设置包含 Apps 映射、Tags & Rules、Export（CSV 导出 + Markdown 日报/周报，模板可编辑，使用安全书签访问目录）。
- 后端正在进行归一化/重放/维护/聚合等重构，部分功能仍在迭代中。

## Build & Run / 构建与运行

**EN**
- Open `Chronicle.xcodeproj` in Xcode.
- Select the `Chronicle` scheme and run.
- Run tests: `xcodebuild -project Chronicle.xcodeproj -scheme Chronicle -destination 'platform=macOS' test`

**中文**
- 用 Xcode 打开 `Chronicle.xcodeproj`。
- 选择 `Chronicle` scheme 并运行。
- 运行测试：`xcodebuild -project Chronicle.xcodeproj -scheme Chronicle -destination 'platform=macOS' test`

## Release (DMG) / 发布（DMG）

**EN**
- Local DMG: `scripts/build_dmg.sh` (outputs to `dist/`)
- GitHub Release: push a tag like `v1.0.0` to trigger `Release DMG` workflow.
- Required secrets for signing (no notarization):
  - `MACOS_CERT_P12` (base64 of Developer ID Application certificate .p12)
  - `MACOS_CERT_PASSWORD`
  - `MACOS_CODESIGN_IDENTITY` (e.g. `Developer ID Application: Your Name (TEAMID)`)

**中文**
- 本地 DMG：`scripts/build_dmg.sh`（输出到 `dist/`）
- GitHub Release：推送类似 `v1.0.0` 的 tag 触发 `Release DMG` workflow
- 签名所需 secrets（不做公证）：
  - `MACOS_CERT_P12`（Developer ID Application 证书 .p12 的 base64）
  - `MACOS_CERT_PASSWORD`
  - `MACOS_CODESIGN_IDENTITY`（示例：`Developer ID Application: Your Name (TEAMID)`）

## Data / 数据

**EN**
Chronicle stores data locally in Application Support (SQLite database). No network sync.

**中文**
Chronicle 数据保存在本地 Application Support（SQLite 数据库），不做联网同步。

## Notes / 备注

**EN**
This project is under active development. Expect frequent changes and occasional breakage while backend refactors land.

**中文**
本项目处于快速迭代阶段，后端重构期间可能出现不稳定或编译问题。
