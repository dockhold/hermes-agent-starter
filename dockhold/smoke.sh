#!/usr/bin/env bash
# Smoke test for the hermes-agent-starter image, run the way Dockhold runs
# it: user 1001, every capability dropped, no privilege escalation, 1 GB of
# memory and no swap (the app size this starter recommends), App storage
# mounted at /data owned root:1001 with mode 2770, a fixed PORT, and the
# address variable Dockhold sets.
#
# One restriction goes further than Dockhold does: the root filesystem is
# read-only, with only /tmp writable, which proves the app writes nothing
# outside /data and /tmp. Unlike the other Dockhold starters, outbound
# network stays on: an agent has to reach its model provider, so the "no
# outbound network" check does not apply here. No model is called; the
# provider key is a placeholder.
#
# Usage: dockhold/smoke.sh <image>
# Needs: docker, curl, jq, bash 4 or newer. Exits non-zero if any case fails.
# Prints one PASS or FAIL line per case, INFO lines for measurements, and the
# container log after a failure. Expect about five minutes.
set -euo pipefail

IMAGE=${1:?usage: dockhold/smoke.sh <image>}
HELPER_IMAGE=alpine:3.20
RUN="hermessmoke-$$-$RANDOM"
APP="$RUN-app"
VOL="$RUN-data"
MEM=1g
HOSTNAME_VALUE="hermes-smoke.example"
PASSWORD="smoke-$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')"
BASE=$(mktemp -d "${TMPDIR:-/tmp}/hermessmoke.XXXXXX")
JAR="$BASE/cookies"
STORAGE_LINE="This app keeps its data on App storage. Turn on App storage in the Size tab; the app restarts on its own."
PW_MISSING_LINE="ADMIN_PASSWORD is missing or empty. Add it as a secret on this app's Variables tab and restart."
PW_SHORT_LINE="ADMIN_PASSWORD is shorter than 12 characters. Change the secret's value under Secrets in the dashboard sidebar and restart."

PASS_COUNT=0
FAIL_COUNT=0
URL=""

pass() { echo "PASS  $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() {
  echo "FAIL  $1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  echo "----- container log ($APP) -----"
  docker logs "$APP" 2>&1 | tail -n 40 || true
  echo "-------------------------------"
}
report() { if [ "$2" = true ]; then pass "$1"; else fail "$1"; fi; }
info() { echo "INFO  $1"; }

cleanup() {
  docker rm -f "$APP" >/dev/null 2>&1 || true
  docker volume rm -f "$VOL" >/dev/null 2>&1 || true
  rm -rf "$BASE"
}
trap cleanup EXIT

# The flags Dockhold runs every app with, plus the read-only root.
run_flags=(
  --user 1001:1001 --cap-drop ALL --security-opt no-new-privileges
  --memory "$MEM" --memory-swap "$MEM"
  --read-only --tmpfs /tmp:rw,exec,mode=1777
  -e PORT=8080 -e DOCKHOLD_APP_HOSTNAME="$HOSTNAME_VALUE"
)

# Fresh App storage: an empty volume (nocopy, so nothing from the image is
# copied in), owned root:1001 with mode 2770.
new_storage() {
  docker volume rm -f "$VOL" >/dev/null 2>&1 || true
  docker volume create "$VOL" >/dev/null
  docker run --rm -v "$VOL:/data:nocopy" "$HELPER_IMAGE" sh -c 'chown 0:1001 /data && chmod 2770 /data'
}

# Runs the image to completion and checks it refused with exactly one line.
expect_refusal() {
  local name=$1 line=$2; shift 2
  local out rc=0
  # An image that starts instead of refusing would run forever; give up after
  # a minute and count it as a failure.
  out=$(timeout 60 docker run --rm --name "$RUN-refusal" "${run_flags[@]}" "$@" "$IMAGE" 2>&1) || rc=$?
  docker rm -f "$RUN-refusal" >/dev/null 2>&1 || true
  report "$name" "$([ "$rc" -eq 1 ] && [ "$out" = "$line" ] && echo true || echo false)"
  if [ "$rc" -ne 1 ] || [ "$out" != "$line" ]; then echo "      exit $rc, output: $out"; fi
}

start_app() {
  docker rm -f "$APP" >/dev/null 2>&1 || true
  docker run -d --name "$APP" "${run_flags[@]}" -e DATA_DIR=/data -e ADMIN_PASSWORD="$PASSWORD" \
    -v "$VOL:/data:nocopy" -p 127.0.0.1::8080 "$IMAGE" >/dev/null
  URL="http://$(docker port "$APP" 8080/tcp | head -n 1)"
}

wait_healthy() {
  local i
  for i in $(seq 1 60); do
    [ "$(curl -s -o /dev/null -w '%{http_code}' "$URL/health" || true)" = 200 ] && return 0
    sleep 1
  done
  return 1
}

login() { # login <password>; leaves the session cookie in $JAR
  rm -f "$JAR"
  curl -s -o /dev/null -c "$JAR" -b "$JAR" --data-urlencode username=admin --data-urlencode "password=$1" "$URL/setup/login"
}

status_code() { curl -s -o /dev/null -w '%{http_code}' -b "$JAR" "$URL/setup/api/status"; }

gateway_state() { curl -s -b "$JAR" "$URL/setup/api/status" | jq -r '.gateway.state // empty'; }

wait_gateway_running() {
  local i
  for i in $(seq 1 90); do
    [ "$(gateway_state)" = running ] && return 0
    sleep 1
  done
  return 1
}

mem_mib() { docker stats --no-stream --format '{{.MemUsage}}' "$APP" | awk '{print $1}'; }

# ---- 1. Refusals ---------------------------------------------------------

new_storage
expect_refusal "refuses to start when App storage is off (no DATA_DIR)" "$STORAGE_LINE" \
  -e ADMIN_PASSWORD="$PASSWORD" -v "$VOL:/data:nocopy"
expect_refusal "refuses to start when DATA_DIR is set but /data is not writable" "$STORAGE_LINE" \
  -e DATA_DIR=/data -e ADMIN_PASSWORD="$PASSWORD"
expect_refusal "refuses to start without ADMIN_PASSWORD" "$PW_MISSING_LINE" \
  -e DATA_DIR=/data -v "$VOL:/data:nocopy"
expect_refusal "refuses an ADMIN_PASSWORD shorter than 12 characters" "$PW_SHORT_LINE" \
  -e DATA_DIR=/data -e ADMIN_PASSWORD=short-pw -v "$VOL:/data:nocopy"

# ---- 2. First start ------------------------------------------------------

start_app
t0=$(date +%s)
if wait_healthy; then pass "first start: /health answers 200 ($(( $(date +%s) - t0 )) s)"; else fail "first start: /health answers 200"; fi

rm -f "$JAR"
code=$(status_code)
report "admin API refuses a request with no session (got $code)" "$([ "$code" != 200 ] && echo true || echo false)"

login "wrong-password-for-smoke"
code=$(status_code)
report "a wrong password does not open the admin API (got $code)" "$([ "$code" != 200 ] && echo true || echo false)"

login "$PASSWORD"
code=$(status_code)
report "the ADMIN_PASSWORD secret opens the admin API (got $code)" "$([ "$code" = 200 ] && echo true || echo false)"

sleep 5
report "Hermes gets the app's public address from DOCKHOLD_APP_HOSTNAME" \
  "$(docker logs "$APP" 2>&1 | grep -qF "public_url=https://$HOSTNAME_VALUE" && echo true || echo false)"

code=$(curl -s -o /dev/null -w '%{http_code}' -b "$JAR" "$URL/sessions")
report "the Hermes dashboard is served behind the login (got $code)" "$([ "$code" = 200 ] && echo true || echo false)"
info "memory after first start, no provider: $(mem_mib)"

# ---- 3. Gateway ----------------------------------------------------------

curl -s -o /dev/null -b "$JAR" -X PUT -H 'content-type: application/json' \
  -d '{"vars":{"OPENROUTER_API_KEY":"sk-or-v1-smoke-placeholder","LLM_MODEL":"openai/gpt-oss-20b:free"},"_restart":true,"_active_provider_key":"OPENROUTER_API_KEY"}' \
  "$URL/setup/api/config"
if wait_gateway_running; then pass "saving a provider starts the gateway"; else fail "saving a provider starts the gateway"; fi
sleep 15
info "memory with the gateway running, no channel: $(mem_mib)"

# ---- 4. Pairing without a restart ----------------------------------------
#
# A message from an unknown user makes Hermes' gateway create a pending
# request in its PairingStore. Here the same call is made inside the app,
# and that one store object then waits to see the user approved. The admin
# panel's Approve button is the only other step. If an approval needed a
# restart, the waiting store would never see it.

docker exec -i "$APP" sh -c 'cat > /tmp/pairing-probe.py' <<'PY'
import sys, time
from gateway.pairing import PairingStore
store = PairingStore()
store.generate_code("telegram", "424242", "smoke-user")
print("pending", flush=True)
assert not store.is_approved("telegram", "424242")
deadline = time.time() + 30
while time.time() < deadline:
    if store.is_approved("telegram", "424242"):
        print("approved", flush=True)
        sys.exit(0)
    time.sleep(0.5)
print("timeout", flush=True)
sys.exit(1)
PY
docker exec -e HERMES_HOME=/data/.hermes -w /opt/hermes-agent "$APP" python /tmp/pairing-probe.py > "$BASE/probe.out" 2>&1 &
probe_pid=$!
pending_code=""
for i in $(seq 1 20); do
  pending_code=$(curl -s -b "$JAR" "$URL/setup/api/pairing/pending" | jq -r '.pending[] | select(.user_id == "424242") | .code' | head -n 1)
  [ -n "$pending_code" ] && break
  sleep 1
done
report "a new user shows up as a pending pairing request" "$([ -n "$pending_code" ] && echo true || echo false)"
curl -s -o /dev/null -b "$JAR" -X POST -H 'content-type: application/json' \
  -d "{\"platform\":\"telegram\",\"code\":\"$pending_code\"}" "$URL/setup/api/pairing/approve"
probe_rc=0; wait "$probe_pid" || probe_rc=$?
report "Approve takes effect in the running store, no restart" \
  "$([ "$probe_rc" -eq 0 ] && grep -qx approved "$BASE/probe.out" && echo true || echo false)"
[ "$probe_rc" -eq 0 ] || cat "$BASE/probe.out"

# ---- 5. Restart keeps everything -----------------------------------------

t0=$(date +%s.%N)
docker stop -t 60 "$APP" >/dev/null
stop_s=$(echo "$(date +%s.%N) - $t0" | bc)
exit_code=$(docker inspect "$APP" --format '{{.State.ExitCode}}')
report "stops cleanly on SIGTERM (exit $exit_code in ${stop_s} s)" \
  "$([ "$exit_code" = 0 ] && [ "$(echo "$stop_s < 30" | bc)" = 1 ] && echo true || echo false)"

docker start "$APP" >/dev/null
URL="http://$(docker port "$APP" 8080/tcp | head -n 1)"
wait_healthy || true
login "$PASSWORD"
if wait_gateway_running; then pass "after a restart the gateway starts again with the saved provider"; else fail "after a restart the gateway starts again with the saved provider"; fi
approved=$(curl -s -b "$JAR" "$URL/setup/api/pairing/approved" | jq -r '[.. | objects | select(.user_id? == "424242")] | length')
report "after a restart the approved user is still approved" "$([ "${approved:-0}" -ge 1 ] && echo true || echo false)"

# ---- 6. Where it writes --------------------------------------------------

outside=$(docker exec "$APP" sh -c 'find /data -xdev ! -user 1001 ! -path /data 2>/dev/null | head -n 5')
report "every file under /data belongs to the app's user" "$([ -z "$outside" ] && echo true || echo false)"
[ -z "$outside" ] || echo "      $outside"
info "App storage used: $(docker exec "$APP" du -sh /data 2>/dev/null | awk '{print $1}')"

echo
echo "$PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
