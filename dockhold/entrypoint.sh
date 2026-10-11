#!/bin/sh
# Start script for Hermes Agent on Dockhold.
#
# Dockhold hands this app a port (PORT), its own address
# (DOCKHOLD_APP_HOSTNAME) and, when App storage is turned on, a folder that
# survives restarts and deploys (DATA_DIR, which is /data). The template
# keeps all of Hermes' state under /data, so this script checks that App
# storage is there and that the admin password is set, gives Hermes the
# app's public address, and then hands over to the template's own start.sh.
# It never prints a secret value.
#
# Every check below fails with one line and exit code 1. Dockhold shows that
# line on the app page, so the line is the whole error message.
set -eu

# 1. App storage.
#
# Hermes keeps its config, pairings, chat history, skills and memory under
# /data/.hermes. Without App storage that folder would be gone after the
# next restart, so the app refuses to start instead of starting empty.
storage_missing() {
  echo "This app keeps its data on App storage. Turn on App storage in the Size tab; the app restarts on its own." >&2
  exit 1
}
[ "${DATA_DIR:-}" = "/data" ] || storage_missing
[ -d /data ] || storage_missing
# Permission bits can say "writable" on a folder that is mounted read-only.
# Creating and removing a file is the only check that cannot be fooled.
probe="/data/.dockhold-write-check.$$"
( : > "$probe" ) 2>/dev/null || storage_missing
rm -f "$probe"

# 2. The admin password.
#
# The template would generate a random password and print it to the log.
# This app is reachable on a public address and its agent can run commands,
# so the password comes from Dockhold's Secrets instead, and it must be long
# enough to resist guessing.
if [ -z "${ADMIN_PASSWORD:-}" ]; then
  echo "ADMIN_PASSWORD is missing or empty. Add it as a secret on this app's Variables tab and restart." >&2
  exit 1
fi
if [ "${#ADMIN_PASSWORD}" -lt 12 ]; then
  echo "ADMIN_PASSWORD is shorter than 12 characters. Change the secret's value under Secrets in the dashboard sidebar and restart." >&2
  exit 1
fi

# 3. The public address.
#
# Hermes builds the return address for MCP tool sign-ins from the app's
# public domain, which the template reads from RAILWAY_PUBLIC_DOMAIN.
# Dockhold sets DOCKHOLD_APP_HOSTNAME instead. A value set by hand wins.
if [ -z "${RAILWAY_PUBLIC_DOMAIN:-}" ] && [ -n "${DOCKHOLD_APP_HOSTNAME:-}" ]; then
  RAILWAY_PUBLIC_DOMAIN="$DOCKHOLD_APP_HOSTNAME"
  export RAILWAY_PUBLIC_DOMAIN
fi

exec /app/start.sh
