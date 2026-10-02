# Platform resources reference

Everything Urbex creates outside the GitOps repo - on Proxmox, in Gitea,
in Komodo - with its name, what creates it, and what removes it. Useful
for finding your way in the UIs, and for knowing what is safe to touch.

`<org>` is `git.org` from [`urbex.platform.yaml`](platform-config.md)
(default `urbex`); `<gitea>` is Gitea's `<ip>:3000`.

## Proxmox

| Resource | Name | Created by | Removed by |
|---|---|---|---|
| Base-service LXCs | `urbex-gitea`, `urbex-komodo`, `urbex-technitium`, `urbex-keycloak`, `urbex-observability` | `urbex bootstrap` | `urbex teardown` |
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
| `urbex-observability` | Prometheus `:9090`, Loki `:3100`, Grafana `:3000`. |
| each project LXC | Komodo Periphery; `sops` and the compose wrapper in `/opt/urbex/bin/`; the service's container. |

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
| Variables | `URBEX_GITEA_URL`, `URBEX_GITEA_USER`, `URBEX_GITEA_TOKEN` (secret), `URBEX_ORG` | `urbex bootstrap` | `urbex teardown` |
| Server (builder) | `urbex-komodo` | `urbex bootstrap` | `urbex teardown` |
| Action | `urbex-release` | `urbex bootstrap` | `urbex teardown` |
| Procedure | `urbex-gitops` | `urbex bootstrap` | `urbex teardown` |
| Builds | `<project>-<service>` | `urbex apply` | `urbex destroy` of the last environment |
| Servers | `<project>-<service>-<env>` | the LXC's agent, with the onboarding key, during `urbex apply` | `urbex destroy <env>` |
| Stacks | `<project>-<service>-<env>` | `urbex apply <env>` | `urbex destroy <env>` |

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
