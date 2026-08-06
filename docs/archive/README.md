# Archive — historical documents, superseded

Nothing in this directory describes the system as it is today. Each file is
kept because it explains *why* something was built, or because a later document
cites it — not because it is a guide anybody should follow.

Every file here carries a header saying what superseded it. If you find one
that does not, that is a bug: add the header or delete the file.

| File | Was | Superseded by |
|---|---|---|
| `HANDOFF.md` | The original build brief | Actively wrong in three ways — see its header |
| `ANALYSIS.md` | The read-only audit that produced issues #54–#64 | The issues themselves, and the fixes on `dev` |
| `redesign-PLAN.md` | Execution plan for the cinematic-minimal redesign | `docs/watchparty-design/README.md`, and the shipped UI |
| `README-servarr.md` | Bring-up guide for a standalone servarr compose stack | `docker-compose.yml`, which now owns those services |

Current documentation lives one level up in `docs/`.
