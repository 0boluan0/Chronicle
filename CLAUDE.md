```
# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.
```

## Chronicle macOS App

Chronicle is a macOS menu bar app for offline activity tracking. It records foreground app sessions into SQLite and provides analytics through Timeline/Stats views and a Dashboard window.

## Development Commands

### Build and Run
- **Open in Xcode:** `open Chronicle.xcodeproj`
- **Run from Xcode:** Select `Chronicle` scheme and click Run (⌘R)
- **Build from command line:**
  ```bash
  xcodebuild -project Chronicle.xcodeproj -scheme Chronicle -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
  ```
- **Clean build:**
  ```bash
  xcodebuild -project Chronicle.xcodeproj -scheme Chronicle -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO clean build
  ```

### Testing
- **Run all tests from command line:**
  ```bash
  xcodebuild -project Chronicle.xcodeproj -scheme Chronicle -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
  ```
- **Run specific test class:**
  ```bash
  xcodebuild -project Chronicle.xcodeproj -scheme Chronicle -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:ChronicleTests/ClassName
  ```
- **Run specific test method:**
  ```bash
  xcodebuild -project Chronicle.xcodeproj -scheme Chronicle -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:ChronicleTests/ClassName/testMethodName
  ```

### Release
- **Build DMG locally:**
  ```bash
  chmod +x scripts/build_dmg.sh
  scripts/build_dmg.sh
  ```
  Outputs to `dist/Chronicle-dev.dmg`

- **GitHub Release:** Push a tag like `v1.0.0` to trigger the `Release DMG` workflow

## Code Architecture

### High-Level Structure
```
Chronicle/
├── App/                      # AppKit integration (AppDelegate, window controllers)
├── ContentView.swift         # Main popover view
├── ChronicleApp.swift        # SwiftUI app entry point
├── Services/                 # Core business logic
│   ├── Database/            # SQLite database operations (DatabaseService.swift)
│   ├── Tracking/            # Activity tracking services
│   ├── Reports/             # Report generation and export
│   ├── AggregationService.swift    # Stats aggregation
│   ├── HealthCheckService.swift    # Database health checks
│   ├── MarkerSpanService.swift     # Marker management
│   ├── TaggingEngine.swift         # Tagging logic
│   └── ...
├── Models/                   # Data models and database rows
├── Views/                    # SwiftUI views
│   ├── Dashboard*View.swift  # Dashboard windows
│   ├── PreferencesView.swift    # Settings UI
│   ├── TimelineView.swift       # Timeline display
│   ├── StatsView.swift          # Statistics views
│   └── ...
├── Components/               # Reusable UI components
├── DesignSystem/             # Design system and styling
├── Utilities/                # Helper functions and extensions
└── Resources/                # Assets, localization
    ├── en.lproj/
    └── zh-Hans.lproj/
```

### Core Services

#### Database Service (`Services/Database/DatabaseService.swift`)
- Singleton: `DatabaseService.shared`
- Provides CRUD operations for all data types (activities, tags, markers, app mappings, raw events)
- Uses SQLite with `GRDB.swift` library
- Key operations: `fetchActivities()`, `insertTag()`, `deleteMarker()`, etc.

#### Activity Tracking (`Services/Tracking/`)
- `ActivityTracker`: Records foreground app sessions
- `IdleDetector`: Detects user idle time
- `AppInfoProvider`: Fetches app metadata (bundle ID, name, icon)
- Emits `didRecordSessionNotification` when new sessions are saved

#### Aggregation Service (`AggregationService.swift`)
- Computes aggregated statistics from raw activity data
- Provides timeline items, summary stats, top apps/tags
- Methods: `fetchTimelineItems()`, `fetchSummaryStats()`, `fetchTopApps()`, etc.

#### Report Service (`Services/Reports/`)
- Generates CSV and Markdown reports
- Handles auto-export scheduling
- Methods: `generateDailyReport()`, `autoExportIfNeeded()`, `exportCSV()`

### UI Architecture

#### Main Entry Points
1. **Menu Bar Popover** (`ContentView.swift`)
   - Shows Timeline or Stats views via segmented control
   - Embeds `TimelineView` or `StatsView`
   - Remembers last selected tab

2. **Dashboard Window** (`DashboardWindowController.swift`)
   - Separate window with navigation sidebar
   - Views: Timeline, Overview, Stats, Markers, Debug
   - Uses `NavigationSplitView` for sidebar navigation

3. **Preferences Window** (`PreferencesWindowController.swift`)
   - Tab-based settings UI
   - Sections: General, Apps, Tags & Rules, Privacy
   - Uses `PreferencesView` with TabView

4. **Quick Marker Panel** (`QuickMarkerPanelController.swift`)
   - Floating panel for quick marker entry
   - Triggered by hotkey ⌥⌘M

#### State Management
- `AppState` (ObservableObject): Holds user preferences and UI state
- `UserDefaults` for persistence
- Published properties drive UI updates

### Data Flow

```
User Action → View → Service → Database → Service (notify) → View updates
```

Examples:
- Adding a marker: QuickMarkerPanelView → MarkerSpanService → DatabaseService → Notification → TimelineView refreshes
- Changing preferences: PreferencesView → AppState → UserDefaults
- Viewing stats: StatsView → AggregationService → DatabaseService → StatsView displays

### Key Technologies

- **SwiftUI**: Declarative UI for all views
- **AppKit**: Window/menu bar management
- **GRDB.swift**: SQLite ORM
- **Swift Concurrency**: Async/await for database operations
- **Combine**: Notification-based updates

### Database Schema

Main tables:
- `activities`: App usage sessions with start/end times, bundle ID, window title
- `tags`: User-defined tags with colors
- `tagRules`: Rules for automatic tagging
- `appMappings`: Manual tag overrides per app
- `markers`: Point and interval markers (notes, sessions)
- `markerSpans`: Marker interval data
- `rawEvents`: Unprocessed tracking events

### Development Notes

- The app runs without a Dock icon (LSUIElement = true)
- Window title capture requires Accessibility permission (disabled by default)
- Data is stored locally in `~/Library/Application Support/Chronicle/` (SQLite database)
- No network synchronization - fully offline
- Supports English and Simplified Chinese localizations

### CI/CD

- **GitHub Actions**: `.github/workflows/ci.yml` runs tests on all pushes
- **Release workflow**: `.github/workflows/release.yml` builds DMG on tag pushes
- **AI Pipeline**: `ops/ai-pipeline/` contains automation for AI-assisted development
