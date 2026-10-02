# ADR-0022: Public endpoints on Cloudflare - Tunnel, Access, Workers

## Status

Proposed. Implements [ADR-0005](0005-cloudflare-tunnel-ingress.md)
(ingress through Cloudflare Tunnel) and replaces its "one `cloudflared`
per LXC/project/environment"; refines the hostname scheme of
[ADR-0007](0007-technitium-configurable-domain.md); replaces Cloudflare
Pages with Workers static assets for web frontends.

## Context

Everything Urbex runs is reachable only on the LAN today. Three things
need a public HTTPS address:

1. **Platform services**: Keycloak, for the apps' users to log in;
   Gitea and Komodo, for the operator from anywhere; Komodo's webhook
   listener, for git providers outside the LAN (GitHub, later).
2. **Project APIs**, per environment.
3. **Web frontends**, per environment.

Constraints found on the test zone (`cubotto.net`):

- On Cloudflare's Free plan, the edge certificate (Universal SSL) covers
  the apex and **one** level of subdomain (`*.cubotto.net`). Two levels
  (`auth.urbex.cubotto.net`) need Advanced Certificate Manager (ACM, paid).
- The account already holds unrelated tunnels and Workers: Urbex must
  only ever touch what it created.
- Cloudflare is folding Pages into Workers: a Worker with static assets
  is the current way to serve a frontend, with versions and gradual
  deployments.

## Decision

### Hostnames

Hostnames are built from labels, most specific first, ending with the
platform's name (`cloudflare.name`, default `urbex`), under the zone's
domain (`domain`). The platform config picks how they are joined
(`cloudflare.hostnames`):

| | `flat` (default, any plan) | `nested` (needs ACM) |
|---|---|---|
| Keycloak | `auth-urbex.cubotto.net` | `auth.urbex.cubotto.net` |
| Gitea | `git-urbex.cubotto.net` | `git.urbex.cubotto.net` |
| Komodo | `komodo-urbex.cubotto.net` | `komodo.urbex.cubotto.net` |
| Webhooks | `hooks-urbex.cubotto.net` | `hooks.urbex.cubotto.net` |
| Web, prod | `hello-urbex.cubotto.net` | `hello.urbex.cubotto.net` |
| Web, staging | `staging-hello-urbex.cubotto.net` | `staging.hello.urbex.cubotto.net` |
| API `api`, prod | `api-hello-urbex.cubotto.net` | `api.hello.urbex.cubotto.net` |
| API `api`, staging | `api-staging-hello-urbex.cubotto.net` | `api.staging.hello.urbex.cubotto.net` |

With `nested`, Urbex orders an ACM certificate for the wildcards it uses
(`*.urbex.<domain>`, `*.<project>.urbex.<domain>`, ...); ACM itself is
enabled on the zone by the operator.

### One tunnel for the platform

- One remotely-managed Cloudflare Tunnel, `urbex-<name>`, created by
  `urbex bootstrap`; its ingress rules are kept by Urbex through the API
  (no config file on disk), its DNS records are CNAMEs to it.
- `cloudflared` runs as a container on a sixth, small base-service LXC,
  `urbex-tunnel`: ingress keeps working when any other service is
  restarted, and the token it runs with lives on that LXC only.
- `urbex apply <env>` adds the project environment's routes, `urbex
  destroy <env>` removes them, `urbex teardown` deletes the tunnel and
  its records.

### What is exposed, and how

| Service | Behind Access | Notes |
|---|---|---|
| Keycloak | no | Its own login is the gate; configured with its public hostname and to trust the tunnel's forwarded headers. |
| Gitea | yes | Browser use. `git` over HTTPS keeps using the LAN address (Access doesn't fit a git client). |
| Komodo | yes | Browser use; the CLI keeps using the LAN address. |
| Webhooks | no | Only Komodo's `/listener/` paths; every call is signed with the webhook secret. |
| Project APIs | no | The app's own auth (Keycloak) is the gate. A service opts in with `public: true` in `urbex.yaml`. |
| Web frontends | no | Static assets on Cloudflare's edge. |

Access: one application per protected hostname, allowing the e-mail
addresses in `cloudflare.access.emails`, logging in with Cloudflare's
one-time PIN (no identity provider to set up); Keycloak can become the
identity provider later.

### Web frontends: Workers with static assets

- `frontend.type: web` deploys to a Worker per environment,
  `urbex-<project>-web-<env>`, serving the build output as static
  assets, on the environment's hostname as a custom domain.
- Builds follow the services' trunk model: every push to `main` builds
  the frontend once (Komodo, in a Node container on the builder), and
  the result is uploaded as a Worker **version** tagged with the commit,
  without deploying it.
- Deploying an environment is making a version current, driven by the
  same `version.env` in the GitOps repo: staging follows `main`,
  promoting to prod deploys the version tagged with the release. A
  rollback is deploying an older version: nothing is rebuilt.
- `provider: cloudflare-pages` in the manifest is kept as an alias
  meaning "Workers static assets".

### Credentials

The Cloudflare API token and account ID are credentials
(`URBEX_CLOUDFLARE_TOKEN`, `URBEX_CLOUDFLARE_ACCOUNT_ID`). The token
needs, on the account: Cloudflare Tunnel, Workers Scripts, Access: Apps
and Policies (all Edit); on the zone: DNS and Workers Routes (Edit), Zone
(Read). The tunnel's own connector token is fetched by bootstrap and
handed to `urbex-tunnel` by Ansible, never written to the GitOps repo.
Komodo gets a Cloudflare token for uploading Worker versions as a secret
variable.

## Rationale

- One tunnel and one connector is the least to run and to secure; routes
  are data, changed through the API like everything else.
- Flat names cost nothing and work on every plan; nested names are
  nicer, so they are one setting away for zones with ACM.
- Access in front of the two admin UIs without running an identity
  provider: one-time PIN is enough for a handful of operators.
- Worker versions give frontends the same build-once, promote-the-same-
  bytes model the services have.

## Consequences

- A sixth base-service LXC (`urbex-tunnel`, 1 core, 256 MiB).
- Every Cloudflare object Urbex creates is named `urbex-...` and tagged
  where the API allows; nothing else on the account is touched.
- Gitea and Komodo keep being used from the LAN by the CLI and git;
  their public hostnames are for browsers.
- Keycloak, Gitea and Komodo are configured with their public URLs,
  which changes the links they generate.
