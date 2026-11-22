# 09: Mirroring + retention (Deleted folder)

**What to build:** Optional per-plan Mirroring: items deleted from the source since the last run are moved to `Destination/Deleted/…` (structure preserved) instead of being removed. Retention for kept items: forever / 90 days (default) / 30 days / until next backup. Off by default (backup only grows).

**Blocked by:** 02 (Copy engine core).

**Status:** ready-for-agent

- [ ] Deleting a source item moves its copy to `Deleted/` on next run (when enabled)
- [ ] Retention settings (forever/90d/30d/next backup) purge correctly
- [ ] Default off: destination only grows
