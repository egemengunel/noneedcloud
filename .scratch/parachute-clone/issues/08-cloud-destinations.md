# 08: Cloud destinations — S3-compatible, OneDrive, Google Drive

**What to build:** Native cloud destinations beyond mounted volumes: Amazon S3 or any S3-compatible bucket (custom endpoint URL), OneDrive, and Google Drive, via their APIs (no Finder mount needed). Credentials stored in Keychain. Destination health check before each run (reachable, writable). Same incremental engine and history apply.

**Blocked by:** 02 (Copy engine core).

**Status:** ready-for-agent

- [ ] Backup to S3-compatible bucket (custom endpoint) succeeds incrementally
- [ ] OneDrive and Google Drive destinations back up via API with Keychain-stored tokens
- [ ] Unreachable destination fails fast with a clear reason in History
