# Chronicle product constitution

Chronicle is a fully offline macOS automatic work log. It turns application and explicitly permitted window-level activity into auditable work blocks so people can review a day or week without reconstructing it from memory.

## Non-negotiable shape

- Single-user, native macOS software with no account requirement.
- The encrypted local Chronicle archive is the source of truth.
- Activity data never leaves the Mac; there is no remote telemetry, cloud sync, remote AI, or team monitoring.
- Activity evidence supports work blocks but never claims to know the user's goal or productivity.
- Work blocks and completed review snapshots are the core domain. A completed snapshot is immutable; already reviewed history is not silently rebuilt.
- Window titles are captured only for applications the user explicitly allows. App-level capture remains a useful privacy-degraded mode.
- The menu bar is a light controller. Review, history, notes, insights, and integrations belong in the main window.
- Export is optional and independent of review. Markdown integration is one way and modifies only a clearly delimited managed block. The reviewed projection owns canonical `YYYY-MM-DD.md` / `daily-YYYY-MM-DD`; template-based daily reports use `YYYY-MM-DD-report.md` / `report-daily-YYYY-MM-DD` and never share that namespace.
- Insights describe patterns; they do not score, rank, coach, or judge the user.

## Product hierarchy

1. **Pending Review** — the default destination, grouped by day from the latest checkpoint onward.
2. **Timeline** — searchable work-block history; raw activity appears only as expandable evidence.
3. **Notes** — user-authored notes and manual work blocks.
4. **Insights** — descriptive time, distribution, switching, and trend views.
5. **Export & Integrations** — formats, templates, folders, and export history.

## Review contract

A review may correct titles, tags, boundaries, splits, and merges, but notes and tags remain optional. Completing a review copies the effective work blocks into an immutable snapshot and advances the checkpoint. Unreviewed blocks may be regenerated transparently; reviewed blocks require an explicit preview and re-review flow. The user may delete raw evidence for a reviewed range after a warning, while the review snapshot remains available.

## Community boundary

Chronicle is an open-source, personal-origin community project licensed under the root MIT License. Community priorities are welcome inside this constitution; requests that turn it into cloud project management, employee monitoring, team analytics, or productivity scoring are out of scope.
