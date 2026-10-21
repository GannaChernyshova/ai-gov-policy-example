# Apply AI Governance policies with Docker Sandboxes

Run this kit from GitHub and ask the agent to apply its policies to your Docker
organization.

You need Docker Sandboxes (`sbx` v0.45 or later)
and an account authorized to manage your organization's governance
policies. The selected team must already exist. The example uses Docker's v3
Codex workload; complete its agent sign-in separately.

Docker Hub registry authentication uses your existing `sbx` login session; see
[Docker registry authentication](https://docs.docker.com/ai/sandboxes/workflows/authentication/#docker-registry).
Governance API calls require a JWT obtained by exchanging a Docker Hub credential.
The agent must verify API access before changing policies.

## 1. Store governance credentials

The governance API requires a JWT, and the token endpoint takes the PAT in a JSON
body, which sandbox proxy substitution cannot fill in. So the exchange runs on your
host: [`scripts/aig-jwt.sh`](scripts/aig-jwt.sh) trades your Docker Hub PAT for a
short-lived JWT and registers the JWT as a custom secret. The PAT never enters the
sandbox, and the agent only sees a placeholder in `AIG_DOCKER_JWT`, which the proxy
swaps for the real JWT in the `Authorization: Bearer` header on `hub.docker.com`.

Store your PAT in the macOS Keychain (`curl` and `jq` are required on the host):

```bash
security add-generic-password -s aig-docker-hub -a "$USER" -w   # prompts for the PAT
```

Then, from a checkout of this repository, register the JWT for the sandbox used below:

```bash
./scripts/aig-jwt.sh --set YOUR_DOCKER_USERNAME aig-policies
```

The script runs `sbx secret set-custom --sandbox aig-policies --host hub.docker.com
--env AIG_DOCKER_JWT --value <JWT>` and prints the generated placeholder. Run it
before creating the sandbox. For an existing sandbox, set `AIG_DOCKER_JWT` inside
it to that placeholder.

The JWT is short-lived. When the agent's requests start returning 401, refresh the
secret by passing the existing placeholder:

```bash
AIG_PLACEHOLDER=sbx-cs-... ./scripts/aig-jwt.sh --set YOUR_DOCKER_USERNAME aig-policies
```

Alternatively, let `sbx` refresh it automatically. `aig-jwt.sh YOUR_DOCKER_USERNAME`
without `--set` prints only the JWT, so it can serve as the secret's command:

```bash
sbx secret set-custom --sandbox aig-policies --host hub.docker.com \
  --env AIG_DOCKER_JWT --refresh 5m \
  --command "$PWD/scripts/aig-jwt.sh YOUR_DOCKER_USERNAME"
```

See [custom secrets](https://docs.docker.com/ai/sandboxes/configuration/credentials/#custom-secrets).
Replacement applies only to request headers, never bodies.

## 2. Run the kit from GitHub

Allow the repository as a kit source on your host. Inspect
`sbx settings get kit.allowedSources` first and retain any existing entries.
For a host using the default allowlist:

```bash
sbx settings set kit.allowedSources '["docker.io/","github.com/GannaChernyshova/ai-gov-policy-example"]'
```

Run the command below, replacing the Docker organization, team, and username:

```bash
sbx run docker.io/docker/sbx-kit-codex:0.155.1 --name aig-policies \
  --kit 'git+https://github.com/GannaChernyshova/ai-gov-policy-example.git#ref=main' \
  --kit-arg org=YOUR_DOCKER_ORG \
  --kit-arg team=YOUR_TEAM \
  --kit-arg docker_username=YOUR_DOCKER_USERNAME
```

The command uses the `main` branch; pin a release tag once one includes
`scripts/aig-jwt.sh`. The organization argument is required. The agent does not
read the Docker username; the script in step 1 uses it for the token exchange.

## 3. Ask the agent to apply the policies

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

References: [Kits](https://docs.docker.com/ai/sandboxes/customize/)
and [AI Governance API](https://docs.docker.com/reference/api/ai-governance/latest/).

## If authentication returns 401

Ask the agent to report the failing method, full URL, and status without exposing
credentials. A failure at `/v2/auth/token` means the JWT exchange failed; a failure
at `/v2/orgs/.../governance/policies` occurs when using the JWT. A successful Docker
image pull alone does not verify governance API access.
