# Platform resources reference

Everything Urbex creates outside the GitOps repo - on Proxmox, in Gitea,
in Komodo - with its name, what creates it, and what removes it. Useful
for finding your way in the UIs, and for knowing what is safe to touch.

`<org>` is `git.org` from [`urbex.platform.yaml`](platform-config.md)
(default `urbex`); `<gitea>` is Gitea's `<ip>:3000`.

## Proxmox

| Resource | Name | Created by | Removed by |
|---|---|---|---|
| Base-service LXCs | `urbex-gitea`, `urbex-komodo`, `urbex-technitium`, `urbex-keycloak`, `urbex-observability`, and `urbex-tunnel` with Cloudflare | `urbex bootstrap` | `urbex teardown` |
| Project LXCs | `<project>-<service>-<env>` | `urbex apply <env>` | `urbex destroy <env>` |

All are unprivileged Debian 13 LXCs with `nesting` (and `keyctl`, unless
disabled), on `proxmox.node`, in `proxmox.pool` if set, with the VMIDs
and IPs described in [addresses](platform-config.md#addresses). Docker
runs inside each.

## On the LXCs

| LXC | Runs |
|---|---|
| `urbex-gitea` | Gitea 1.24 (web, git, container registry) on `:3000`, SSH on `:2222`. |
| `urbex-komodo` | Komodo Core on `:9120`, its database (FerretDB on PostgreSQL), and a Periphery agent that is also the **builder** (server `urbex-komodo`). |
| `urbex-technitium` | Technitium DNS, web console on `:5380`. |
| `urbex-keycloak` | Keycloak on `:8080`. |
| `urbex-observability` | Prometheus `:9090` (receiving the agents' metrics by remote write), Loki `:3100`, Grafana `:3000` (admin / `grafanaAdminPassword`), with Loki and Prometheus as data sources and the *Urbex logs* and *Urbex resources* dashboards (folder *Urbex*). |
| `urbex-tunnel` | `cloudflared`, the connector of the platform's Cloudflare Tunnel, with its token in `/opt/urbex/cloudflared.env`. |
| each project LXC | Komodo Periphery; `sops` and the compose wrapper in `/opt/urbex/bin/`; the service's container. |

Every LXC - base and project - also runs the telemetry agent, Grafana
Alloy in `/opt/urbex/telemetry`: its service's logs to Loki and the
LXC's CPU, memory, disk and network to Prometheus, labelled
`kind="platform"` or `kind="app"` ([ADR-0023](../decisions/0023-service-logs-to-loki.md)).

The base services run as Docker Compose projects installed by Ansible;
their data is in Docker volumes on the LXC.

## Gitea

| Resource | Name | Created by | Removed by |
|---|---|---|---|
| Admin user | `urbex-admin` | `urbex bootstrap` | `urbex teardown` |
| API token | `urbex-cli` (of `urbex-admin`) | `urbex bootstrap` | `urbex teardown` |
| Organization | `<org>` | `urbex bootstrap` | `urbex teardown` |
| GitOps repo | `<org>/gitops` | `urbex bootstrap` | `urbex teardown` |
| GitOps webhook | on `<org>/gitops`, branch `main` → the `urbex-gitops` Procedure | `urbex bootstrap` | `urbex teardown` |
| Project repo | `<org>/<project>` | `urbex apply` (if missing) | by hand, or with Gitea by `urbex teardown` |
| Project webhook | on `<org>/<project>`, every push → the `urbex-release` Action | `urbex apply` | `urbex destroy` of the last environment |
| Release tags | `vX.Y.Z` on `<org>/<project>` | `urbex release`, or you | - |
| Images | packages `<project>-<service>`, tags `<short hash>` and `<X.Y.Z>`: `<gitea>/<org>/<project>-<service>:<tag>` | the `urbex-release` Action | - (by hand) |

Images are never deleted automatically: one per commit of `main`. Clean
them up in Gitea under the organization's *Packages* when they pile up.

## Komodo

| Resource | Name | Created by | Removed by |
|---|---|---|---|
| Admin user | `urbex-admin` | `urbex bootstrap` | `urbex teardown` |
| API key | `urbex-cli` | `urbex bootstrap` | `urbex teardown` |
| Onboarding key | `urbex-projects` | `urbex bootstrap` | `urbex teardown` |
| Git account, registry account | `urbex-admin` on `<gitea>`, with the Gitea token | `urbex bootstrap` | `urbex teardown` |
| Variables | `URBEX_GITEA_URL`, `URBEX_GITEA_USER`, `URBEX_GITEA_TOKEN` (secret), `URBEX_ORG`; with Cloudflare `URBEX_CLOUDFLARE_TOKEN` (secret), `URBEX_CLOUDFLARE_ACCOUNT_ID` | `urbex bootstrap` | `urbex teardown` |
| Server (builder) | `urbex-komodo` | `urbex bootstrap` | `urbex teardown` |
| Servers of the base services | `urbex-gitea`, `urbex-technitium`, `urbex-keycloak`, `urbex-observability`, `urbex-tunnel`: Periphery in `/opt/urbex/periphery` on their LXCs, for monitoring their containers | `urbex bootstrap` | `urbex teardown` |
| Tags | `platform`, `app`, each project's name, `staging`, `prod` | `urbex bootstrap`, `urbex apply` | - |
| Action | `urbex-release` | `urbex bootstrap` | `urbex teardown` |
| Procedure | `urbex-gitops` | `urbex bootstrap` | `urbex teardown` |
| Builds | `<project>-<service>` | `urbex apply` | `urbex destroy` of the last environment |
| Servers | `<project>-<service>-<env>` | the LXC's agent, with the onboarding key, during `urbex apply` | `urbex destroy <env>` |
| Stacks | `<project>-<service>-<env>`; a web frontend's `<project>-web-<env>` runs on the builder | `urbex apply <env>` | `urbex destroy <env>` |

### Tags

Komodo's resources are tagged like the logs and metrics in Grafana
([ADR-0023](../decisions/0023-service-logs-to-loki.md)), so Komodo's
lists filter the same way:

| Resources | Tags |
|---|---|
| The base services' Servers, the builder, `urbex-release`, `urbex-gitops` | `platform` |
| A project's Builds | `app`, `<project>` |
| A project environment's Servers and Stacks (web frontend included) | `app`, `<project>`, `<env>` |

Urbex sets them on every `bootstrap` and `apply`, replacing the
resource's tags.

### `urbex-release` (Action)

A TypeScript script, called by every project repo's webhook. For a push
to:

- **`main`** - runs the project's Builds at the pushed commit (images
  tagged with its short hash), then sets `VERSION` to that hash in every
  `version.env` of the project with `TRACK=main`, in one commit to the
  GitOps repo, and runs `urbex-gitops`.
- **a `vX.Y.Z` tag** - for each service, copies the image of the tagged
  commit to the tag `X.Y.Z` in the registry; if `main` never built that
  commit, builds it first.
- **anything else** - does nothing.

Runs can overlap - the webhook of a push and `urbex apply`, or pushes
in quick succession - so a run waits for a busy Build, never builds a
commit whose image already exists, and only moves environments to
`main`'s current head: a slow build of an older push can't undo a newer
one. A tag pushed with git resolves to the commit it points to, annotated
or not.

It reads Gitea's address and token from the `URBEX_*` variables.
`urbex release` and `urbex apply` also run it directly. Its source is
`platform/komodo/release.ts` in `urbex-cli`.

### `urbex-gitops` (Procedure)

One stage: *deploy if changed* on every Stack. Runs on every push to the
GitOps repo's `main` (webhook) and every 15 minutes (schedule
`0 */15 * * * *`).

### Builds

Builder `urbex-komodo`, repo `<org>/<project>` branch `main`, image
`<project>-<service>` in `<gitea>/<org>`, tagged with the commit hash
only (no `latest`, no auto-incremented version), build arg
`SERVICE=<service>`. For the `go`, `java` and `python` runtimes a pre-build
step writes Urbex's Dockerfile next to the sources; for `docker`, the
build uses the project's. See [runtimes](manifest.md#runtimes).

### Stacks

Server `<project>-<service>-<env>`; repo `<org>/gitops` branch `main`;
run directory `environments/<env>/<project>/<service>`; `version.env` as
an env file and `config.env`, `secrets.sops.env` as config files - a
change to any of the three, or to `compose.yaml`, redeploys the Stack.
Compose runs through `/opt/urbex/bin/urbex-compose`, which decrypts the
secrets. Nothing in a Stack's definition depends on what it deploys:
after `apply`, everything is a commit.

## Technitium

Unlike Cloudflare, these exist regardless of `cloudflare.accountId`/
`zoneId` - Technitium is part of the base platform
([ADR-0007](../decisions/0007-technitium-configurable-domain.md)). See
[ADR-0026](../decisions/0026-technitium-internal-dns-records.md) and
[ADR-0027](../decisions/0027-service-conventions.md).

| Resource | Name | Created by | Removed by |
|---|---|---|---|
| Admin API token | `urbex-cli` (of Technitium's admin user) | `urbex bootstrap` | `urbex teardown` (the LXC itself) |
| Zone (Primary) | `dns.zone`, by default `<cloudflare.name>.<domain>` (a zone named after `domain`, from an older urbex, is moved and deleted) | `urbex bootstrap` | `urbex teardown` (the LXC itself) |
| Forwarders (server setting) | `dns.forwarders`, by default `proxmox.network.dnsServers` or the gateway | `urbex bootstrap` | `urbex teardown` (the LXC itself) |
| A records, platform | `git`, `komodo`, `hooks`, `auth`, `dns`, `grafana`, `prometheus`, `loki`, `tunnel` (with Cloudflare) under the zone | `urbex bootstrap` | `urbex teardown` (the LXC itself) |
| A records, projects | `<service>.<env>.<project>.<zone>`, `<service>.<project>.<zone>` in prod - every declared service, whether or not it's `public: true` | `urbex apply <env>` | `urbex destroy <env>` only - removing a service from `urbex.yaml` leaves its record behind, like its LXC and Stack (see [known limitations](../known-limitations.md#projects-and-deploys)) |

## Cloudflare

Only with Cloudflare configured ([ADR-0022](../decisions/0022-cloudflare-tunnel-access-workers.md)).
Everything is named with the platform's `cloudflare.name` (`urbex`
below); DNS records carry the comment `managed by urbex`. Nothing else
on the account is ever changed: a DNS record of the same name that urbex
didn't create makes it stop instead.

| Resource | Name | Created by | Removed by |
|---|---|---|---|
| Tunnel (remotely managed) | `urbex-platform` | `urbex bootstrap` | `urbex teardown` |
| Tunnel routes, DNS CNAMEs | `auth-`, `git-`, `komodo-`, `hooks-`, `dns-`, `grafana-`, `prometheus-`, `loki-urbex.<domain>` (Prometheus' remote write and Loki's push paths answer 404) | `urbex bootstrap` | `urbex teardown` |
| Access login method | One-time PIN (if the organization had none) | `urbex bootstrap` | - |
| Access policy | `urbex-operators`: the `cloudflare.access.emails` | `urbex bootstrap` | `urbex teardown` |
| Access applications | `urbex-git`, `urbex-komodo`, `urbex-dns`, `urbex-grafana`, `urbex-prometheus`, `urbex-loki`, `urbex-auth-admin` (`/admin` of Keycloak's hostname), `urbex-auth-master` (`/realms/master`) | `urbex bootstrap` | `urbex teardown` |
| Tunnel routes, DNS CNAMEs of public services | `<service>[-staging]-<project>-urbex.<domain>` | `urbex apply <env>` | `urbex destroy <env>`, or `apply` once not public |
| Workers, custom domains | `urbex-<project>-web-<env>` at `[staging-]<project>-urbex.<domain>` | the web Stack (`apply`, deploys) | `urbex destroy <env>` |

Access is always set up before anything is routed: if it can't be,
nothing is published.

## What is safe to change by hand

- **Yes:** anything under `environments/` in the GitOps repo; tags and
  branches on project repos; old images in Gitea; Komodo's UI for
  looking, running the Procedure, or redeploying a Stack.
- **Overwritten by the next `bootstrap` or `apply`:** the Action, the
  Procedure, Builds, Stacks, the `URBEX_*` variables. Change them in the
  CLI instead.
- **No:** deleting the `urbex-admin` users, the `urbex-cli` token or API
  key, or the onboarding key - the CLI and Komodo depend on them, and
  bootstrap only creates them when the credentials file has none.
