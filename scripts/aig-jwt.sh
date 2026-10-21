#!/bin/bash
# Host-side helper. Exchanges a Docker Hub PAT for a short-lived JWT at
# POST /v2/auth/token, so the PAT never enters the sandbox and the sandbox only
# sees a custom-secret placeholder for the JWT.
#
# Usage:
#   aig-jwt.sh DOCKER_USERNAME                  print the JWT (for `sbx secret set-custom --command`)
#   aig-jwt.sh --set DOCKER_USERNAME [SANDBOX]  register the JWT as AIG_DOCKER_JWT with
#                                               `sbx secret set-custom` (SANDBOX defaults to aig-policies)
#
# --set is re-runnable: `sbx secret set-custom` fails if the env already exists in the
# scope and there is no update command, so any existing secret with the fixed
# placeholder below is removed first. The placeholder stays the same across refreshes,
# so a running sandbox keeps working without changes.
#
# PAT source: the DOCKER_PAT environment variable (export DOCKER_PAT="..."). Requires
# curl and jq on the host.
set -euo pipefail

set_secret=false
if [ "${1:-}" = "--set" ]; then
  set_secret=true
  shift
fi
username=${1:?usage: aig-jwt.sh [--set] DOCKER_USERNAME [SANDBOX]}
sandbox=${2:-aig-policies}
pat=${DOCKER_PAT:?export DOCKER_PAT with your Docker Hub PAT first}

# Body goes through stdin so the PAT never appears in a process argument list.
jwt=$(printf '{"identifier":"%s","secret":"%s"}' "$username" "$pat" \
  | curl -fsS -X POST https://hub.docker.com/v2/auth/token \
      -H 'Content-Type: application/json' -d @- \
  | jq -er .access_token)

if ! $set_secret; then
  printf '%s\n' "$jwt"
  exit 0
fi

placeholder=sbx-cs-aig-docker-jwt

# Remove the previous secret, if any. A first run has nothing to delete.
printf 'y\n' | sbx secret rm --sandbox "$sandbox" --placeholder "$placeholder" >/dev/null 2>&1 || true

# The JWT is short-lived, so exposing it in this process's arguments is a small risk.
sbx secret set-custom --sandbox "$sandbox" --host hub.docker.com --env AIG_DOCKER_JWT \
  --placeholder "$placeholder" --value "$jwt"
