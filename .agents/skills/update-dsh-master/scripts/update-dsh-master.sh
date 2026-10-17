#!/usr/bin/env bash
#
# update-dsh-master.sh — merge the newest official master into this checkout,
# push the merged result to a personal fork, and restart the `dsh web` service
# that serves it. `--help` prints the options, exit codes, and log locations.
#
# LOG     ${DSH_HOME:-$HOME/.dsh}/update-dsh-master/logs/<name>-<YYYYMMDD-HHMMSS>.log
# STATE   ${DSH_HOME:-$HOME/.dsh}/update-dsh-master/state/update-dsh-master.state.json
#
# Uncommitted changes do not block a run: git refuses a merge that would
# overwrite them, and only committed work reaches the fork.
#
# The Tailscale serve mapping is durable configuration and is never rewritten
# here; a missing or misrouted mapping is reported, not repaired.

set -Eeuo pipefail

SCRIPT_NAME="update-dsh-master"
DSH_HOME_DIR="${DSH_HOME:-$HOME/.dsh}"
RUN_DIR="$DSH_HOME_DIR/$SCRIPT_NAME"
LOG_DIR="$RUN_DIR/logs"
STATE_DIR="$RUN_DIR/state"
STATE_FILE="$STATE_DIR/$SCRIPT_NAME.state.json"

PORT=3180
MOUNT="/dsh"
TS_HOST=""
PUBLIC_URL=""
REPO_ROOT=""
SERVICE_LOG=""
SERVICE_PID=""
URL=""
DO_PULL=true
DO_PUSH=true
PUSH_REMOTE="fork"
PUSH_BRANCH="local/dsh-tooling"
DETACH=false
SHOW_URL=false
DRY_RUN=false
ASSUME_YES=false
RESTART=false

LOG_FILE=""
STEP=0
TOTAL_STEPS=8
OK_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

on_err() { printf '[%s] [ERR] %s failed at line %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$PROG" "$1" >&2; }
trap 'on_err "$LINENO"' ERR

# ---------------------------------------------------------------------------
# logging
# ---------------------------------------------------------------------------

# ISO8601 UTC timestamp for every log line.
now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Emit one structured line to stdout and, once the log file exists, to it too.
say() {
  local line="[$(now_iso)] $*"
  printf '%s\n' "$line"
  if [[ -n "$LOG_FILE" ]]; then
    printf '%s\n' "$line" >> "$LOG_FILE"
  fi
  return 0
}

# Announce the start of a numbered step.
step_begin() {
  STEP=$((STEP + 1))
  say "STEP [$STEP/$TOTAL_STEPS] BEGIN $1"
}

# Announce the end of the current step with its outcome.
step_end() { say "STEP [$STEP/$TOTAL_STEPS] END ok=$1"; }

# Announce a step that is skipped on purpose.
step_skip() {
  SKIP_COUNT=$((SKIP_COUNT + 1))
  STEP=$((STEP + 1))
  say "STEP [$STEP/$TOTAL_STEPS] SKIP $1"
}

# Record a fatal failure with its context and stop.
die() {
  local code="$1"; shift
  FAIL_COUNT=$((FAIL_COUNT + 1))
  say "FATAL $*"
  write_state failed "$*" || true
  say "SUMMARY: ok=$OK_COUNT fail=$FAIL_COUNT skipped=$SKIP_COUNT"
  exit "$code"
}

# ---------------------------------------------------------------------------
# state
# ---------------------------------------------------------------------------

# Escape a value for embedding in the state file's JSON strings.
json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\n\r\t'
}

# Write the state file atomically (tmp + rename) so an interrupted run never
# leaves a half-written file behind.
write_state() {
  local status="$1" detail="${2:-}" pid="${3:-}" url="${4:-}"
  if [[ "$DRY_RUN" == true ]]; then
    return 0
  fi
  mkdir -p "$STATE_DIR"
  local tmp="$STATE_FILE.tmp.$$"
  cat > "$tmp" <<JSON
{
  "status": "$status",
  "detail": "$(json_escape "$detail")",
  "updatedAt": "$(now_iso)",
  "port": $PORT,
  "mount": "$(json_escape "$MOUNT")",
  "servicePid": "$(json_escape "$pid")",
  "url": "$(json_escape "$url")",
  "logFile": "$(json_escape "$LOG_FILE")"
}
JSON
  mv -f "$tmp" "$STATE_FILE"
}

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

# Print the complete option reference, step list, and exit codes.
usage() {
  cat <<'USAGE_TEXT'
update-dsh-master.sh — merge the newest official master into this checkout,
push the merged result to a personal fork, and restart the `dsh web` service
that serves it.

USAGE
  update-dsh-master.sh [options]

OPTIONS
  --port <port>        port `dsh web` listens on (default 3180)
  --mount <path>       Tailscale serve path prefix (default /dsh)
  --host <name>        Tailscale DNS name; auto-detected from `tailscale status` when omitted
  --push-remote <r>    git remote that receives the merged master (default fork)
  --push-branch <b>    branch on that remote (default local/dsh-tooling)
  --no-push            merge without pushing to the fork
  --url                print the listening service's launch URL, restarting nothing
  --no-pull            restart the service without merging
  --detach             re-exec detached, print one line, and return at once
  --dry-run            report every planned action without changing anything
  --restart            clear the state file and start over
  --yes, -y            skip the confirmation prompt
  -h, --help           show this help

EXIT CODES
  0  merged, pushed, and serving through the Tailscale path
  2  invalid arguments or a missing precondition
  3  the checkout could not be merged with origin/master
  4  the service did not become ready at the requested port
  5  the merged checkout could not be pushed to the fork
USAGE_TEXT
}

# Resolve the repository root from the script's own location.
repo_root() {
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  (cd "$here/../../../.." && git rev-parse --show-toplevel)
}

# Read the Tailscale DNS name of this machine; empty when unavailable.
detect_ts_host() {
  if ! command -v tailscale >/dev/null 2>&1; then
    return 0
  fi
  tailscale status --json 2>/dev/null | node -e '
    let raw = ""
    process.stdin.on("data", chunk => { raw += chunk })
    process.stdin.on("end", () => {
      try {
        const dns = JSON.parse(raw)?.Self?.DNSName
        if (typeof dns === "string" && dns.length > 0) console.log(dns.replace(/\.$/, ""))
      } catch { /* an unparseable status is reported as an absent host */ }
    })
  ' 2>/dev/null | head -1 || true
}

# List the PIDs currently listening on the port.
listening_pids() { lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null || true; }

# Wait until the port has no listener left; fail after 30 seconds.
wait_port_free() {
  local waited=0
  while [[ -n "$(listening_pids)" ]]; do
    if [[ $waited -ge 30 ]]; then
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
    say "  waiting for port $PORT to free (${waited}s)"
  done
  return 0
}

# Wait until the service answers HTTP; print the response code.
wait_ready() {
  local waited=0 code=""
  while [[ $waited -lt 90 ]]; do
    code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 3 "http://127.0.0.1:$PORT/" 2>/dev/null || true)"
    case "$code" in
      200|303|401) printf '%s' "$code"; return 0 ;;
    esac
    sleep 2
    waited=$((waited + 2))
    if [[ $((waited % 10)) -eq 0 ]]; then
      say "  waiting for service readiness (${waited}s)"
    fi
  done
  return 1
}

# Extract the launch URL `dsh web` prints, including its process credential.
launch_url() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  grep -oE 'dsh web: https?://[^[:space:]]+' "$file" 2>/dev/null | tail -1 | sed 's/^dsh web: //' || true
}

# Fetch with bounded retries: a transient transport failure — an HTTP/2 framing
# error, a dropped connection — must not fail the whole run, while a pull stays
# single-attempt because its failures are conflicts the retry cannot resolve.
fetch_with_retry() {
  local attempt=1
  while [[ $attempt -le 3 ]]; do
    if git fetch --all --prune >> "$LOG_FILE" 2>&1; then
      return 0
    fi
    if [[ $attempt -lt 3 ]]; then
      say "  git fetch failed (attempt $attempt/3); retrying"
      sleep "$attempt"
    fi
    attempt=$((attempt + 1))
  done
  return 1
}

# Print the launch URL of the service already listening, restarting nothing.
# A restart mints a new token and invalidates the URL another device holds, so
# answering "what is the URL" must never restart the service.
show_current_url() {
  local pids pid log url
  pids="$(listening_pids)"
  if [[ -z "$pids" ]]; then
    say "no service is listening on port $PORT"
    return 4
  fi
  for pid in $pids; do
    say "  listener pid=$pid"
    # Read the log through the process's own stdout/stderr descriptors instead
    # of guessing a filename, so this also resolves a service another tool
    # started and this script never saw.
    log="$(lsof -p "$pid" -a -d 1,2 -Fn 2>/dev/null \
      | sed -n 's|^n\(/.*\)$|\1|p' | grep -v '^/dev/' | head -1)"
    if [[ -z "$log" ]]; then
      say "  pid $pid writes no regular file this script can read"
      continue
    fi
    say "  service log=$log"
    url="$(launch_url "$log")"
    if [[ -n "$url" ]]; then
      say "URL $url"
      return 0
    fi
    say "  no 'dsh web:' line in that log"
  done
  if [[ -f "$STATE_FILE" ]]; then
    url="$(sed -n 's/.*"url": "\(.*\)".*/\1/p' "$STATE_FILE" | head -1)"
    if [[ -n "$url" ]]; then
      say "  falling back to the last recorded state; confirm it still answers"
      say "URL $url"
      return 0
    fi
  fi
  say "no launch URL found; read the 'dsh web:' line from the service log"
  return 4
}

# ---------------------------------------------------------------------------
# steps
# ---------------------------------------------------------------------------

# Confirm the tooling this script depends on is present.
check_preconditions() {
  step_begin "preconditions"
  local binary
  for binary in git lsof curl node; do
    if ! command -v "$binary" >/dev/null 2>&1; then
      die 2 "required command not found: $binary"
    fi
  done
  REPO_ROOT="$(repo_root)" || true
  if [[ -z "$REPO_ROOT" ]]; then
    die 2 "script is not inside a git checkout"
  fi
  say "  repo=$REPO_ROOT"
  say "  port=$PORT mount=$MOUNT"
  cd "$REPO_ROOT"
  if ! git rev-parse --verify --quiet master >/dev/null; then
    die 2 "no master branch in $REPO_ROOT"
  fi
  if [[ -n "$(git status --porcelain)" ]]; then
    say "  WARN working tree has uncommitted changes; a pull may fail"
  fi
  OK_COUNT=$((OK_COUNT + 1))
  step_end true
}

# Resolve the Tailscale host name, either given or detected.
resolve_target() {
  step_begin "resolve target"
  if [[ -z "$TS_HOST" ]]; then
    TS_HOST="$(detect_ts_host)"
    if [[ -z "$TS_HOST" ]]; then
      die 2 "no Tailscale DNS name detected; pass --host <name>"
    fi
    say "  detected tailscale host=$TS_HOST"
  else
    say "  tailscale host=$TS_HOST (given)"
  fi
  PUBLIC_URL="https://$TS_HOST$MOUNT/"
  say "  public url=$PUBLIC_URL"
  OK_COUNT=$((OK_COUNT + 1))
  step_end true
}

# Merge the newest origin/master into the checkout.
update_master() {
  if [[ "$DO_PULL" != true ]]; then
    step_skip "merge origin/master (--no-pull)"
    return 0
  fi
  step_begin "merge origin/master"
  cd "$REPO_ROOT"
  local branch
  branch="$(git rev-parse --abbrev-ref HEAD)"
  if [[ "$branch" != "master" ]]; then
    die 3 "on branch '$branch', expected master"
  fi
  if git rev-parse -q --verify MERGE_HEAD >/dev/null; then
    die 3 "a merge is already in progress; finish or abort it first"
  fi
  # Uncommitted changes are tolerated: git refuses a merge that would overwrite
  # them, which is the protection that matters, and they cannot reach the fork
  # because only committed work is pushed.
  if [[ -n "$(git status --porcelain)" ]]; then
    say "  WARN uncommitted changes present; the merge stops if it would overwrite them"
  fi
  if [[ "$DRY_RUN" == true ]]; then
    say "  DRY-RUN would fetch origin and merge origin/master"
    OK_COUNT=$((OK_COUNT + 1))
    step_end true
    return 0
  fi
  local before behind
  before="$(git rev-parse HEAD)"
  if ! fetch_with_retry; then
    die 3 "git fetch failed after 3 attempts; see $LOG_FILE"
  fi
  behind="$(git rev-list --count HEAD..origin/master 2>/dev/null || echo 0)"
  if [[ "$behind" == "0" ]]; then
    say "  already contains origin/master"
  else
    say "  merging $behind commit(s) from origin/master"
    if ! git merge --no-edit origin/master >> "$LOG_FILE" 2>&1; then
      if git rev-parse -q --verify MERGE_HEAD >/dev/null; then
        # Leave no half-finished merge behind: the next run must start clean.
        git merge --abort >> "$LOG_FILE" 2>&1 || true
        die 3 "merge with origin/master conflicted; the merge was aborted, resolve it by hand"
      fi
      die 3 "git refused the merge, usually because uncommitted changes would be overwritten; see $LOG_FILE"
    fi
    say "  advanced $before -> $(git rev-parse HEAD)"
  fi
  say "  head=$(git log --oneline -1)"
  OK_COUNT=$((OK_COUNT + 1))
  step_end true
}

# Push the merged master to the personal fork. The fork's own master stays
# untouched so it remains usable as a clean base for upstream pull requests.
push_fork() {
  if [[ "$DO_PUSH" != true ]]; then
    step_skip "push to the fork (--no-push)"
    return 0
  fi
  step_begin "push to $PUSH_REMOTE"
  cd "$REPO_ROOT"
  if ! git remote get-url "$PUSH_REMOTE" >/dev/null 2>&1; then
    die 5 "no git remote named '$PUSH_REMOTE'; add it or pass --push-remote"
  fi
  say "  target: $PUSH_REMOTE $PUSH_BRANCH"
  if [[ "$DRY_RUN" == true ]]; then
    say "  DRY-RUN would push master to $PUSH_REMOTE/$PUSH_BRANCH"
    OK_COUNT=$((OK_COUNT + 1))
    step_end true
    return 0
  fi
  # BatchMode and a disabled terminal prompt stop a missing credential from
  # hanging a detached run; the fork remote authenticates over SSH.
  if ! GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes" \
       git push "$PUSH_REMOTE" "master:$PUSH_BRANCH" >> "$LOG_FILE" 2>&1; then
    die 5 "push to $PUSH_REMOTE/$PUSH_BRANCH failed; see $LOG_FILE"
  fi
  say "  pushed master -> $PUSH_REMOTE/$PUSH_BRANCH"
  OK_COUNT=$((OK_COUNT + 1))
  step_end true
}

# Stop the service currently holding the port.
stop_service() {
  step_begin "stop service"
  local pids pid
  pids="$(listening_pids)"
  if [[ -z "$pids" ]]; then
    say "  no listener on port $PORT"
    OK_COUNT=$((OK_COUNT + 1))
    step_end true
    return 0
  fi
  say "  listeners: $(echo "$pids" | tr '\n' ' ')"
  if [[ "$DRY_RUN" == true ]]; then
    say "  DRY-RUN would stop pids: $(echo "$pids" | tr '\n' ' ')"
    OK_COUNT=$((OK_COUNT + 1))
    step_end true
    return 0
  fi
  if [[ "$ASSUME_YES" != true && -t 0 ]]; then
    local reply=""
    read -r -p "Stop the service on port $PORT and restart it? [y/N] " reply
    if [[ ! "$reply" =~ ^[Yy]$ ]]; then
      die 2 "aborted by user"
    fi
  fi
  for pid in $pids; do
    kill "$pid" 2>/dev/null || true
    say "  sent TERM to $pid"
  done
  sleep 2
  pids="$(listening_pids)"
  for pid in $pids; do
    kill -9 "$pid" 2>/dev/null || true
    say "  sent KILL to $pid"
  done
  if ! wait_port_free; then
    die 4 "port $PORT still held after stopping the service"
  fi
  say "  port $PORT free"
  OK_COUNT=$((OK_COUNT + 1))
  step_end true
}

# Start `dsh web` detached and record its pid.
start_service() {
  step_begin "start service"
  SERVICE_LOG="$LOG_DIR/service-$PORT-$(date -u +%Y%m%d-%H%M%S).log"
  say "  cmd: pnpm dsh web --port $PORT --no-open --trusted-host $TS_HOST --public-url $PUBLIC_URL"
  if [[ "$DRY_RUN" == true ]]; then
    say "  DRY-RUN would start the service and log to $SERVICE_LOG"
    OK_COUNT=$((OK_COUNT + 1))
    step_end true
    return 0
  fi
  cd "$REPO_ROOT"
  nohup pnpm dsh web \
    --port "$PORT" --no-open \
    --trusted-host "$TS_HOST" \
    --public-url "$PUBLIC_URL" > "$SERVICE_LOG" 2>&1 < /dev/null &
  SERVICE_PID=$!
  disown 2>/dev/null || true
  say "  started pid=$SERVICE_PID"
  say "  service log=$SERVICE_LOG"
  OK_COUNT=$((OK_COUNT + 1))
  step_end true
}

# Wait for the new service to answer HTTP.
await_readiness() {
  step_begin "await readiness"
  if [[ "$DRY_RUN" == true ]]; then
    say "  DRY-RUN would poll http://127.0.0.1:$PORT/ until it answers"
    OK_COUNT=$((OK_COUNT + 1))
    step_end true
    return 0
  fi
  local code
  if ! code="$(wait_ready)"; then
    die 4 "service on port $PORT did not answer within 90s; see $SERVICE_LOG"
  fi
  say "  http://127.0.0.1:$PORT/ -> $code"
  OK_COUNT=$((OK_COUNT + 1))
  step_end true
}

# Verify the Tailscale path and report the launch URL.
verify_and_report() {
  step_begin "verify"
  if [[ "$DRY_RUN" == true ]]; then
    step_end true
    return 0
  fi
  local code serve_state
  code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 "https://$TS_HOST$MOUNT/" 2>/dev/null || true)"
  say "  https://$TS_HOST$MOUNT/ -> ${code:-no-response}"
  case "${code:-}" in
    200|303|401) ;;
    *) say "  WARN unexpected status through the Tailscale path" ;;
  esac
  serve_state="$(tailscale serve status 2>/dev/null | grep -E "^[|]-- $MOUNT( |$)" || true)"
  if [[ -n "$serve_state" ]]; then
    say "  serve mapping:$(echo "$serve_state" | sed 's/^[|]--/ /')"
  else
    say "  WARN no 'tailscale serve' mapping for $MOUNT; run:"
    say "       tailscale serve --bg --https 443 --set-path $MOUNT http://127.0.0.1:$PORT"
  fi
  # `dsh web` prints its launch URL only after the Loader finishes, so poll the
  # log for that line rather than guessing a fixed delay. A token-less mount URL
  # always answers 401, so it is never reported as the result.
  local waited=0
  while [[ $waited -lt 90 ]]; do
    URL="$(launch_url "$SERVICE_LOG")"
    if [[ -n "$URL" ]]; then
      break
    fi
    sleep 1
    waited=$((waited + 1))
  done
  if [[ -z "$URL" ]]; then
    say "  WARN no launch URL in the service log after ${waited}s"
    say "       read the 'dsh web:' line from $SERVICE_LOG"
    say "URL (unavailable; read the service log named above)"
  else
    say "URL $URL"
  fi
  OK_COUNT=$((OK_COUNT + 1))
  step_end true
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

# Parse the command line; exit 2 on any invalid argument.
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --port)    [[ $# -ge 2 ]] || die 2 "--port needs a value"; PORT="$2"; shift 2 ;;
      --mount)   [[ $# -ge 2 ]] || die 2 "--mount needs a value"; MOUNT="$2"; shift 2 ;;
      --host)    [[ $# -ge 2 ]] || die 2 "--host needs a value"; TS_HOST="$2"; shift 2 ;;
      --url)     SHOW_URL=true; shift ;;
      --push-remote) [[ $# -ge 2 ]] || die 2 "--push-remote needs a value"; PUSH_REMOTE="$2"; shift 2 ;;
      --push-branch) [[ $# -ge 2 ]] || die 2 "--push-branch needs a value"; PUSH_BRANCH="$2"; shift 2 ;;
      --no-push) DO_PUSH=false; shift ;;
      --no-pull) DO_PULL=false; shift ;;
      --detach)  DETACH=true; shift ;;
      --dry-run) DRY_RUN=true; shift ;;
      --restart) RESTART=true; shift ;;
      --yes|-y)  ASSUME_YES=true; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die 2 "unknown argument: $1" ;;
    esac
  done
  if [[ ! "$PORT" =~ ^[0-9]+$ ]]; then
    die 2 "--port must be numeric, got '$PORT'"
  fi
  if [[ "$MOUNT" != /* ]]; then
    die 2 "--mount must start with '/', got '$MOUNT'"
  fi
  MOUNT="${MOUNT%/}"
}

parse_args "$@"

# The read-only query answers for whatever is listening right now, so it runs
# before any state mutation and controls no service.
if [[ "$SHOW_URL" == true ]]; then
  mkdir -p "$LOG_DIR"
  LOG_FILE="$LOG_DIR/url-port$PORT-$(date -u +%Y%m%d-%H%M%S).log"
  : > "$LOG_FILE"
  say "START $SCRIPT_NAME --url port=$PORT"
  show_current_url || exit $?
  exit 0
fi

if [[ "$RESTART" == true ]]; then
  rm -f "$STATE_FILE"
fi

# A detached run re-execs this script in the background so the caller — often a
# Host process that this restart is about to replace — returns immediately.
if [[ "$DETACH" == true ]]; then
  mkdir -p "$LOG_DIR"
  detach_log="$LOG_DIR/detach-$PORT-$(date -u +%Y%m%d-%H%M%S).log"
  forward=(--port "$PORT" --mount "$MOUNT" --yes)
  if [[ -n "$TS_HOST" ]]; then
    forward+=(--host "$TS_HOST")
  fi
  if [[ "$DO_PULL" != true ]]; then
    forward+=(--no-pull)
  fi
  if [[ "$DO_PUSH" != true ]]; then
    forward+=(--no-push)
  fi
  forward+=(--push-remote "$PUSH_REMOTE" --push-branch "$PUSH_BRANCH")
  nohup "$0" "${forward[@]}" > "$detach_log" 2>&1 < /dev/null &
  disown 2>/dev/null || true
  printf 'restart scheduled; follow %s\n' "$detach_log"
  exit 0
fi

mkdir -p "$LOG_DIR" "$STATE_DIR"
LOG_FILE="$LOG_DIR/$SCRIPT_NAME-$(date -u +%Y%m%d-%H%M%S).log"
: > "$LOG_FILE"

say "START $SCRIPT_NAME port=$PORT mount=$MOUNT dryRun=$DRY_RUN"
write_state running "started"

check_preconditions
resolve_target
update_master
push_fork
stop_service
start_service
await_readiness
verify_and_report

write_state ok "service ready" "$SERVICE_PID" "$URL"
say "SUMMARY: ok=$OK_COUNT fail=$FAIL_COUNT skipped=$SKIP_COUNT"
say "DONE in ${SECONDS}s"
