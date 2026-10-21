# Apply AI Governance policies with Docker Sandboxes

Clone this repository, run it as a kit, and ask the agent to apply its policies to
your Docker organization.

You need Docker Sandboxes (`sbx` v0.45 or later)
and an account authorized to manage your organization's governance
policies. The selected team must already exist. The example uses Docker's v3
Codex workload; complete its agent sign-in separately.

Docker Hub registry authentication uses your existing `sbx` login session; see
[Docker registry authentication](https://docs.docker.com/ai/sandboxes/workflows/authentication/#docker-registry).
Governance API calls require a JWT obtained by exchanging a Docker Hub credential.
The agent must verify API access before changing policies.

## 1. Clone the repository

```bash
git clone https://github.com/GannaChernyshova/ai-gov-policy-example.git
cd ai-gov-policy-example
```

Run the remaining commands from this directory.

## 2. Store governance credentials

The governance API requires a JWT, and the token endpoint takes the PAT in a JSON
body, which sandbox proxy substitution cannot fill in. So the exchange runs on your
host: [`scripts/aig-jwt.sh`](scripts/aig-jwt.sh) trades your Docker Hub PAT for a
short-lived JWT and registers the JWT as a custom secret. The PAT never enters the
sandbox, and the agent only sees a placeholder in `AIG_DOCKER_JWT`, which the proxy
swaps for the real JWT in the `Authorization: Bearer` header on `hub.docker.com`.

Export your PAT in the shell you run the script from (`curl` and `jq` are required
on the host):

```bash
export DOCKER_PAT="your_actual_token_here"
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
without `--set` prints only the JWT, so it can serve as the secret's command. The
command runs under `sbx`, so `DOCKER_PAT` must be in the environment of the process
that starts it:

```bash
sbx secret set-custom --sandbox aig-policies --host hub.docker.com \
  --env AIG_DOCKER_JWT --refresh 5m \
  --command "$PWD/scripts/aig-jwt.sh YOUR_DOCKER_USERNAME"
```

See [custom secrets](https://docs.docker.com/ai/sandboxes/configuration/credentials/#custom-secrets).
Replacement applies only to request headers, never bodies.

## 3. Run the kit

Run the command below, replacing the Docker organization and team:

```bash
sbx run docker.io/docker/sbx-kit-codex:0.155.1 --name aig-policies \
  --kit "$PWD" \
  --kit-arg org=YOUR_DOCKER_ORG \
  --kit-arg team=YOUR_TEAM
```

The kit is loaded from the cloned directory. Pass its full path (`"$PWD"`), not
`.`: `sbx` takes the kit name from the last path component, and `.` is rejected as
an invalid name. Your host must allow local kits
(`sbx settings get kit.allowLocalKits`; it is on by default). The organization
argument is required.

## 4. Ask the agent to apply the policies

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
