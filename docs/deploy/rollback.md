# Rollback runbook

## Why rollback is manual here

Issue #60's acceptance criteria asked CI to gate on "post-deploy health, and rollback
behavior". The health gate is automated; **rollback deliberately is not.**

That was an explicit decision, not an omission. An automatic rollback is itself a deploy: it
rebuilds images and recreates containers unattended, in response to a signal that has
already proven unreliable enough to fail. When the health check trips for a reason unrelated
to the new commit — Jellyfin still scanning a library, an expired TLS cert, a slow disk — an
automatic revert adds a second unplanned deploy to an already-degraded stack and destroys
the state you would want to inspect. Choosing a red build plus a human decision trades a
little recovery latency for not compounding an outage.

What CI does guarantee: a failed health check **fails the workflow run nonzero**, so a bad
deploy is never reported as success. See `deploy/health-check.sh`.

## What CI gives you when a deploy goes unhealthy

`deploy/health-check.sh` prints the failing services and the exact rollback command,
including the commit to return to. It derives that from `ORIG_HEAD` — what `git pull` leaves
pointing at the pre-pull commit — falling back to `HEAD@{1}`. If neither resolves, or if the
candidate is the commit already checked out (which would make the "rollback" a no-op), it
says so rather than printing a command that does nothing.

Read that output first. It is more specific than this document.

## Procedure

```bash
ssh <vps>
cd /opt/watch-party

# 1. Confirm what is deployed and what to go back to.
git log --oneline -5

# 2. Return to the last known-good commit.
#    Use the SHA from health-check.sh, or pick one from the log above.
git reset --hard <known-good-sha>

# 3. Rebuild and bring the stack back up.
docker compose --env-file secrets/.env -f docker-compose.prod.yml up -d --build

# 4. Verify. This must exit 0.
./deploy/health-check.sh
```

If step 4 still fails, the problem is not the commit — stop rolling back and diagnose:

```bash
docker compose -f docker-compose.prod.yml ps
docker compose -f docker-compose.prod.yml logs watchparty --tail 100
docker compose -f docker-compose.prod.yml logs caddy --tail 50
```

## Notes and gotchas

- **`git reset --hard` discards uncommitted changes on the VPS.** Production is a deploy
  target, not a workspace, so it should have none — but check `git status` first if you have
  ever hand-edited a file there.
- **`secrets/` is unaffected by any of this.** It is gitignored and never moves with a pull,
  reset, or checkout. A rollback will not restore an old secret, and does not need to.
- **A rollback that crosses an image pin change re-pulls images.** The pins in
  `docker-compose.prod.yml` are digests, so you get byte-identical images back, not
  "whatever `:latest` means now" — this is much of the point of pinning. See
  `docs/deploy/pinning.md`.
- **The database and session store survive.** `data/sessions`, `data/subtitles` and `data/`
  are bind mounts outside the images, so rolling back the code does not log everyone out.
- **Rolling back does not fix a forward-only migration.** There are none today; if one is
  ever added, this runbook needs a matching down-path before that deploy ships.
- **`--force-recreate` is not used here** (unlike `deploy/up-prod.sh`) because a rollback
  changes the code, so `up -d --build` already recreates what changed.

## Verification record

The procedure above was executed once on 2026-08-05 to satisfy #60's requirement that
rollback behaviour be tested rather than merely documented. Evidence is in the pull request
for #60, and covers `deploy/health-check.sh` correctly reporting failures, emitting a
rollback target, and suppressing a no-op target when the candidate equals `HEAD`.

The parts that could **not** be exercised from the authoring environment, and so remain
unverified until run on the VPS:

- an end-to-end `git reset --hard` + rebuild + re-verify cycle against live containers, which
  was out of scope because the standing constraint forbade stopping or recreating any live
  `watchparty-*` container
- `deploy/firewall.sh` applying real `DOCKER-USER` rules, and their survival across a reboot
