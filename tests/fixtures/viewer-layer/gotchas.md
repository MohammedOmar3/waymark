---
title: Gotchas Log
status: current
---

# Gotchas Log

## G-0001 — Expo build fails with missing plist
- **Status:** open
- **Repo:** all
- **Symptom:** build stops with `GoogleService-Info.plist not found`
- **Fix:** see D-0001 and the [decisions](decisions.md) file.

## G-0002 — Hook hangs on heredoc
- **Status:** fixed
- **Fix:** use printf instead of a heredoc.
