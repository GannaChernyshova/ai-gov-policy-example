# Apply AI Governance policies with Docker Sandboxes

An `sbx` kit that gives a coding agent the policy payloads in `policies/` and the
instructions in `AGENTS.md` to apply them to a Docker organization through the
[AI Governance API](https://docs.docker.com/reference/api/ai-governance/latest/).

## Requirements

- Docker Sandboxes (`sbx` v0.45 or later), signed in. The example uses the Codex
  agent; complete its sign-in separately.
- `curl` and `jq` on the host.
- An existing Docker Hub team to scope the team restrictions to. Create one before you run the agent: [how to create a Team](https://docs.docker.com/accounts/organization/manage/manage-a-team/) 
- An organization access token (OAT) with the scopes `scope-group-read` and
  `scope-governance-policy-write`. Use an OAT, not a personal access token:
  `GET /v2/orgs/{org}/groups` rejects JWTs issued from a PAT. See
  [how to create an OAT](https://docs.docker.com/security/access-tokens/organization-access-tokens/)
  and the [scope reference](https://docs.docker.com/security/access-tokens/reference/).

## How authentication works

The governance API requires a JWT from `POST /v2/auth/token`. That endpoint takes the
token in a JSON body, and the sandbox proxy only substitutes secrets in request
headers. So the exchange runs on the host:

1. `scripts/aig-jwt.sh` exchanges the OAT (identifier: the org name) for a JWT that is
   valid for about 10 minutes.
2. It stores the JWT with `sbx secret set-custom` as `AIG_DOCKER_JWT` for
   `hub.docker.com`.
3. In the sandbox, `AIG_DOCKER_JWT` is a placeholder. The agent sends
   `Authorization: Bearer $AIG_DOCKER_JWT`, and the proxy replaces the placeholder
   with the JWT. The OAT and the JWT never enter the sandbox.

## Setup

```bash
git clone https://github.com/GannaChernyshova/ai-gov-policy-example.git
cd ai-gov-policy-example

export DOCKER_OAT="dckr_oat_..."
./scripts/aig-jwt.sh --set YOUR_DOCKER_ORG aig-policies
```

The script runs `sbx secret set-custom --sandbox aig-policies --host hub.docker.com
--env AIG_DOCKER_JWT --placeholder sbx-cs-aig-docker-jwt --value <JWT>`. Run it before
creating the sandbox. The sandbox name (`aig-policies`) must match the one used below.

## Run

```bash
sbx run docker.io/docker/sbx-kit-codex:0.155.1 --name aig-policies \
  --kit "$PWD" \
  --kit-arg org=YOUR_DOCKER_ORG \
  --kit-arg team=YOUR_TEAM
```

- Pass the full path (`"$PWD"`), not `.`. `sbx` takes the kit name from the last path
  component and rejects `.`.
- Local kits must be allowed on the host (`sbx settings get kit.allowLocalKits`).
- `org` is required. `team` defaults to `aig-demo-team`.

Then paste this into the agent. Starting the sandbox alone changes nothing.

```text
Apply the included AI Governance policies to the organization in AIG_ORG and the team in AIG_TEAM. Follow the kit's AGENTS.md, back up existing policies before changing them, preserve unrelated policies, and verify the resulting scopes and rules. Report the policy IDs, rule counts, and any failures.
```

## What gets applied

| Policy | Rules | Scope |
| --- | --- | --- |
| Network | 41 | Organization |
| Filesystem | 4 | Organization |
| Network restrictions | 4 | Selected team only |
| Notion (Cedar) | embedded | Organization |
| GitHub (Cedar) | embedded | Organization |
| CrowdStrike Falcon (Cedar) | embedded | Organization |
| Jira (Cedar) | embedded | Organization |

The agent backs up existing policies, reuses matching ones instead of duplicating them,
applies the seven policies, and verifies scopes, rule contents and counts against the
payloads. It reports the policy IDs and any failures.

Policy changes take up to five minutes to reach developer machines. Filesystem policies
apply to new sandbox mounts only and do not hide `.env` files inside an allowed
workspace. Copy the backups out of the sandbox before removing it.

## Refresh an expired JWT

The JWT expires after about 10 minutes. When the agent's requests return 401, rerun:

```bash
./scripts/aig-jwt.sh --set YOUR_DOCKER_ORG aig-policies
```

`sbx secret set-custom` fails if the variable already exists and there is no update
command, so the script removes the old secret and recreates it with the same
placeholder. The running sandbox keeps working without changes.

To have `sbx` refresh the JWT itself, use the script as the secret's command instead.
It runs under `sbx`, so `DOCKER_OAT` must be in the environment of the process that
starts it. Remove any existing `AIG_DOCKER_JWT` secret first
(`sbx secret rm --sandbox aig-policies --placeholder PLACEHOLDER`):

```bash
sbx secret set-custom --sandbox aig-policies --host hub.docker.com \
  --env AIG_DOCKER_JWT --refresh 5m \
  --command "$PWD/scripts/aig-jwt.sh YOUR_DOCKER_ORG"
```

## Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| `403 token issued from personal access token is not allowed` | A PAT-issued JWT was used. Use an OAT. |
| `403` on `/v2/orgs/{org}/groups` | The OAT lacks `scope-group-read`. |
| `403` on `/governance/policies` | The OAT lacks `scope-governance-policy-write`. |
| `401` on `/governance/policies` | The JWT expired. Refresh it as above. |
| `error: custom secret env ... already exists` | Run `aig-jwt.sh --set`, which replaces it. |
| `invalid name "."` from `sbx run` | Pass `--kit "$PWD"`, not `--kit .`. |

Ask the agent to report the failing method, full URL and status, without headers or
response bodies.

References: [Kits](https://docs.docker.com/ai/sandboxes/customize/),
[organization access tokens](https://docs.docker.com/security/access-tokens/organization-access-tokens/),
[custom secrets](https://docs.docker.com/ai/sandboxes/configuration/credentials/#custom-secrets).
