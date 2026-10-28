---
title: Waymark design notes
kind: spec
status: current
created: 2026-01-05
valid_until: 2026-02-01
summary: Notes with a mermaid diagram
---

# Waymark design notes

This page contains a mermaid diagram of the capture flow.

```mermaid
graph TD
  A[Session] --> B[Capture]
  B --> C[Layer]
```

See the [decisions](../../decisions.md) file and gotcha G-0001.
