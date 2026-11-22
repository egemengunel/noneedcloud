# NoNeedCloud

Automatic, set-and-forget backups of iCloud Photos and iCloud Drive to storage you own: external drives, NAS / network shares, or a cloud provider of your choice.

iCloud syncs, it does not back up. A deletion or corruption on one device propagates everywhere, and with "Optimize Storage" on, iCloud may hold the only full-resolution original. NoNeedCloud keeps an independent copy of your originals as plain files and folders that you can browse and restore with Finder.

> Status: **research / product definition**. No application code yet. The product requirements document (PRD) is written first; implementation starts only after it is reviewed.

## Monorepo layout

```
noneedcloud/
├── apps/
│   └── macos/          # Native macOS client (Swift / SwiftUI)
├── backend/            # Server-side services
├── docs/
│   ├── PRD.md          # Product requirements (client first)   [planned]
│   └── research/       # Competitive / reverse-engineering notes (local only, not committed)
└── README.md           # This file: global overview for the whole monorepo
```

| Part | Path | Purpose | Status |
| --- | --- | --- | --- |
| macOS client | `apps/macos` | Backs up Photos, iCloud Drive and custom folders on-device; scheduling, menu bar, Shortcuts | PRD in progress |
| Backend | `backend` | Server-side services supporting the clients (scope to be defined in PRD) | Not started |

## Product pillars (client)

- **Sources**: System Photo Library (originals, edits, Live Photo movies, RAW sidecars, Shared Albums), iCloud Drive (incl. Desktop & Documents, per-app data folders), any custom folder.
- **Destinations**: any Finder-mounted volume (external drive, NAS, SMB/SFTP/WebDAV), plus built-in Google Drive, OneDrive and S3-compatible storage.
- **Backup semantics**: incremental by default; optional mirroring that moves deleted items into a `Deleted` folder with configurable retention. Never writes to or deletes from iCloud.
- **Space-aware**: fetches one item at a time from iCloud and releases it again after copying, so the Mac's disk never fills up.
- **Automation**: multiple backup plans, each with its own sources, destination and schedule (hourly / daily / weekly / monthly), start at login, Shortcuts & Siri actions, Shortcuts triggered on backup events.
- **Visibility**: guided 3-step setup, live per-file progress, menu bar status, backup history, missed-item reporting.
- **Privacy**: everything runs on-device; no accounts required for local destinations, no telemetry.

## Principles

1. Read-only towards iCloud. Ever.
2. Backups are plain files and folders: no proprietary format, no restore tool required.
3. One-time-purchase mindset: no lock-in.
4. Native platform APIs first (PhotoKit, FileProvider / NSFileCoordinator, App Intents, SwiftUI).

## Getting started

Nothing to build yet. See `docs/PRD.md` once it lands.
