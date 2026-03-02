<p align="center">
  <img src="Chronicle/Assets.xcassets/AppIcon.appiconset/appicon_128.png" width="96" height="96" alt="Chronicle app icon">
</p>

<h1 align="center">Chronicle</h1>

<p align="center">
  Fully offline macOS menubar work timeline — auto-capture app sessions, add context with quick markers and tag rules, then export Markdown/CSV into your review workflow.
</p>

<p align="center">
  <a href="https://github.com/0boluan0/Chronicle/releases/latest">
    <img src="https://img.shields.io/github/v/release/0boluan0/Chronicle?display_name=tag&sort=semver&style=flat-square" alt="Release">
  </a>
  <a href="https://github.com/0boluan0/Chronicle/releases">
    <img src="https://img.shields.io/github/downloads/0boluan0/Chronicle/total?style=flat-square" alt="Downloads">
  </a>
  <a href="https://github.com/0boluan0/Chronicle/actions/workflows/ci.yml">
    <img src="https://img.shields.io/github/actions/workflow/status/0boluan0/Chronicle/ci.yml?branch=main&style=flat-square" alt="CI">
  </a>
  <img src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&style=flat-square" alt="macOS 14+">
  <img src="https://img.shields.io/badge/offline-only-2ea44f?style=flat-square" alt="Offline only">
</p>

<p align="center">
  <a href="#download">Download</a> ·
  <a href="#features">Features</a> ·
  <a href="#custom-csv-analysis">Custom CSV Analysis</a> ·
  <a href="#privacy--data">Privacy &amp; Data</a> ·
  <a href="#build--test">Build</a>
</p>

<details>
  <summary><b>中文简介</b></summary>
  <br>
  Chronicle 是一款完全离线的 macOS 菜单栏工作时间轴。它自动记录你在电脑上做了什么，再用快捷标记与标签规则补齐“上下文”，最后一键导出 Markdown/CSV 进入你的复盘与写作流程。数据保存在本地 SQLite，不做联网同步。
</details>

## Download

- Get the latest DMG from [Releases](https://github.com/0boluan0/Chronicle/releases/latest).
- Install: open the DMG, drag `Chronicle.app` into `/Applications`.
- First run: if Gatekeeper warns, right-click the app → **Open**.

## Features

- Menubar popover: **Timeline** + **Stats** for quick checks.
- Dashboard window: **Timeline / Overview / Stats / Markers** for deeper browsing.
- Foreground app tracking + idle detection; data stored in **SQLite**.
- Markers: point note + interval session; hotkey `⌥⌘M` for quick entry.
- Tagging: rules + app mappings + manual overrides; stats/exports use effective tags.
- Export: CSV + Markdown daily/weekly reports with editable templates and folder bookmarks.
- Language: English + 简体中文 (switch in Preferences).

## Permissions

- **Accessibility permission** is required only if you enable window-title capture.
- Window-title capture is **off by default**.

## Privacy & Data

- 100% offline: no network sync.
- Data is stored in **Application Support** as a local SQLite database.

## Build & Test

- Open `Chronicle.xcodeproj` in Xcode.
- Select the `Chronicle` scheme and Run.
- Run tests:
  - `xcodebuild -project Chronicle.xcodeproj -scheme Chronicle -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`

## Custom CSV Analysis

Chronicle exports CSV with stable technical fields (`start_time`, `end_time`, `duration`, `app_name`, `is_idle`, tag fields).  
You can run local scripts to build your own analytics:

- `python3 scripts/csv-analysis/tag_time_report.py --csv /path/to/export.csv`
- `python3 scripts/csv-analysis/switch_transition_report.py --csv /path/to/export.csv`
- `python3 scripts/csv-analysis/focus_block_report.py --csv /path/to/export.csv --min-minutes 25`

See [`scripts/csv-analysis/README.md`](scripts/csv-analysis/README.md) for details.

### Contributing Analysis Scripts

- Keep scripts reproducible and offline-only.
- Prefer Python standard library only (no heavy dependencies by default).
- Accept input via CLI flags (at least `--csv`) and print deterministic text/CSV output.
- Document expected CSV columns and include one runnable example in script help or README.
- If a script depends on optional tools (e.g. pandas/notebook), place it in a separate folder with setup notes.

## Current Status

This project is under active development. Expect frequent changes and occasional breakage while backend refactors land.

## Docs

- `UI-design.md` (UI notes and architecture)
- `Product Requirements Document_ Offline Timeline Activity Tracker (macOS).pdf` (PRD)
- `docs/migrations-and-upgrades.md` (DB migration and rollback policy)
- `docs/data-safety.md` (data location, backup, and upgrade validation)
- `docs/privacy-and-permissions.md` (privacy promise, permissions, and data removal)
- `docs/update-strategy.md` (manual GitHub updates vs Sparkle recommendation)
- `docs/stable-release-checklist.md` (non-breaking upgrade and rollback checklist)

## Checklists

<details>
  <summary><b>Release Checklist</b></summary>
  <br>

- Window titles are captured (when enabled) and written into Raw Events and Activities.
- Auto-export does not retry within the same day/week after a failure; failures are visible in Export status.
- Export UI has no obvious unlocalized strings in English/Chinese.
- Menubar popover remembers the last selected tab.
- No new database migrations are introduced.
</details>

<details>
  <summary><b>Internal Beta Checklist</b></summary>
  <br>

- First launch onboarding appears once; can be reopened from the menubar menu (“Welcome…”).
- Popover can open Dashboard and Preferences from the top header buttons.
- Hotkey `⌥⌘M` creates both a point marker and an interval marker (start + stop).
- Auto daily/weekly export does not retry within the same day/week after a failure (status visible in Export UI).
- English/Chinese switch: Popover / Preferences / Export has no obvious unlocalized strings.
- Wipe data in Preferences > Privacy, then restart: database reinitializes and app functions normally.
</details>

<details>
  <summary><b>中文检查清单</b></summary>
  <br>

- 窗口标题采集开启后，已写入 Raw Events 与 Activities。
- 自动导出失败后同一天/同一周不重复尝试，失败状态在导出页面可见。
- 导出界面无明显未本地化字符串（中英文切换正常）。
- 菜单栏弹窗会记住上次选中的标签页。
- 未新增数据库迁移。
- 首次启动会出现上手引导；完成后不再出现，并可从菜单栏菜单“欢迎…”重新打开。
- Popover 顶部可直接打开仪表盘与偏好设置。
- 快捷键 `⌥⌘M` 可分别创建一次点标记与一次区间标记（开始 + 结束）。
- 中英文切换：Popover / 偏好设置 / 导出页面无明显未本地化字符串。
- 在 偏好设置 > 隐私 清除数据并重启后：数据库可重新初始化，功能正常可用。
</details>
