---
name: update-dsh-master
description: Use when the user asks to update this checkout from official master, push the merged result to their fork, and restart the dsh web service behind its Tailscale path, or asks for that service's current Tailscale URL.
user-invocable: true
---

# Merge official master, push to the fork, restart dsh web

One bundled script owns this workflow end to end. Run it and report what it prints; do not re-derive the steps by hand.

```sh
.agents/skills/update-dsh-master/scripts/update-dsh-master.sh
```

The command above is relative to the repository root and defaults to port `3180`, Tailscale mount `/dsh`, and the machine's own Tailscale DNS name detected from `tailscale status --json`.

## What it does

Eight logged steps: preconditions, target resolution, fetch, merge, push, service stop, service start, readiness wait, verification. It fetches `origin/master` and merges it into the local `master` — a merge rather than a fast-forward, because this checkout carries its own commits on top of upstream. A conflicting merge is aborted and reported rather than left half-finished.

The merged master then goes to `fork/local/dsh-tooling`, deliberately not to the fork's own `master`, so that branch stays identical to upstream and remains a clean base for pull requests. Uncommitted files never block a run: git refuses a merge that would overwrite them, and only committed work reaches the fork.

The restart reuses the same `--trusted-host` and `--public-url` the service needs to answer through the Tailscale path, and it prints `URL <launch url>` on success.

## Report to the user

Quote the `URL <launch url>` line verbatim. It carries the process credential that admits the browser session, so it is the deliverable of this skill. Include whether the checkout actually advanced and which commit it now sits on.

If that line reports the URL as unavailable, the service is running but its launch URL could not be read from the log. Report the service log path the script named instead of assembling a URL from the mount root: a token-less URL always answers 401.

## Answering "what is the URL?"

When the user only wants the link, run `--url` and never the full update:

```sh
.agents/skills/update-dsh-master/scripts/update-dsh-master.sh --url
```

A restart mints a new launch token, so a full update invalidates the URL a phone or another browser already holds, and a device that has not yet exchanged its token cannot recover from that on its own. `--url` reads the listening service's own log through its file descriptors and changes nothing. The signed session cookie derives from a persistent key, so a device that has exchanged a token once keeps working across restarts for the cookie's 30-day lifetime.

## Options

| Flag | Effect |
|---|---|
| `--url` | print the listening service's launch URL; restarts nothing |
| `--push-remote <r>` | git remote that receives the merged master (default `fork`) |
| `--push-branch <b>` | branch on that remote (default `local/dsh-tooling`) |
| `--no-push` | merge without pushing to the fork |
| `--port <port>` | port `dsh web` listens on (default 3180) |
| `--mount <path>` | Tailscale serve path prefix (default `/dsh`) |
| `--host <name>` | Tailscale DNS name; auto-detected when omitted |
| `--no-pull` | restart the service without merging origin/master |
| `--dry-run` | report every planned action without changing anything |
| `--restart` | clear the state file and start over |
| `--yes` | skip the confirmation prompt |

Always use `--yes` here: the script prompts only on a TTY, and a non-interactive caller should not rely on that.

## Diagnose failures

The script exits `2` for bad arguments or missing preconditions, `3` when the checkout cannot be merged with origin/master, `4` when the service never becomes ready, and `5` when the merged checkout cannot be pushed to the fork. Every run logs to `~/.dsh/update-dsh-master/logs/`, and the newest run's state sits in `~/.dsh/update-dsh-master/state/update-dsh-master.state.json`.

- Exit `3`: `git fetch` already retried three times with backoff, so a fetch failure here is sustained rather than a transient transport drop; report it from the log. A merge conflict aborts the merge and needs the user's decision, not an automatic resolution. A refusal naming overwritten files means uncommitted work collides with the incoming changes; the user commits or stashes it, and the script never discards it.
- Exit `4`: read the service log path the script printed. A port still held means the old process ignored `SIGTERM`; a startup crash is usually a plugin that failed to resolve.
- Exit `5`: the merge landed but the push did not, so the service still runs the previous checkout. Check that the fork remote resolves and that SSH to GitHub works — the fork authenticates over SSH, not HTTPS, and the push runs with prompts disabled so a missing credential fails fast instead of hanging.
- A `WARN no 'tailscale serve' mapping` line means the mapping is absent, not broken. Report the exact `tailscale serve` command the script suggests rather than running it.

Do not restart anything yourself beyond this script, and do not start a second server on another port: the point of the command is that one known URL keeps working.
