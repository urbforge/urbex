# CLI reference

Every `urbex` command: what it does, step by step, what it needs, and its
flags. For walkthroughs see [getting started](../getting-started.md) and
the [cookbook](../cookbook.md).

- [Conventions](#conventions)
- [`urbex init`](#urbex-init)
- [`urbex bootstrap`](#urbex-bootstrap)
- [`urbex plan`](#urbex-plan)
- [`urbex apply`](#urbex-apply)
- [`urbex release`](#urbex-release)
- [`urbex deploy`](#urbex-deploy)
- [`urbex promote`](#urbex-promote)
- [`urbex secret`](#urbex-secret)
- [`urbex status`](#urbex-status)
- [`urbex destroy`](#urbex-destroy)
- [`urbex teardown`](#urbex-teardown)
- [Environment variables](#environment-variables)
- [Exit status and output](#exit-status-and-output)

## Conventions

- **`<env>`** is `staging` or `prod`. They are the only environments in
  v1.
- **Project commands** (`plan`, `apply`, `release`, `deploy`, `promote`,
  `secret`, `status <env>`, `destroy`) act on the project whose
  `urbex.yaml` is in the current directory (`--file` to point elsewhere),
  and on the GitOps repo working copy given by `--gitops-repo` or
  `URBEX_GITOPS_REPO`.
- **A version** is either a release (`1.4.2`, from the tag `v1.4.2`) or
  a commit of `main`, as its short hash (`a1b2c3d`) - the tag of the image
  built for that commit.
- **Credentials** come from environment variables, falling back to
  `~/.urbex/credentials.yaml`; see [credentials](credentials.md).
- Commands that change the GitOps repo first pull it from Gitea
  (rebasing local commits), then commit and push. Its working copy may
  have uncommitted changes; they are kept.

Shared flags:

| Flag | Default | Meaning |
|---|---|---|
| `--gitops-repo <dir>` | `$URBEX_GITOPS_REPO` | Local working copy of the GitOps repo. Required by every command but `init`. |
| `--file <path>` | `urbex.yaml` | The project's manifest. |

---

## `urbex init`

```
urbex init [--file urbex.yaml] [--project <name>]
```

Creates a starter manifest if `--file` doesn't exist (project name from
`--project`, else the current directory's name); otherwise validates it
against the [manifest schema](manifest.md) and lists every error. Touches
nothing else and needs no credentials.

```sh
urbex init --project acme-app   # Created urbex.yaml for project "acme-app".
urbex init                      # urbex.yaml is valid.
```

## `urbex bootstrap`

```
urbex bootstrap [--gitops-repo <dir>] [--dry-run]
```

Creates the platform: the base-service LXCs, and Gitea and Komodo wired
together. Run it once per platform; running it again is safe and is how
the base services are updated.

1. If `<dir>/urbex.platform.yaml` doesn't exist, writes a starter one and
   stops: edit it ([reference](platform-config.md)) and run again.
2. Validates the platform config, the credentials (`URBEX_PROXMOX_TOKEN`,
   `URBEX_AGE_KEY`), and that the age key is well-formed.
3. Lists the node's containers. If an `urbex-*` base-service container
   exists that this GitOps repo's Terraform state doesn't know about, it
   stops rather than adopt or duplicate it.
4. Writes the embedded Terraform and Ansible files into the GitOps repo,
   allocates the base services' IPs (`baseHostOffset` to `+4`), generates
   any missing platform secret into `~/.urbex/credentials.yaml`.
5. `terraform init` and `terraform apply` in `terraform/base/`, then
   `ansible-playbook` with `ansible/playbook.yml`: Docker on every LXC,
   then Gitea, Komodo (Core, database, Periphery), Technitium, Keycloak,
   Prometheus/Loki/Grafana.
6. Platform setup: a Gitea token, the org and its `gitops` repo; a Komodo
   API key, the onboarding key, Komodo's Gitea git and registry accounts,
   the `URBEX_*` Komodo variables, the `urbex-release` Action, the
   `urbex-gitops` Procedure; `.sops.yaml`; commits and pushes the GitOps
   repo, and adds its webhook. Tokens and keys already in the credentials
   file are reused, not rotated.

| Flag | Meaning |
|---|---|
| `--dry-run` | Do steps 1-4 (files only, no secrets generated) and stop before Terraform. |

Needs: `URBEX_PROXMOX_TOKEN`, `URBEX_AGE_KEY`, `terraform`,
`ansible-playbook`, `git`, and an SSH agent with the key in
`proxmox.sshPublicKey`. Everything it creates is listed in
[platform resources](platform-resources.md).

## `urbex plan`

```
urbex plan <env> [--file urbex.yaml] [--gitops-repo <dir>]
```

Shows what `apply` would change in the infrastructure, without changing
it: updates the GitOps repo from Gitea, allocates (and records) a VMID and IP for each service's LXC in
`<env>` if it has none, writes the project's Terraform files under
`terraform/projects/<project>/<env>/`, and runs `terraform plan`.

Before any Terraform command, `plan`, `apply`, and `destroy` drop from
the Terraform state the LXCs that no longer exist on Proxmox (deleted by
hand, say), printing `LXC <vmid> is gone from Proxmox: forgetting ...`.
Terraform would find out by itself with an unrestricted token, but a
token scoped to a resource pool gets `403 Permission check failed` for a
VMID outside the pool - which a deleted LXC is.

Needs: `URBEX_PROXMOX_TOKEN`, `URBEX_AGE_KEY`, `terraform`.

## `urbex apply`

```
urbex apply <env> [--file urbex.yaml] [--gitops-repo <dir>] [--repo-dir .]
```

Creates or updates an environment of the project - its infrastructure,
the project's build setup, and the environment's deploy setup - and, if
there is something to run, waits until it runs.

1. Everything `plan` does, then `terraform apply`: one LXC per service.
2. `ansible-playbook` with `ansible/project-playbook.yml`: Docker, the
   Komodo Periphery agent (registered under the LXC's hostname), `sops`
   and the compose wrapper that decrypts secrets.
3. **The project:** its repo on Gitea (if Gitea has no `main`, pushes
   `--repo-dir`'s `HEAD` there), a Komodo Build per service, and the
   project repo's webhook to the `urbex-release` Action.
4. **The environment:** waits for the LXCs' agents to connect to Komodo
   (accepting the new key of a recreated LXC), writes each service's
   folder in the GitOps repo, declares its Komodo Stack, commits and
   pushes.
5. **What to run:**
   - a new **staging** follows `main`: `apply` builds `main`'s head and
     waits until staging runs it;
   - a new **prod** stays empty until `urbex promote` or `urbex deploy
     prod`;
   - an environment that already runs something is redeployed (e.g. onto
     a recreated LXC) and waited for.

| Flag | Default | Meaning |
|---|---|---|
| `--repo-dir <dir>` | `.` | The project's local repo, used only if Gitea has no `main` yet. |

Needs: `URBEX_PROXMOX_TOKEN`, `URBEX_AGE_KEY`, the platform credentials
from bootstrap, `terraform`, `ansible-playbook`, `git`, the SSH agent.

```
Deployed acme-app (staging):
  api              http://192.168.1.210:8080  3f9c2e1 (192.168.1.200:3000/urbex/acme-app-api:3f9c2e1)
staging follows main: every push to main is deployed here.
```

Re-run it after adding a service or changing `resources`. Changes to a
port or healthcheck only need [`deploy`](#urbex-deploy).

## `urbex release`

```
urbex release [--version vX.Y.Z] [--ref <commit|branch|tag>] [--file urbex.yaml] [--gitops-repo <dir>]
```

Makes a release: tags a commit of the project as `vX.Y.Z` on Gitea and
waits until every service has an image `X.Y.Z` in the registry.

- **Version:** `--version`, or the patch after the highest existing
  `vX.Y.Z` tag (`v0.1.0` for the first). An existing version is refused.
- **Commit:** `--ref`; else, if staging follows `main`, **the commit
  staging runs**; else `main`'s head.
- **Images:** the tag triggers the `urbex-release` Action, which copies
  the commit's existing image (built when it was pushed to `main`) to the
  new tag - no rebuild. A commit `main` never built is built first.

A release deploys nothing. Pushing a `vX.Y.Z` tag with `git` is exactly
equivalent.

```
Releasing acme-app v0.4.0 from the commit staging runs (8d41b07).
Tagged v0.4.0 on 8d41b07; Komodo is publishing its images...
Released acme-app 0.4.0:
  api              192.168.1.200:3000/urbex/acme-app-api:0.4.0
Put it in production with 'urbex promote' (or 'urbex deploy prod').
```

Needs: the platform credentials.

## `urbex deploy`

```
urbex deploy <env> [--version <version> | --follow-main] [--file urbex.yaml] [--gitops-repo <dir>]
```

Sets what an environment runs, by writing each service's
`version.env` in the GitOps repo and pushing; Komodo deploys from there,
and `deploy` waits until the environment runs it.

| Form | Effect |
|---|---|
| `urbex deploy <env>` | The project's latest release. |
| `urbex deploy <env> --version 1.4.2` | That release. How to roll back. |
| `urbex deploy <env> --version 8d41b07` | The image of that commit of `main`. |
| `urbex deploy <env> --follow-main` | Follow `main`: build its head now, and deploy every later push. |

Deploying a version removes `TRACK=main`, so an environment that
followed `main` stays on that version (`deploy` says so);
`--follow-main` adds it back.

Before writing anything, `deploy` checks that every service has an image
for the version, and refuses otherwise. It also regenerates each
service's `compose.yaml` from `urbex.yaml`: this is how a changed port or
healthcheck takes effect.

If the environment hasn't moved after a few seconds - Komodo can miss a
push that follows another closely - `deploy` asks Komodo to reconcile.

Needs: the platform credentials. No Terraform, no SSH.

## `urbex promote`

```
urbex promote [--file urbex.yaml] [--gitops-repo <dir>]
```

Sets production to the release staging runs, and waits until it runs.

- Staging runs a release: prod gets that release.
- Staging runs a commit of `main`: prod gets the release tagged on that
  commit (the highest, if several). If there is none, `promote` refuses -
  `urbex release` first.

Prod is pinned to the release (no `TRACK=main`). Nothing is rebuilt: the
image is the one staging runs. Prints `Nothing to promote` when prod
already runs it. Configuration and secrets are not copied: they are per
environment.

Needs: both environments applied; the platform credentials.

## `urbex secret`

```
printf %s "$VALUE" | urbex secret set <env> <service> <KEY>
urbex secret unset <env> <service> <KEY>
urbex secret list <env> <service>
```

Manages a service's secrets in one environment: environment variables
kept in `environments/<env>/<project>/<service>/secrets.sops.env`,
encrypted with SOPS for the platform's age key, decrypted only on the
LXC when Komodo deploys.

- `set` reads the value from standard input (all of it, minus one
  trailing newline), adds or replaces `KEY`, commits, pushes, and asks
  Komodo to reconcile: the service is redeployed with it.
- `unset` removes `KEY` the same way.
- `list` prints the names, one per line. Names aren't encrypted: it needs
  neither `sops` nor the key, and never prints values.

`KEY` must be a valid environment variable name (letters, digits,
underscores, not starting with a digit, not `sops_...`).

Needs: `sops` and `URBEX_AGE_KEY` (`set`, `unset`), the platform
credentials.

## `urbex status`

```
urbex status [<env>] [--file urbex.yaml] [--gitops-repo <dir>]
```

Without `<env>`: which base-service LXCs exist on Proxmox.

```
Base services:
  urbex-gitea              present
  urbex-komodo             present
  ...
```

With `<env>`, for each service of the project:

```
acme-app (staging):
  api   acme-app-api-staging   allocated=yes provisioned=yes version=8d41b07(follows-main) stack=running image=192.168.1.200:3000/urbex/acme-app-api:8d41b07
```

| Field | Source |
|---|---|
| `allocated` | The service has a VMID/IP in `state/allocations.json`. |
| `provisioned` | Its LXC exists on Proxmox right now. |
| `version` | Its `version.env` in the GitOps repo; `(follows-main)` if it has `TRACK=main`; `none` if unset. |
| `stack`, `image` | What Komodo reports: the Stack's state and the image it runs. |

Needs: `URBEX_PROXMOX_TOKEN`; the platform credentials for the Komodo
columns.

## `urbex destroy`

```
urbex destroy <env> [--file urbex.yaml] [--gitops-repo <dir>]
```

Removes an environment of the project, in this order:

1. Updates the GitOps repo from Gitea.
2. Takes its Komodo Stacks down (`docker compose down`) and deletes them:
   from here on nothing deploys the environment.
3. `terraform destroy` for the services' LXCs (and their disks).
4. Deletes their Komodo Servers.
5. If the project has no environment left: deletes the project repo's
   webhook, waits for any build still running (a push just before), and
   deletes its Komodo Builds.
6. Updates the GitOps repo again and removes, in one commit:
   `environments/<env>/<project>/`, the environment's Terraform files and
   (now empty) state under `terraform/projects/<project>/<env>/`, its
   Ansible inventory under `ansible/projects/<project>/<env>/`, and its
   entries in the allocation ledger.

The folder goes last on purpose: until the Stacks are gone, a push to
`main` can still make the release Action update it, and removing it
earlier would conflict with that commit.

`destroy` can be run again after a failure: it resumes where it
stopped. An LXC already gone from Proxmox is dropped from Terraform's
state rather than failing (see [`plan`](#urbex-plan)).

The project's repo and images stay on Gitea. Services that were never
applied are skipped; if none were, nothing happens. Base services are
never touched.

Needs: `URBEX_PROXMOX_TOKEN`, `URBEX_AGE_KEY`, the platform credentials,
`terraform`.

## `urbex teardown`

```
urbex teardown [--gitops-repo <dir>] [--yes]
```

Destroys the platform `urbex bootstrap` created: the inverse of
`bootstrap`.

1. Updates the GitOps repo from Gitea (if it still answers).
2. Refuses while any project environment exists - a folder under
   `environments/` or an LXC in the allocation ledger - naming them: run
   `urbex destroy <env>` in each project first.
3. Says what it destroys and what is lost: the base-service LXCs and
   their disks, so **every repository and image on Gitea** (project repos
   included - make sure they also live elsewhere), Komodo's, Keycloak's
   and Grafana's data, the generated credentials. Without `--yes` it
   stops here.
4. `terraform destroy` in `terraform/base/` (LXCs already gone are
   dropped from the state first).
5. Removes the credentials bootstrap generated from
   `~/.urbex/credentials.yaml`; the ones you provide (Proxmox token, age
   key, Cloudflare token) stay.
6. Commits the GitOps repo locally. Its working copy is now the **only
   copy**: keep it. `urbex bootstrap` creates a new platform from it and
   pushes it to the new Gitea.

| Flag | Meaning |
|---|---|
| `--yes` | Confirm. Without it, nothing is destroyed. |

Needs: `URBEX_PROXMOX_TOKEN`, `URBEX_AGE_KEY`, `terraform`. The Proxmox
resource pool, its storages and the token are left as they are.

## Environment variables

| Variable | Used by |
|---|---|
| `URBEX_GITOPS_REPO` | Every command but `init`: the GitOps repo working copy, if `--gitops-repo` isn't given. |
| `URBEX_PROXMOX_TOKEN` | `bootstrap`, `plan`, `apply`, `destroy`, `teardown`, `status`. |
| `URBEX_AGE_KEY` | `bootstrap`, `plan`, `apply`, `destroy`, `teardown`, `secret set/unset`. |
| `URBEX_GITEA_TOKEN`, `URBEX_KOMODO_*`, ... | Generated by bootstrap into `~/.urbex/credentials.yaml`; an environment variable overrides the file. |

The full list, and how to obtain each, is in [credentials](credentials.md).

## Exit status and output

Every command exits 0 on success and non-zero with a one-line error on
standard error otherwise; the error says what to do when there is
something to do (`run 'urbex apply staging' first`, `release it first`).
Commands that run Terraform or Ansible stream their output. Nothing is
interactive: every command can run in a script or an agent session.
