# 03: Backup History + Missed Items

**What to build:** After every run the app records a history entry (start/end time, items copied, errors) and a "Missed Items" list: every file that could not be copied with a clear per-item reason (locked, permission, vanished mid-copy). Missed items are retried automatically on the next run. The dashboard shows last-run result; a History view lists runs.

**Blocked by:** 02 (Copy engine core).

**Status:** ready-for-agent

- [ ] Each run produces a history entry viewable in the app
- [ ] Locked/unreadable files appear in Missed Items with reasons
- [ ] Missed items are retried and cleared on the next successful run
