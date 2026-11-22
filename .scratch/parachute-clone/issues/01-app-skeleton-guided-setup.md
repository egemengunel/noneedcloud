# 01: App skeleton + 3-step guided setup

**What to build:** A native macOS 15+ SwiftUI app (sandboxed) that on first launch walks the user through the guided setup: Step 1 "What to protect" (choose source folders; Photos toggles placeholder), Step 2 "Where to keep your data" (pick a folder destination on a mounted volume), Step 3 "Start your first backup" (button present but wired to the engine in ticket 02). After setup, show the "At a Glance" overview: per-plan summary, item counts (zero state), last backup status. No real copying happens in this ticket.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] App builds and runs on macOS 15+
- [ ] 3-step setup wizard completes and persists selections
- [ ] At a Glance dashboard renders plan summary + zero state
- [ ] Re-launch skips setup and shows the dashboard
