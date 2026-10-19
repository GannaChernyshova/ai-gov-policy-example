# Apply AI Governance policies with Docker Sandboxes

Run this kit from GitHub and ask the agent to apply its policies to your Docker
organization.

You need Docker Sandboxes (`sbx` v0.45 or later with custom-secret support), Docker
with Buildx, and an account authorized to manage your organization's governance
policies. The selected team must already exist. The example uses Docker's v3
Codex workload; complete its agent sign-in separately.

## 1. Configure your Docker Hub PAT

On your **Mac**, open Keychain Access and create a password item named
`aig-docker-token`, with your Docker Hub PAT as its password. Then run on the host:

```bash
sbx secret set-custom --sandbox aig-policies \
  --host hub.docker.com --env AIG_DOCKER_TOKEN \
  --command '/usr/bin/security find-generic-password -s aig-docker-token -w'
```

For a password manager instead of macOS Keychain, replace `--command ...` with
`--ref 'op://YOUR_VAULT/Docker Hub/password'` (requires a configured, authenticated
resolver). Custom secrets are experimental.

The PAT stays on the host. The sandbox receives a placeholder that the proxy
replaces in requests to Docker Hub. Never put the PAT in chat, kit arguments,
or repository files.

## 2. Run the kit from GitHub

Allow the repository as a kit source on your host. Inspect
`sbx settings get kit.allowedSources` first and retain any existing entries.
For a host using the default allowlist:

```bash
sbx settings set kit.allowedSources '["docker.io/","github.com/GannaChernyshova/ai-gov-policy-example"]'
```

Run the command below, replacing the Docker organization, team, and username. Use the same sandbox name as the secret setup:

```bash
sbx run docker.io/docker/sbx-kit-codex:0.155.1 --name aig-policies \
  --kit 'git+https://github.com/GannaChernyshova/ai-gov-policy-example.git#ref=v1.0.0' \
  --kit-arg org=YOUR_DOCKER_ORG \
  --kit-arg team=YOUR_TEAM \
  --kit-arg docker_username=YOUR_DOCKER_USERNAME
```

The command uses the `v1.0.0` release.

## 3. Ask the agent to apply the policies

> Apply the included AI Governance policies to the configured organization and
> team. Follow the kit's AGENTS.md, back up existing policies, and verify the result.

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
kit arguments or a newer kit revision, create a sandbox with a new name and
configure its secret under that name.

References: [Kits](https://docs.docker.com/ai/sandboxes/customize/),
[Custom secrets](https://docs.docker.com/ai/sandboxes/configuration/credentials/#custom-secrets),
and [AI Governance API](https://docs.docker.com/reference/api/ai-governance/latest/).
