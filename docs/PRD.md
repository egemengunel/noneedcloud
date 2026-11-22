# PRD: No Need Cloud for Mac (Reverse-Engineered Clone)

**Status:** Draft v1
**Date:** 2026-11-22
**Source:** Reverse-engineered from https://parachuteapps.com/parachute (v2.0.2, $14.99 one-time, macOS 15+)
**Goal:** Build a functionally equivalent macOS app — codename **NoNeedCloud** — that automatically backs up iCloud Photos and iCloud Drive to storage the user owns.

---

## 1. Problem Statement

iCloud is **sync, not backup**:

1. **Originals Only in iCloud** — With "Optimize Mac Storage" enabled, full-quality originals live only in iCloud; the Mac may hold placeholders.
2. **Deletions Sync** — Delete a photo on one device and it disappears on all devices (after the 30-day "Recently Deleted" window it is gone).
3. **No Independent Copy** — Time Machine skips offloaded (placeholder) files; there is no user-owned, full-quality, independent copy of the iCloud library.

**Solution:** An app that downloads every item from iCloud one at a time, copies it to a destination the user controls (external drive, NAS/network share, Google Drive, OneDrive, Amazon S3 or any S3-compatible bucket), and optionally mirrors deletions into a retention-managed `Deleted` folder.

---

## 2. Goals & Non-Goals

### Goals
- G1: Full-quality backup of the entire iCloud Photos library (photos, videos, edits, Live Photo movies, RAW sidecars, shared albums).
- G2: Backup of iCloud Drive (incl. Desktop & Documents sync, per-app data like Pages/Numbers) and arbitrary local folders.
- G3: Multiple destinations: mounted volumes (external/encrypted drives, NAS, WebDAV/SFTP/Dropbox mounts) + native cloud APIs (Google Drive, OneDrive, S3-compatible).
- G4: Multiple independent **Backup Plans** (sources, destination, schedule per plan).
- G5: Incremental engine: first run = full backup, subsequent runs copy only new/changed items.
- G6: Optional **Mirroring**: deletions moved to a `Deleted/` folder with retention policy (forever / 90 days (default) / 30 days / until next backup).
- G7: **Smart Offloading**: items fetched from iCloud are released/offloaded after copying so the Mac's disk never fills.
- G8: Automation: in-app scheduler (hourly/daily/weekly/monthly, run-at-login), Shortcuts actions (Start Backup, Stop Backup, Current Backup, Last Backup — plan-aware), Siri, shortcut triggers on backup events.
- G9: Menu bar status: start/stop a backup and watch live progress without opening the main window.
- G10: Read-only with respect to iCloud: never modify or delete anything in iCloud or the Photos library.

### Non-Goals
- NG1: No iOS/iPadOS version (future phase — see Parachute Mobile).
- NG2: No restoring/writing back to iCloud.
- NG3: No telemetry, no account system, no subscription (one-time purchase model).
- NG4: No album-structured export in v1 (output structure is `Year → Month → Day`; album mapping is a known user-requested gap — backlog).

---

## 3. Target User & Personas

| Persona | Pain | Success |
|---|---|---|
 **The Memory Keeper** (consumer) | 10+ years of photos only in iCloud, Optimize Storage on | "My full-quality library is on my own NAS" |
 **The Pro** (photographer) | RAW files + edits, needs local copies | RAW sidecars + edits backed up incrementally |
 **The Privacy-Minded** | Doesn't trust cloud-only copies | Encrypted destination, no telemetry |

---

## 4. User Workflow (Guided 3-Step Setup)

1. **Step 1 of 3 — "What to protect"**: allow Photos access (toggles: full timeline / photos / videos / edits; optional date range) OR pick source folders (iCloud Drive, Pages/Numbers app data, arbitrary folders — each with a toggle). Configure Mirroring here.
2. **Step 2 of 3 — "Where to keep your data"**: choose destination from list (connected drives incl. encrypted, NAS, Google Drive, OneDrive, Amazon S3).
3. **Step 3 of 3 — "Start your first backup"**: one button copies everything selected; live progress shown.

**Ongoing:** schedule runs automatically (or manual/Shortcuts/Siri). Live per-file progress. After each run, an "At a Glance" overview shows item counts, statistics and the setup summary.

---

## 5. Functional Requirements

### 5.1 Photos Backup (P0)
- FR-P1: Read the **System Photo Library** via PhotoKit; require it as source.
- FR-P2: Copy photos **and** videos at full original quality, including: edited versions (optionally originals alongside), Live Photo paired movies, RAW sidecars (RAW+JPEG pairs), burst picks, favorites metadata sidecar (v1.1), shared albums (opt-in).
- FR-P3: Per-item iCloud fetch on demand: download each asset from iCloud as the backup reaches it (requires only free space ≈ largest single asset, not the whole library).
- FR-P4: Output layout: `Destination/Photos/YYYY/MM/DD/filename.ext`.
- FR-P5: Incremental: asset identifier + modification state tracking; never re-copy unchanged assets.
- FR-P6: Photo options toggles: full timeline / photos only / videos only / include edits / date-range filter.

### 5.2 File/Folder Backup (P0)
- FR-F1: Sources: iCloud Drive root (incl. Desktop & Documents), per-app iCloud containers (Pages, Numbers), any user-picked folder.
- FR-F2: Copy folder hierarchy as-is.
- FR-F3: Smart offloading for iCloud Drive: after copying a dataless (placeholder) file, let the system evict it again.
- FR-F4: Per-source toggles persisted per plan.

### 5.3 Destinations (P0)
- FR-D1: Mounted volumes: external drives, encrypted (FileVault/APFS-encrypted) volumes, NAS/SMB shares, anything Finder mounts.
- FR-D2: Native cloud: Google Drive (API), OneDrive (API), Amazon S3 + any S3-compatible endpoint (custom endpoint URL).
- FR-D3: Destination health check before each run (reachable, writable, enough space estimate).

### 5.4 Backup Engine (P0)
- FR-E1: Plans: multiple named plans, each with sources + destination + schedule.
- FR-E2: Live progress: percent, current file, items copied, elapsed time, start time.
- FR-E3: **Backup History**: per-run log (start/end, counts, errors).
- FR-E4: **Missed Items**: files that failed (locked, unreachable) are recorded and retried next run.
- FR-E5: Error reporting with clear per-item reasons.
- FR-E6: Cancellable runs (Stop button).

### 5.5 Mirroring (P1)
- FR-M1: Optional per plan. When on, items deleted from the source since last run are **moved** to `Destination/Deleted/…` (structure preserved).
- FR-M2: Retention: keep forever / 90 days (default) / 30 days / delete at next backup.
- FR-M3: Default off → backup "only grows".

### 5.6 Scheduling & Automation (P0)
- FR-S1: Intervals: hourly, daily, weekly, monthly; time-of-day picker; "start at login" option.
- FR-S2: Shortcuts App Intents: `Start Backup` (plan parameter), `Stop Backup`, `Current Backup` (status), `Last Backup` (result); event triggers exposed to Shortcuts.
- FR-S3: Menu bar extra: icon state (idle/running), popover with progress + Stop, "Start plan…" menu.

### 5.7 Onboarding & Overview (P0)
- FR-O1: First-launch 3-step guided setup (see §4).
- FR-O2: "At a Glance" dashboard: protected item counts, last backup time/result, oldest backed-up memory, per-plan setup summary.
- FR-O3: Permissions onboarding: Photos permission prompt, Full Disk Access guidance for arbitrary folders.

### 5.8 Security & Privacy (P0)
- FR-SEC1: Zero telemetry. No account creation; uses the Apple Account already signed in on the Mac.
- FR-SEC2: Works with Advanced Data Protection enabled (app only reads what the system can decrypt locally).
- FR-SEC3: No secrets at rest beyond OS keychain; cloud credentials stored in Keychain.
- FR-SEC4: Read-only toward iCloud/Photos library.

---

## 6. Non-Functional Requirements

- NFR1: macOS 15+ (SwiftUI, App Sandbox, App Store distributable).
- NFR2: Memory-efficient streaming copy (never load whole asset into RAM).
- NFR3: Respect system load: low I/O priority for copy operations.
- NFR4: Localizable (EN first; DE/TR ready).
- NFR5: Crash-free incremental state (SQLite or similar, atomic writes).
- NFR6: App size < 20 MB.

---

## 7. Success Metrics

- First backup completion rate > 90% within 24h of install.
- Incremental run duration < 5 min for < 100 changed items.
- Zero data-loss incidents (destination never corrupts source).
- App Store rating ≥ 4.5.

---

## 8. Known Gaps from the Original (Backlog Signals)

User requests seen in the original's reviews — candidate differentiators:
- Album-preserving export structure (instead of Year/Month/Day)
- Folder excludes / filters
- HEIC→JPG conversion option
- Backup notifications (email/push)
- Auto-mount/auto-eject destination drives
- Multi-account (family) photo libraries
- Encrypted sparse-bundle NAS destinations
- Apple Notes / Music backup

---

## 9. Milestones

| M | Scope |
|---|---|
| M1 | Engine core: local folder → local folder incremental copy + history + live progress |
| M2 | Photos source (PhotoKit, on-demand fetch, edits/Live Photo/RAW), Year/Month/Day layout |
| M3 | iCloud Drive sources + smart offloading |
| M4 | Destinations: S3-compatible + OneDrive + Google Drive |
| M5 | Plans, scheduler, menu bar, Shortcuts intents |
| M6 | Mirroring + retention, Missed Items, polish, guided setup flow |
