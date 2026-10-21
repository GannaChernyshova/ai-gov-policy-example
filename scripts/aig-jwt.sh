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
# To refresh an existing secret, re-run with --set and the placeholder printed the first
# time: AIG_PLACEHOLDER=sbx-cs-... aig-jwt.sh --set DOCKER_USERNAME
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

# The JWT is short-lived, so exposing it in this process's arguments is a small risk.
args=(secret set-custom --sandbox "$sandbox" --host hub.docker.com --env AIG_DOCKER_JWT --value "$jwt")
if [ -n "${AIG_PLACEHOLDER:-}" ]; then
  args+=(--placeholder "$AIG_PLACEHOLDER")
fi
sbx "${args[@]}"
