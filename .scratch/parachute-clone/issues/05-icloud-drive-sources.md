# 05: iCloud Drive sources + Smart Offloading

**What to build:** Folder sources beyond arbitrary folders: iCloud Drive root (including Desktop & Documents sync), and per-app iCloud containers (Pages, Numbers). Dataless (placeholder) files are fetched from iCloud before copying and released/evicted again right after, so device storage never fills. Each source has a toggle in the plan.

**Blocked by:** 02 (Copy engine core).

**Status:** ready-for-agent

- [ ] iCloud Drive incl. Desktop & Documents backs up with hierarchy preserved
- [ ] A placeholder file is fetched, copied, then evicted again (storage unchanged)
- [ ] Pages/Numbers containers selectable and backed up
- [ ] Sources independently toggleable per plan
