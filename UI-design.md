# Chronicle UI Architecture

This document describes the implemented Chronicle 1.1 UI shape. The earlier dashboard-and-reports redesign plan is retired; product boundaries are defined by [docs/product-constitution.md](docs/product-constitution.md), domain terms by [CONTEXT.md](CONTEXT.md), and durable product decisions by [docs/adr](docs/adr).

## Application shell

Chronicle is a native macOS SwiftUI application with AppKit integration where the platform requires it.

- `AppDelegate` owns the menu-bar status item, transient controller popover, tracking lifecycle, and AppKit menus.
- SwiftUI window scenes provide the main window, Settings, onboarding, and quick capture.
- `AppWindowRouter` is the single routing boundary for opening those surfaces.
- `AppActivationCoordinator` changes the activation policy dynamically: Chronicle behaves as a menu-bar accessory when no standard window is visible and presents a Dock presence while a standard window is open.
- Window sizes, restoration, and localized titles are centralized in `AppWindowScenes.swift`.

The menu-bar popover is deliberately a light controller. It shows archive/tracking state, pending-review status, quick actions, and navigation into full windows; it is not a miniature analytics dashboard.

## Primary information architecture

The main window uses a `NavigationSplitView` with five user-facing destinations:

1. **Pending Review** — the default view for proposed work blocks after the latest checkpoint. Users may correct titles, tags, boundaries, splits, and merges before completing an immutable review snapshot.
2. **Timeline** — searchable reviewed work-block history. Raw activity is subordinate, expandable evidence.
3. **Notes** — point notes, interval notes, manual work blocks, and note history.
4. **Insights** — descriptive time, distribution, switching, and trend views. It does not score or judge the user.
5. **Export & Integrations** — one-way Markdown/CSV export, managed-block settings, destinations, and export history.

The corresponding view boundaries are `PendingReviewView`, `WorkBlockTimelineView`, `NotesLibraryView`, `WorkBlockInsightsView`, and `ExportIntegrationsView`. `DashboardView` is the main-window container retained for code continuity; “Dashboard” is not a separate product destination.

## Secondary surfaces

### Quick capture

`QuickMarkerPanelView` and `QuickMarkerEntryView` support point notes, interval notes, and manual work blocks. Quick capture is reachable from the menu bar, app commands, and the main-window toolbar.

### Settings

`PreferencesView` uses a sidebar with General, Privacy, Tags, and Support. Debug-only controls may appear in development builds. Settings holds collection policy, the window-title allowlist, local counters, app/tag classification, archive health, diagnostics, and destructive data controls; export workflow belongs in Export & Integrations.

### Onboarding

`OnboardingView` explains local ownership, tracking, window-title permission, and the review workflow. Permission requests must remain contextual: Accessibility is needed only when allowlist-based window-title capture is active.

## Interaction and content rules

- Separate observed **Activity Evidence** from user-confirmed **Work Blocks** in labels and hierarchy.
- Keep Pending Review usable without requiring notes, tags, or export.
- Treat a completed review snapshot as immutable. Revision must be an explicit preview-and-re-review flow.
- Show raw evidence as supporting detail, never as a claim about intent or productivity.
- Capture window titles only for applications on the explicit allowlist; app-level evidence remains the privacy-degraded baseline.
- Make export state and partial success visible, but never make review completion depend on export.
- Keep managed Markdown ownership explicit and warn that files outside the Chronicle archive are plaintext.
- Surface archive startup failures with a retry/recovery path; never replace an unreadable archive with an empty UI state.
- Use confirmation for destructive actions, especially raw-evidence deletion and archive wipe.

## Visual and accessibility system

`Chronicle/DesignSystem/DesignSystem.swift` contains shared spacing, colors, status tones, surfaces, and controls. New UI should prefer those primitives and system colors/SF Symbols over page-specific styling.

All release surfaces support English and Simplified Chinese. Interactive elements need stable accessibility identifiers, meaningful labels, keyboard reachability, and layouts that tolerate localized text growth. Fixed action groups should remain non-lazy when UI automation or accessibility must discover every child deterministically.

## State and service boundaries

- `AppState` exposes user-visible runtime and preference state.
- `DatabaseService` and its domain extensions own SQLCipher-backed persistence; views do not bypass that boundary.
- `WorkBlockBuilder`, `WorkBlockProjectionService`, and `ReviewCompletionService` implement the evidence → work-block → review-snapshot flow.
- `ReportService`, `ReviewMarkdownExportService`, and `CoordinatedFileWriter` implement ordinary and reviewed exports.
- Notifications refresh UI after tracking, projection, review, or archive-recovery events.

The encrypted Chronicle archive is authoritative. UI state may cache or project archive data, but exported files and view-local state must not become an alternative source of truth.

## Verification

- Run unit tests with `./script/run_unit_tests.sh`.
- Run the bilingual public UI path with `./script/run_ui_smoke.sh all`.
- Run every release UI surface independently in both languages with `./script/run_ui_smoke.sh full`.

The UI runner uses isolated Application Support, export, database-key, and preferences fixtures. Passing a build-only check is not equivalent to passing runtime UI automation.
