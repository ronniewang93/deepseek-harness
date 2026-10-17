---
name: update-dsh-master
description: Use when the user asks to update this checkout's master branch and restart the dsh web service that serves it behind its Tailscale path, or asks for that service's current Tailscale URL after such a restart.
user-invocable: true
---

# Update master and restart dsh web

One bundled script owns this workflow end to end. Run it and report what it prints; do not re-derive the steps by hand.

```sh
.agents/skills/update-dsh-master/scripts/update-dsh-master.sh
```

The command above is relative to the repository root and defaults to port `3180`, Tailscale mount `/dsh`, and the machine's own Tailscale DNS name detected from `tailscale status --json`.

## What it does

Seven logged steps: preconditions, target resolution, checkout update, service stop, service start, readiness wait, verification. It fetches `origin/master` and fast-forwards only (`--ff-only`), so a diverged or dirty checkout fails loudly instead of merging. The restart reuses the same `--trusted-host` and `--public-url` the service needs to answer through the Tailscale path, and it prints `URL <launch url>` on success.

## Report to the user

Quote the `URL <launch url>` line verbatim. It carries the process credential that admits the browser session, so it is the deliverable of this skill. Include whether the checkout actually advanced and which commit it now sits on.

If that line reports the URL as unavailable, the service is running but its launch URL could not be read from the log. Report the service log path the script named instead of assembling a URL from the mount root: a token-less URL always answers 401.

## Options

| Flag | Effect |
|---|---|
| `--port <port>` | port `dsh web` listens on (default 3180) |
| `--mount <path>` | Tailscale serve path prefix (default `/dsh`) |
| `--host <name>` | Tailscale DNS name; auto-detected when omitted |
| `--no-pull` | restart the service without updating the checkout |
| `--dry-run` | report every planned action without changing anything |
| `--restart` | clear the state file and start over |
| `--yes` | skip the confirmation prompt |

Always use `--yes` here: the script prompts only on a TTY, and a non-interactive caller should not rely on that.

## Diagnose failures

The script exits `2` for bad arguments or missing preconditions, `3` when the checkout cannot be updated on master, and `4` when the service never becomes ready. Every run logs to `~/.dsh/update-dsh-master/logs/`, and the newest run's state sits in `~/.dsh/update-dsh-master/state/update-dsh-master.state.json`.

- Exit `3`: `git fetch` already retried three times with backoff, so a fetch failure here is sustained rather than a transient transport drop; report it from the log. A `git pull` failure is a dirty tree or a diverged master and needs the user's decision, not an automatic merge.
- Exit `4`: read the service log path the script printed. A port still held means the old process ignored `SIGTERM`; a startup crash is usually a plugin that failed to resolve.
- A `WARN no 'tailscale serve' mapping` line means the mapping is absent, not broken. Report the exact `tailscale serve` command the script suggests rather than running it.

Do not restart anything yourself beyond this script, and do not start a second server on another port: the point of the command is that one known URL keeps working.
