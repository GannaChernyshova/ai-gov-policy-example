# Apply AI Governance policies with Docker Sandboxes

Run this kit from GitHub and ask the agent to apply its policies to your Docker
organization.

You need Docker Sandboxes (`sbx` v0.45 or later)
and an account authorized to manage your organization's governance
policies. The selected team must already exist. The example uses Docker's v3
Codex workload; complete its agent sign-in separately.

Docker Hub registry authentication uses your existing `sbx` login session; see
[Docker registry authentication](https://docs.docker.com/ai/sandboxes/workflows/authentication/#docker-registry).
Governance API calls still require a valid JWT. This example does not configure
credentials; the agent must verify API access before changing policies.

## 1. Run the kit from GitHub

Allow the repository as a kit source on your host. Inspect
`sbx settings get kit.allowedSources` first and retain any existing entries.
For a host using the default allowlist:

```bash
sbx settings set kit.allowedSources '["docker.io/","github.com/GannaChernyshova/ai-gov-policy-example"]'
```

Run the command below, replacing the Docker organization, team, and username.:

```bash
sbx run docker.io/docker/sbx-kit-codex:0.155.1 --name aig-policies \
  --kit 'git+https://github.com/GannaChernyshova/ai-gov-policy-example.git#ref=v1.0.8' \
  --kit-arg org=YOUR_DOCKER_ORG \
  --kit-arg team=YOUR_TEAM \
  --kit-arg docker_username=YOUR_DOCKER_USERNAME
```

The command uses the `v1.0.8` release. The organization argument is required.

## 2. Ask the agent to apply the policies

Copy and paste this into the agent:

```text
Apply the included AI Governance policies to the organization in AIG_ORG and the team in AIG_TEAM. Follow the kit's AGENTS.md, back up existing policies before changing them, preserve unrelated policies, and verify the resulting scopes and rules. Report the policy IDs, rule counts, and any failures.
```

The kit registers `AGENTS.md` with the agent and supplies policy files under
`/opt/aig-policies`. The agent backs up existing policies, applies changes, and
reports verified IDs, scopes, counts, and failures. Starting the sandbox alone
does not change policies.

| Policy | Scope |
| --- | --- |
| Network rules (41) | Organization |
| Filesystem rules (4) | Organization |
| Network restrictions (4) | Selected team only |
| Notion Cedar policy | Organization |

Changes can take up to five minutes to propagate. Filesystem policies affect new
sandbox mounts; they do not hide `.env` files inside an allowed workspace. Copy
policy backups out of the sandbox before removing it if you need to retain them.

To return to the same sandbox, run `sbx run --name aig-policies`. To use different
kit arguments or a newer kit revision, create a sandbox with a new name.

References: [Kits](https://docs.docker.com/ai/sandboxes/customize/),
and [AI Governance API](https://docs.docker.com/reference/api/ai-governance/latest/).

## If authentication returns 401

Ask the agent to report the failing method, full URL, and status without exposing
credentials. A failure at `/v2/auth/token` means the JWT exchange failed; a failure
at `/v2/orgs/.../governance/policies` occurs when using the JWT. A successful Docker
image pull alone does not verify governance API access.
