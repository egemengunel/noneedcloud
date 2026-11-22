# 04: Photos source — PhotoKit with on-demand iCloud fetch

**What to build:** Back up the System Photo Library at full original quality. Each asset is fetched from iCloud on demand as the backup reaches it (works with Optimize Storage on; needs free space ≈ largest asset only). Output layout `Destination/Photos/YYYY/MM/DD/`. Includes: photos, videos, edited versions (with original optional), Live Photo paired movies, RAW sidecars, and opt-in Shared Albums. Options: full timeline / photos only / videos only / include edits / date-range filter. Strictly read-only toward the library. Incremental via asset identifiers + modification state.

**Blocked by:** 02 (Copy engine core).

**Status:** ready-for-agent

- [ ] Test library backs up fully at original quality in YYYY/MM/DD layout
- [ ] Asset with edit + Live Photo + RAW exports all components correctly
- [ ] On-demand fetch works with Optimize Storage on; no full-library download
- [ ] New/edited assets after first run are picked up incrementally
- [ ] Library is never modified or deleted from
