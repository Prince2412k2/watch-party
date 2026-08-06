# LiveKit credential exposure — findings and decisions

Raised by issue [#60](https://github.com/Prince2412k2/watch-party/issues/60), whose
acceptance criteria included "LiveKit credentials are rotated and historical exposure is
handled". Investigating that turned up **two separate events** with very different
severities. They are recorded separately on purpose — conflating them makes the harmless
one look alarming and the real one look handled.

Neither event involves a secret that is currently tracked in git.

---

## Event A — historical placeholder in git history (not a live secret)

| | |
| --- | --- |
| **What** | `livekit.yaml` containing `devkey: devsecret0000000000000000000000000` |
| **Where** | Tracked from `1822273` ("Phase 0: scaffold repo structure and config files") until `a8a09bf` deleted it |
| **Also present** | `node_ip: 100.64.0.10` — a Tailscale CGNAT address, not publicly routable |
| **Severity** | Negligible |
| **Action** | None. Documented only. |

`devkey` / `devsecret0000…` is LiveKit's **published development default**, printed in
LiveKit's own getting-started docs. It is not a bespoke credential and was never
production's. Verified: `secrets/livekit.yaml` uses a different key id and a different
secret, so nothing that was ever committed grants access to the deployment.

### Why history was not rewritten

Purging `livekit.yaml` from history with `git filter-repo` was considered and **declined**.
The value is a publicly documented placeholder, so the benefit is approximately zero, while
the cost is a rewrite of every commit SHA in the repository — invalidating six in-flight
audit worktrees, the Wave 1 integration branch, this branch, and every existing clone and
open PR. That trade is not worth making for a string anyone can read in LiveKit's
documentation.

Consequently `devsecret0000…` remains reachable via `git log`. That is a deliberate,
recorded decision, not an oversight.

---

## Event B — live credential printed into an assistant transcript

| | |
| --- | --- |
| **What** | The current production LiveKit API key id and secret |
| **When** | 2026-08-05, while authoring this issue's spec |
| **How** | A diagnostic command read `secrets/livekit.yaml` to confirm LiveKit's UDP port configuration. It attempted to redact by filtering lines matching `secret\|key`, but the credential line is a bare `<keyid>: <value>` YAML pair containing neither word, so the filter passed it through and the value was printed into the session transcript. |
| **Blast radius** | The session transcript only. The credential lives in four **gitignored** files — `secrets/livekit.yaml`, `secrets/.env`, `secrets/livekit.dev.yaml`, `.env` — and no tracked file was affected. |
| **Severity** | Real. The credential left its intended storage. |
| **Action** | **Accepted without rotation, by explicit repository-owner decision.** |

### Decision and its consequence

The exposure and three options (document only / rotate the pair / rotate plus a full history
rewrite) were put to the repository owner on 2026-08-05. The owner chose to document without
rotating.

**The credential therefore remains valid.** This is recorded so a later reader can tell an
accepted risk from a missed one. Anyone who disagrees with the call can revisit it; rotating
means generating a new key id and secret, updating all four files above consistently, and
recreating `watchparty-livekit` and `watchparty-app` so both sides load the new pair. The
two sides must match — a mismatch does not fail loudly, it silently breaks every LiveKit
token mint, so cameras stop working while the app otherwise looks healthy.

### The lesson that was actionable

Redacting by keyword match on the *name* of a value is unsound, because a credential line
need not contain the words "key" or "secret". Diagnostics that read secret-bearing files
must select by **line position or an explicit key allowlist** instead. Applied throughout
the rest of this issue's work.

---

## What actually reduces risk here

Since neither event called for rotation, the durable improvement is preventing a *new*
secret from ever being committed. Issue #60 adds a `secret-scan` gate to
`.github/workflows/main.yml` (gitleaks, pinned by commit SHA) that runs on every push to
`main` and `dev` and on every pull request, and which `deploy` depends on. It scans the
pushed commit range and PR diffs rather than full history — deliberately, so the Event A
placeholder above does not make the gate permanently red and thereby useless.

Supporting cleanups in the same change:

- `.gitignore` no longer carries a stale instruction to run `git rm --cached livekit.yaml`;
  `a8a09bf` already untracked it years of commits ago.
- `coturn.conf` (placeholders only, but tracked while `*.conf` was gitignored — a
  contradiction between tracked state and ignore policy) is now `coturn.conf.example`,
  matching the existing `livekit.yaml.example` convention.
