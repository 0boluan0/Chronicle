# Chronicle Work Journal

Chronicle turns local activity evidence into a personal, reviewable history of work. Its language separates what the computer observed from what the user has confirmed.

## Evidence and work

**Activity Evidence**:
A time-bounded observation of the foreground application and, when explicitly allowed for that application, its window title. Evidence supports a work block but is not itself a statement of user intent.
_Avoid_: Task, work item, productivity event

**Work Block**:
A continuous span of related context assembled from activity evidence or added manually by the user. A work block may be renamed, split, merged, and tagged without rewriting its underlying evidence.
_Avoid_: Session, task, insight

**Automatic Work Block**:
A work block proposed from activity evidence by Chronicle's transparent local rules.
_Avoid_: AI task, inferred goal

**Manual Work Block**:
A user-authored work block that fills time or context Chronicle could not observe, including work away from the Mac.
_Avoid_: Fake activity, correction event

**Note**:
User-authored text attached to a moment, interval, or work block. A note is optional context and is never required to complete a review.
_Avoid_: Report, journal entry

## Review

**Pending Review**:
Work blocks after the latest checkpoint that the user has not yet confirmed. Pending review can span multiple days.
_Avoid_: Today, inbox item, unexported work

**Review**:
The act of confirming and optionally correcting a range of work blocks. Review is independent of export and does not require notes or tags.
_Avoid_: Export, closeout, report generation

**Checkpoint**:
The end of the latest completed review range. It defines where pending review begins and only moves forward during an ordinary review.
_Avoid_: Last export time, sync cursor

**Review Snapshot**:
An immutable record of the effective work-block values confirmed in one completed review, together with its range, completion time, and optional note.
_Avoid_: Generated report, cached timeline

**Frozen Work Block**:
A work block captured by a review snapshot and therefore excluded from silent automatic rebuilding. Revising it requires an explicit re-review flow.
_Avoid_: Locked activity, archived row

## Boundaries

**Chronicle Archive**:
The local, encrypted, in-app source of truth for activity evidence, work blocks, notes, and review snapshots.
_Avoid_: Sync database, Obsidian vault

**Managed Export Block**:
A Chronicle-owned delimited region inside a Markdown file. Chronicle may replace only this region; text outside it remains owned by the user or another application.
_Avoid_: Two-way sync, whole-file export

**Window-title Allowlist**:
The set of applications for which the user explicitly permits document- or window-level context capture. Applications outside the set remain app-level evidence only.
_Avoid_: Capture blacklist, global title capture
