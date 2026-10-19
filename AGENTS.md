# Applying AI Governance policies from this sandbox

Read `README.md` and the payloads under `/opt/aig-policies` before deploying.
Write credential-free backups to a new directory under the sandbox user's home.

## Target and API

- Require `AIG_ORG` to explicitly select the target organization. Use `AIG_TEAM`, defaulting to `aig-demo-team`. “AIG” means AI Governance, not an organization slug. Never infer the organization from the Docker username.
- A request to apply the policies authorizes deployment; do not ask again for routine confirmation. Launching the kit alone does not authorize deployment.
- API base: `https://hub.docker.com/v2`.
- Reference: https://docs.docker.com/reference/api/ai-governance/latest/
- OpenAPI: https://docs.docker.com/reference/api/ai-governance/api.yaml

## Authentication inside the sandbox

Read `AIG_DOCKER_USERNAME` and `AIG_DOCKER_TOKEN` from the environment and build
requests in memory. The token variable can be a custom-secret placeholder; the
host proxy replaces it in requests to `hub.docker.com`. Never print credentials,
pass the PAT in command arguments, commit secrets, or ask for secrets in chat.

Exchange the credential with `POST https://hub.docker.com/v2/auth/token`, setting
`Content-Type: application/json`. Build the JSON fields `identifier` and `secret`
from the actual environment values of `AIG_DOCKER_USERNAME` and `AIG_DOCKER_TOKEN`;
do not send their variable names literally. Do not use `/auth/token` at the host
root, the legacy `/users/login` endpoint, or `username`/`password` JSON fields.
Require a successful response containing a nonempty `access_token` before any
governance request. Use that returned JWT as
`Authorization: Bearer <token>` and refresh it on expiry. Never log token request
or response bodies. Do not use the PAT directly as a bearer token or configure
PAT header injection that would overwrite the JWT. If using an OAT, follow the
token endpoint's organization identifier requirements:
https://docs.docker.com/reference/api/hub/latest/operations/AuthCreateAccessToken/

First perform an authenticated
`GET https://hub.docker.com/v2/orgs/{AIG_ORG}/governance/policies`.
If credentials are missing or authentication fails, report the precise blocker
and refer to the host credential setup in README.md. Do not assume Docker Desktop
or GitHub authentication grants governance access. Read structured network errors:
refer pending approvals to the host approval flow and organization policy blocks
to the customer's administrator. Never bypass sandbox network controls.

For a 401, report the exact request method, full URL, and status, without headers
or token response bodies. A token-exchange 401 means no JWT was obtained; do not
diagnose it as a governance scope failure. Check that both credential variables
are set (report presence only), the username owns the PAT, and the custom secret
is configured for this sandbox and `hub.docker.com`. A placeholder is expected;
do not reject it for lacking a `dckr_pat_` prefix. If a secret was added after
creation, use the documented placeholder setup for an existing sandbox. Ask for
the host's `sbx version` if injection behavior remains in doubt. A governance 401
after a successful exchange calls for a fresh JWT and a check that the request
uses it rather than the PAT or placeholder.

## Deployment procedure

1. Validate all JSON payloads. List existing policies, following `next_page_token` pagination, and fetch their full contents before changing anything. Save a local backup of affected policies without credentials.
2. Resolve the actual ID of the existing selected team (`AIG_TEAM`, default `aig-demo-team`) in the target organization through `GET /orgs/{org_name}/groups` (the Docker Hub teams API), following pagination. Use the returned `uuid`, not the numeric `id`, for governance scope. Confirm the team belongs to this organization. Set the team policy name to `<selected-team> Network Restrictions`. Substitute that UUID for `AIG_DEMO_TEAM_ID` in the submitted payload, leaving the packaged source unchanged. Never submit the placeholder, use the team name as its ID, or silently fall back to organization scope. If the team is missing, report that blocker.
3. Apply these four policies, preserving their scopes:

   | Policy payload | Rule payload | Scope |
   | --- | --- | --- |
   | `policies/org-network-policy.json` | `policies/org-network-rules.json` (41 rules) | Organization |
   | `policies/org-filesystem-policy.json` | `policies/org-filesystem-rules.json` (4 rules) | Organization |
   | `policies/aig-demo-team-network-policy.json` | `policies/aig-demo-team-network-rules.json` (4 rules) | Selected team only (default `aig-demo-team`) |
   | `policies/notion-policy.json` | Cedar text embedded in payload | Organization |

   Empty `scope.teams` means organization scope. Scope belongs to the policy, not an individual rule.

4. Reuse an unambiguously matching existing policy rather than creating duplicates. Compare its scope and full rule contents. Use the documented PATCH endpoints for updates. Preserve unrelated policies and rules; resolve ambiguous matches before editing.
5. For a new policy, POST its creation payload to `/orgs/{org_name}/governance/policies`. For each non-Cedar policy, use the returned policy ID and POST each rule object separately to `/orgs/{org_name}/governance/policies/{policy_id}/rules`. The Notion policy already contains its Cedar statements and requires no rule POSTs. Keep network and filesystem rules in separate policies.
6. When migrating a previous deployment of this kit, install and verify the team-scoped restrictions before removing their equivalent organization-scoped copies. Do not leave those four restrictions enforced organization-wide. Remove only copies confirmed to belong to the superseded kit deployment; do not delete unrelated policies.
7. Check every response. Record successful policy and rule IDs as work proceeds. If a request fails, inspect current server state before retrying a POST to avoid duplicates. Report partial deployment accurately; never claim that failed operations succeeded.

## Verification and reporting

- Fetch each resulting policy by ID and compare scope, rule contents and counts, or Cedar text/schema URL against the local payloads. Compare semantic fields rather than generated IDs and timestamps.
- Confirm the four team restrictions are scoped to the resolved team and were not accidentally deployed organization-wide.
- Report the target organization, policy IDs, scopes, verified counts, and any remaining failures. Do not claim successful runtime enforcement based only on API acceptance.
- Policy changes can take up to five minutes to propagate to developer machines.
- Filesystem policies authorize workspace mounts at sandbox creation. Existing sandboxes must be recreated to apply mount changes; do not recreate them without a user request. These rules do not prevent access to `.env` files within an allowed mounted workspace.
