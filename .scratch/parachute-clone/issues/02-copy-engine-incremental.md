# 02: Copy engine core — folder→folder incremental with live progress

**What to build:** The heart of the app: an incremental backup engine that streams files from a chosen source folder to a folder destination on a mounted volume. First run copies everything; later runs copy only new/changed items (persistent run state). Live progress UI: percent, current file, items copied, elapsed time, start time — plus a working Stop button. Copies are streamed (never load a whole file in RAM) and run at low I/O priority. The engine never writes to the source.

**Blocked by:** 01 (App skeleton + guided setup).

**Status:** ready-for-agent

- [ ] Full first backup of a test folder tree, hierarchy preserved
- [ ] Second run after small changes copies only changed/new files
- [ ] Live progress (percent, current file, count, times) visible; Stop cancels safely
- [ ] Run state survives app restart; unchanged items never re-copied
