---
title: Docs Protocol
status: current
---

# Docs Protocol

Read this only when writing a doc under `docs/`.

## Creating a new doc

Before writing, check `docs/INDEX.md` for an existing doc on the same subject. Extend or explicitly supersede it; do not create a near-duplicate.

Location: `docs/<repo>/` for a single repo, `docs/cross-repo/` otherwise.

Filename: `YYYY-MM-DD-<kind>-<slug>.md`, lowercase, hyphenated, no spaces. `<kind>` is one of: `design`, `impl`, `analysis`, `research`, `investigation`, `review`.

Required frontmatter. Refuse to create the doc without all of `title`, `repo`, `kind`, `created`, `status` and `summary` filled in (`repo` is a repo name or `cross-repo`; `supersedes`, `related` and `valid_until` are optional, except that `valid_until` is required for `analysis` and `research`):

```yaml
---
title:
repo:
kind:
created:      # YYYY-MM-DD
status:       # draft | current | superseded | done | abandoned
summary:      # one line, shown in docs/INDEX.md
valid_until:  # YYYY-MM-DD; required for analysis and research kinds
supersedes:   # relative path, or omit
related:      # decision or convention ID, repo file, or omit
---
```

When a doc drives a decision, record a short decision linking to the doc. The decision holds the distillate; the doc holds the reasoning. Never inline a design doc into the decisions log.

## Superseding a doc

- Set the old doc's `status: superseded` and move it to `docs/archive/`.
- Set `supersedes:` on the new doc to the old doc's (former) relative path.
- Never delete or overwrite a superseded doc.
