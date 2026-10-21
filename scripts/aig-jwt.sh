#!/bin/bash
# Host-side helper. Exchanges a Docker Hub organization access token (OAT) for a
# short-lived JWT at POST /v2/auth/token, so the OAT never enters the sandbox and the
# sandbox only sees a custom-secret placeholder for the JWT.
#
# Usage:
#   aig-jwt.sh ORG                  print the JWT (for `sbx secret set-custom --command`)
#   aig-jwt.sh --set ORG [SANDBOX]  register the JWT as AIG_DOCKER_JWT with
#                                   `sbx secret set-custom` (SANDBOX defaults to aig-policies)
#
# --set is re-runnable: `sbx secret set-custom` fails if the env already exists in the
# scope and there is no update command, so any existing secret with the fixed
# placeholder below is removed first. The placeholder stays the same across refreshes,
# so a running sandbox keeps working without changes.
#
# Token source: the DOCKER_OAT environment variable (export DOCKER_OAT="dckr_oat_...").
# The OAT needs the Group Read and Governance Policy Write scopes. The JWT lives about
# 10 minutes. Requires curl and jq on the host.
set -euo pipefail

set_secret=false
if [ "${1:-}" = "--set" ]; then
  set_secret=true
  shift
fi
org=${1:?usage: aig-jwt.sh [--set] ORG [SANDBOX]}
sandbox=${2:-aig-policies}
oat=${DOCKER_OAT:?export DOCKER_OAT with your organization access token first}
case $oat in
  dckr_oat_*) ;;
  *) echo "DOCKER_OAT must be an organization access token (dckr_oat_...)" >&2; exit 1 ;;
esac

# The identifier for an OAT is the organization name. The body goes through stdin so the
# OAT never appears in a process argument list.
jwt=$(printf '{"identifier":"%s","secret":"%s"}' "$org" "$oat" \
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
