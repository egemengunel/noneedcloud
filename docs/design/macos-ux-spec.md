# NoNeedCloud for macOS — UX & Interaction Spec

**Status:** Draft v1 · 2026-11-22
**Audience:** macOS developer(s) building `apps/macos`
**Companion to:** `docs/PRD.md` (what to build). This document covers *how it should look, flow and feel*, plus the backup-progress model the UI depends on.

> Scope note: iOS/iPadOS is out of scope for v1 (PRD NG1). Where a decision affects a future iOS client, it is called out with **iOS later**.

---

## 1. Design principles

1. **One window, one primary action.** The main window is the whole app. Setup, running and "all good" states live in the same surface; there is always exactly one primary button.
2. **Setup is part of the main screen, not a separate wizard.** The user builds their configuration in place and sees it fill up.
3. **Show the work.** During a backup, always show which file, which stage, how many left and roughly how long. Never leave the user wondering whether it froze.
4. **Safe by default.** Nothing in iCloud is ever touched. The backup only grows unless the user explicitly turns on mirroring. Destructive actions are visually marked and confirmed.
5. **Progressive disclosure.** Common options are toggles; advanced options sit behind a popover or secondary control.
6. **Make protection feel personal.** The "protected" state should show the user's own library back to them (counts, oldest memory, growth), not just a timestamp.

---

## 2. Information architecture

```
Main window
├── Header: app name/logo · [History] button (top-right)
├── Status area  ← changes with state (see §3)
├── "Your Setup" list (always visible)
│     Photos       <count> items      [Configure…] [toggle]
│     Files        <count> items      [Configure…] [toggle]
│     Destination  <name / not set>   [Configure…]
│     Schedule     <summary / off>    [Configure…]
└── Primary button: Start Backup | Stop

Sheets (modal over main window, main window stays visible behind)
├── Photos Settings      (+ Mirroring popover)
├── Source Folders
├── Destination Settings (+ Add Destination menu)
└── Schedule             (popover on macOS)

Other surfaces
├── Backup History window (runs, per-run detail, failed items)
├── Menu bar extra (status + Start/Stop + Show app)
└── Settings window (notifications, support/diagnostics)
```

Sheet footer convention: left = secondary/reset action (`Reset to Defaults`, `Remove All`), right = `Done`.

---

## 3. Main window states

| State | Status area | Primary button |
|---|---|---|
| **Setup 1/3 — What to protect** | 3-segment progress (Sources → Destination → First backup), card: title, one-line explanation, buttons `Allow Photos Access` / `Choose Folders…` | Start Backup (disabled) |
| **Setup 2/3 — Where to keep it** | Card: explanation + `Choose Destination…` | Start Backup (disabled) |
| **Setup 3/3 — First backup** | Card: summary of sources → destination, expectation note for first run (see §6.3) | **Start Backup** (enabled) |
| **Running** | Big percent + progress bar · "About N min" · "N items to go" · current-file row with stage indicator (§5) · 4 live tiles | **Stop** (same position) |
| **Protected** | Sentence headline: "Last backup <relative time>" + one-line context (sources → destination) · statistics tiles (§4) | Start Backup |
| **Needs attention** | Same as Protected but headline in warning style with a single fix action (destination missing, permission revoked, last run failed, backup stale) | Fix action or Start Backup |

Rules:
- "Your Setup" rows show `Not configured` / `Off` explicitly during setup so the user sees what is missing.
- The primary button never moves; only its label/role changes.
- **Needs attention** is new relative to the PRD; it is driven by the health checks in §6.

---

## 4. Statistics tiles (Protected state)

A grid of 6–8 tiles (2 rows × 4 on a standard window). Each tile: large value, small label, a tinted background, and an optional tiny visualization (sparkline, dots, bar).

**Functional tiles (required):**
- Photos protected — total count ("All 172,000")
- Files protected — total count
- Protected since — date of first successful run
- Added since first run — item delta

**Personal tiles (pick a set, design our own):**
- Oldest item in the backup (e.g. "18 years ago")
- Most active weekday / month for new photos
- Largest recent item
- Total size on destination

Design our own visual language for tiles (palette, glyphs, mini-charts). Do not reuse third-party artwork or labels.

Running state uses 4 live tiles: protected so far · running for · new items copied · started at.

---

## 5. Backup progress model (what the UI binds to)

The UI must not compute progress itself; the engine publishes a single observable progress value.

### 5.1 Per-item pipeline

Every item goes through the same stages, shown in the current-file row:

```
Enumerate → Check → Fetch → Write → (Release)
```

| Stage | Meaning | Notes |
|---|---|---|
| Enumerate | Build the work list from PhotoKit / folder scan | Produces `totalItems` before copying starts |
| Check | Compare item to destination (identifier, size, modification date) | Unchanged → skipped; still counts as processed |
| Fetch | Make the original available locally (PhotoKit network access / iCloud Drive download) | Usually the slowest stage for offloaded items |
| Write | Stream to a temp name at the destination, then atomic rename | Cloud destinations: provider upload |
| Release | Evict downloaded iCloud Drive files again (smart offloading) | Photos: system decides when to free space |

### 5.2 Published state (suggested shape)

```swift
struct BackupProgress: Sendable {
    var phase: Phase              // .enumerating, .copying, .finishing, .cancelled, .finished
    var totalItems: Int?          // nil while enumerating
    var processedItems: Int       // checked + copied + skipped + failed
    var copiedItems: Int          // new or changed items written
    var failedItems: Int
    var bytesWritten: Int64
    var currentItem: CurrentItem? // relative path + stage
    var startedAt: Date
    var estimatedRemaining: TimeInterval?
}
struct CurrentItem: Sendable { var displayPath: String; var stage: Stage }
enum Stage: Sendable { case check, fetch, write, release }
```

- `fractionCompleted = processedItems / totalItems` (show indeterminate bar while `totalItems == nil`).
- **ETA:** rolling average of item throughput over the last ~60 s (or last N items), not since start. Hide ETA for the first ~20 s and while throughput is unstable. Skipped items process much faster than copied ones, so the window must be recent.
- **UI throttle:** coalesce updates to ~4–5 per second for the window; ~1 per second for the menu bar. The engine may publish faster.
- **Single source of truth:** main window, menu bar extra and (later) Live Activity all observe the same object.

### 5.3 Interruption & resume

- Stop: finish or abandon the current item cleanly (no partial file at the final name), then mark the run `cancelled`.
- Next run starts with a fresh enumeration; Check skips what already exists, so it effectively resumes.
- Failed items are recorded with a human-readable reason and retried next run (PRD FR-E4).

---

## 6. Gaps to beat (differentiators)

Ordered by user value. These are opportunities the PRD does not yet cover or only lists as backlog.

### 6.1 Restore flow (highest value)
- In-app **Backup Browser**: grid/timeline of backed-up items, filter by date and type.
- **Restore to Photos**: import selected items back via PhotoKit into a new album; keep Live Photo image + movie paired automatically.
- **Restore to folder**: copy selected files to a chosen location.
- Plain files on disk remain the fallback (README principle 2).

### 6.2 Backup health & verification
- Health summary in the Protected state: last success, last verification, items failing.
- `Verify Backup` action: re-read destination files and compare size / checksum against the source.
- "Backup is stale" detection (no successful run in N days) drives the **Needs attention** state and a notification.

### 6.3 First-run expectations
- Before the first run, estimate library size and time; show a checklist: keep the Mac awake and on power, prefer a directly connected drive.
- During the first run, show progress in a way that survives long durations (days), e.g. "Day 1 of ~2".

### 6.4 Destination preflight
- When adding a destination: check reachability, write permission, file system compatibility, free space vs. estimated library size.
- Plain-language error messages with a suggested fix (e.g. "This drive's format can't store files larger than 4 GB. Reformat as APFS or exFAT.").

### 6.5 Encryption for cloud destinations
- Optional client-side encryption for S3 / Google Drive / OneDrive; key in Keychain; explicit recovery-key flow during setup.

### 6.6 Metadata the plain copy loses
- Albums, favorites, captions/keywords and dates/locations edited inside Photos are not in the original files.
- Option: per-item sidecar (XMP or JSON) and/or album folders, links or index (PRD NG4/backlog).

### 6.7 Notifications & glanceable surfaces
- Local notifications: run finished (summary), run failed, backup stale.
- macOS widget: last backup + health.

### 6.8 Background reliability
- Run scheduled backups from a login item / helper (`SMAppService`) so they do not depend on the main window being open.

**iOS later:** in-app scheduling is restricted on iOS; plan for a guided Shortcuts automation setup, background processing while charging, Live Activity, widgets, and the same destination folder layout so Mac and iPhone backups can share a destination without duplicate copies.

---

## 7. Copy & tone

- Sentence-case titles ("Where to keep your data"), short explanatory subtitles.
- Calm and factual. Explain *why* (iCloud syncs; it is not a backup) once during onboarding, not on every screen.
- Use "protected" / "safe" for completed items; avoid alarmist language except in **Needs attention**.
- Write all copy fresh; do not reuse wording from other products.

---

## 8. Platform surfaces checklist (macOS v1)

- [ ] Main window with states from §3
- [ ] Sheets: Photos, Source Folders, Destination, Schedule
- [ ] Mirroring popover with retention picker, Deleted-folder size and `Empty Now` (destructive, confirmed)
- [ ] Backup History window with per-run detail and failed items
- [ ] Menu bar extra: state icon, progress, Stop, Start plan…, Show app
- [ ] App Intents: Start / Stop / Current / Last backup (PRD FR-S2)
- [ ] Notifications (§6.7)
- [ ] Help → Contact Support with an attachable diagnostic log (no file contents)
