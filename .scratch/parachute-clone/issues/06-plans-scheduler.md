# 06: Backup Plans + scheduler

**What to build:** Multiple named Backup Plans, each with its own sources, destination and schedule. Scheduler: hourly, daily, weekly, monthly with time-of-day picker, plus "start at login". Plans run independently; each keeps its own history and incremental state. Missed scheduled runs (Mac asleep) start at next wake.

**Blocked by:** 02 (Copy engine core), 04 (Photos source), 05 (iCloud Drive sources).

**Status:** ready-for-agent

- [ ] Create/edit/delete multiple plans with per-plan settings
- [ ] Hourly/daily/weekly/monthly schedules fire automatically
- [ ] Start-at-login option works; missed run resumes after wake
