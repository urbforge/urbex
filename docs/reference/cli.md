# CLI reference

Every `urbex` command: what it does, step by step, what it needs, and its
flags. For walkthroughs see [getting started](../getting-started.md) and
the [cookbook](../cookbook.md).

- [Conventions](#conventions)
- [`urbex doctor`](#urbex-doctor)
- [`urbex discover`](#urbex-discover)
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
- [`urbex users`](#urbex-users)
- [Environment variables](#environment-variables)
- [Exit status and output](#exit-status-and-output)

## Conventions

- **`<env>`** is `staging` or `prod`. They are the only environments in
  v1. A stack declared with `environments: [prod]` has production only,
  and the commands refuse `staging` for it.
- **Project commands** (`plan`, `apply`, `release`, `deploy`, `promote`,
  `secret`, `status <env>`, `destroy`) act on the project whose
  `urbex.yaml` is in the current directory (`--file` to point elsewhere),
  and on the GitOps repo working copy given by `--gitops-repo` or
  `URBEX_GITOPS_REPO`.
- **Addresses**: from your machine the CLI reaches the platform at the
  LAN addresses it computes from `urbex.platform.yaml`; the services
  reach each other by internal name. Project commands first ask
  Technitium for the platform services' names: if one points elsewhere
  (an LXC recreated on another address, a config that no longer
  matches), they stop with both addresses; if Technitium doesn't answer,
  or a name has no record yet, they warn and go on
  ([ADR-0027](../decisions/0027-service-conventions.md)).
- **A version** is either a release (`1.4.2`, from the tag `v1.4.2`) or
  a commit of `main`, as its short hash (`a1b2c3d`) - the tag of the image
  built for that commit. For an application from a published image, the
  version is a tag of that image together with the digest it was
  resolved to (`17.6@sha256:...`).
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

## `urbex doctor`

```
urbex doctor [--gitops-repo <dir>] [--output text|json]
```

Checks that this machine, the workspace, Proxmox and Cloudflare have
what urbex needs, and says what to do about what's missing. It changes
nothing and prints no secret; run it first, and whenever something
fails for no clear reason.

- **tools**: `git`, `ssh`, `terraform`, `ansible-playbook`, `sops`, `age`,
  with their versions. `urbex-op`'s image has them all.
- **workspace**: the credentials file, the Proxmox token and age key, an
  SSH key (an agent, or `~/.ssh/urbex`), the GitOps repo and its
  `urbex.platform.yaml`, validated.
- **proxmox**, with a valid platform config and a token: the API answers
  with the token, the node, the pool, the token's privileges (on the
  pool, the storage and the bridge, as in
  [credentials](credentials.md#proxmox-api-token)), the storage holds
  container and VM disks, the LXC template is on the node, the bridge
  exists.
- **cloudflare**, with an account in the config: the token is active and
  sees the zone of `domain`.

Each check is `ok`, `warn`, `fail` or `skip`; a check that isn't `ok`
has its fix under it. On the lab:

```
tools:
  ok    git                git version 2.47.3
  ok    terraform          Terraform v1.13.3
  ...

workspace:
  ok    credentials file   /home/me/urbex-work/home/.urbex/credentials.yaml
  ok    credentials        the Proxmox token and the age key are set
  ok    SSH key            an SSH agent
  ok    GitOps repo        /work/gitops
  ok    platform config    /work/gitops/urbex.platform.yaml

proxmox:
  ok    API                Proxmox VE 9.2.21 at https://192.168.1.10:8006/api2/json
  ok    node               pve
  ok    pool               urbex
  ok    privileges         on /pool/urbex, storage local-zfs and bridge vmbr0
  ok    storage            local-zfs (zfspool), 881 of 896 GB free
  ok    LXC template       local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst
  ok    bridge             vmbr0

cloudflare:
  ok    token              active
  ok    zone               example.com

Everything urbex needs is there.
```

A refused token, for instance:

```
proxmox:
  fail  API                https://192.168.1.10:8006/api2/json: proxmox api GET /version returned 401 Authentication failed!:
                           -> the token is refused: check it is user@realm!name=secret, and not expired or deleted; store it again with 'urbex-op set proxmoxToken'
```

It exits non-zero when a check failed. `--output json` prints the report
as one JSON document, `{"checks": [{"group", "name", "status", "detail",
"fix"}], "ok": true}`, for the setup UI and the plugin
([ADR-0032](../decisions/0032-web-ui-console-ai-assistant.md)).

## `urbex discover`

```
urbex discover [--proxmox https://<host>:8006] [--no-scan] [--write] [--gitops-repo <dir>] [--output text|json]
```

Finds what `urbex.platform.yaml` needs and proposes it, each value with
where it comes from. It reads with the stored tokens and changes
nothing on Proxmox or Cloudflare; it prints no secret.

- **Proxmox** (`--proxmox`, or `proxmox.apiUrl` of an existing config):
  the version, the nodes, the token's pool and bridge, the storages for
  LXC and VM disks (a thin pool such as `local-zfs` or `local-lvm` first,
  then the most room), the newest amd64 Debian 13 LXC template, whether
  the platform's VMIDs are free, and an Urbex platform already in the
  pool. Whether to check the certificate (`insecure`) comes from whether
  it is trusted.
- **The LAN**, from the bridge's address on the node: its CIDR and
  gateway, then a block of 20 free addresses nearest `.200`, scanned by
  ping and by TCP on the usual ports (22, 80, 443, 53, 8006, 445).
  `--no-scan` skips the scan. A host that answers neither looks free:
  keep the block outside your DHCP range.
- **Cloudflare**, with a token: its zones, the first one proposed, and
  whether the token is active.

```
Proxmox VE 9.2.21 at https://192.168.1.10:8006/api2/json, node pve, pool urbex
  storages for disks: local-zfs (zfspool, 881 GB free)
  Debian 13 templates: local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst
LAN 192.168.1.0/24, gateway 192.168.1.1, 29 addresses answer
Cloudflare: token active true, zones example.com
warning: the scan sees only what answers (ping, or a TCP port): keep the proposed block outside the DHCP range

Proposed urbex.platform.yaml (save it with --write):

# Proposed by 'urbex discover' - check every value, then run 'urbex bootstrap'.
# See docs/reference/platform-config.md in urbforge/urbex.
domain: example.com   # the Cloudflare zone

git:
  giteaUrl: https://git-urbex.example.com
  org: urbex

cloudflare:   # public HTTPS on example.com; Gitea and Komodo behind Cloudflare Access
  accountId: 0123456789abcdef0123456789abcdef
  zoneId: fedcba9876543210fedcba9876543210
  access:
    emails: [you@example.com]   # FILL IN: who may open Gitea and Komodo (a one-time PIN goes to the address)

proxmox:
  apiUrl: https://192.168.1.10:8006/api2/json
  insecure: true   # the node's certificate is Proxmox's own, self-signed
  node: pve
  storagePool: local-zfs   # zfspool, 881 of 896 GB free
  lxcTemplate: local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst
  sshPublicKey: "ssh-ed25519 AAAA... urbex"   # the workspace's home/.ssh/urbex.pub
  vmIdBase: 9000   # base services from here, projects from +100: free
  pool: urbex   # the token's pool
  network:
    cidr: 192.168.1.0/24   # bridge vmbr0 on pve
    gateway: 192.168.1.1
    baseHostOffset: 200   # .200-.219 answered nothing in the scan; keep them out of the DHCP range
    bridge: vmbr0
    dnsServers: [192.168.1.1]   # the gateway; set your LAN's resolver if it isn't
```

Without a Cloudflare token the proposal keeps everything on the LAN,
with `domain: home.arpa` (the name reserved for home networks; set yours
if you have one). What it can't know is marked `FILL IN`. `--write` saves
the proposal as `urbex.platform.yaml` in the GitOps repo, and refuses to
replace one that exists. Then `urbex doctor` checks it.

It exits non-zero when it can't propose a config (the token is refused,
no storage or Debian 13 template the token can use, no Cloudflare zone).
`--output json` prints what it found (`proxmox`, `network`,
`cloudflare`, `sshPublicKey`), the `proposal` as text, and the
`warnings` and `errors`.

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
urbex bootstrap [--gitops-repo <dir>] [--dry-run] [--events json]
```

Creates the platform: the base-service LXCs, and Gitea and Komodo wired
together. Run it once per platform; running it again is safe and is how
the base services are updated. Its phases, what runs at the same time
and how long each takes are drawn in [startup sequence](startup.md);
`urbex status --progress` follows them live.

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
5. Prepares urbex's LXC template when it is missing or outdated
   (`urbex-template`, in the pool): Docker, sops and the agents' images
   already installed, so that the LXCs - the platform's now, the
   projects' on `urbex apply` - are linked clones of it, created in
   seconds, with nothing to download. Where Proxmox doesn't allow it, the
   LXCs come from the Debian template as before, with a warning.
   Then `terraform init` and `terraform apply` in `terraform/base/`, then
   `ansible-playbook` with `ansible/playbook.yml`: Docker on every LXC
   (skipped on clones of the template), then Technitium, then Gitea,
   Komodo (Core, database, Periphery) and the others in parallel - while
   they install, the LXCs of Keycloak, the observability stack and the
   tunnel pull, one at a time, the images of the Stacks Komodo deploys
   on them later.
   Every LXC resolves through Technitium, then `dns.forwarders`.
6. Mints a Technitium API token (with the generated
   `URBEX_TECHNITIUM_ADMIN_PASSWORD`, which Ansible also set as
   Technitium's own admin password), creates the internal zone
   (`dns.zone`, by default `<cloudflare.name>.<domain>`), sets its
   forwarders and records every platform service by name (`git`,
   `komodo`, `hooks`, `auth`, `dns`, `grafana`, `prometheus`, `loki`,
   `tunnel`). On a platform set up with a zone named after `domain`, it
   moves the project services' records to the new zone and deletes the
   old one - see [ADR-0027](../decisions/0027-service-conventions.md).
7. Platform setup: a Gitea token, the org and its `gitops` repo; a Komodo
   API key, the onboarding key, Komodo's Gitea git and registry accounts,
   the `URBEX_*` Komodo variables, the `urbex-release` Action, the
   `urbex-gitops` Procedure; `.sops.yaml`; commits and pushes the GitOps
   repo, and adds its webhook. Tokens and keys already in the credentials
   file are reused, not rotated.
   Then connects the other base LXCs to Komodo and has Komodo adopt
   Technitium, Gitea and Komodo as Stacks (`urbex-technitium`,
   `urbex-gitea`, `urbex-komodo`) whose compose files stay on their
   servers, in `/opt/urbex`: Komodo takes over the running containers
   without redeploying them, and from then on can redeploy them; a copy
   of each compose file, without secrets, is committed to the GitOps repo
   in `platform/<service>/compose.yaml` for review. If a redeploy breaks
   one of them, re-running `urbex bootstrap` restores it from Ansible
   ([ADR-0027](../decisions/0027-service-conventions.md)).
   Keycloak, the observability stack and, with Cloudflare, the tunnel
   are written to the GitOps repo's `platform/<service>/` - their admin
   passwords and the tunnel's token encrypted with SOPS - and deployed
   by Komodo as the Stacks `urbex-keycloak`, `urbex-observability` and
   `urbex-tunnel`, like a project service. These and every LXC's
   telemetry agent (`urbex-telemetry-<lxc>`) are deployed all at once;
   if any fails, bootstrap stops naming each Stack that failed, after the
   others have finished.
8. With Cloudflare configured
   ([ADR-0022](../decisions/0022-cloudflare-tunnel-access-workers.md)):
   before Ansible, the tunnel `urbex-platform` and the token its
   connector on `urbex-tunnel` runs with; at the end, Access first - the
   one-time PIN login if missing, the policy for `cloudflare.access.emails`,
   applications for Gitea and Komodo - then the routes and DNS records of
   Keycloak, Gitea, Komodo and the webhook listener. If Access can't be set
   up, nothing is published.
9. Waits for Keycloak to answer before reporting the platform ready: its
   first start takes a few minutes (it says so while waiting), and stops
   with an error after 15 minutes.

| Flag | Meaning |
|---|---|
| `--dry-run` | Do steps 1-4 (files only, no secrets generated) and stop before Terraform. |

Needs: `URBEX_PROXMOX_TOKEN`, `URBEX_AGE_KEY`, `terraform`,
`ansible-playbook`, `git`, an SSH agent with the key in
`proxmox.sshPublicKey`, and with Cloudflare `URBEX_CLOUDFLARE_TOKEN`. Everything it creates is listed in
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
urbex apply <env> [--file urbex.yaml] [--gitops-repo <dir>] [--repo-dir .] [--delete-data] [--events json]
```

Creates or updates an environment of the project - its infrastructure,
the project's build setup, and the environment's deploy setup - and, if
there is something to run, waits until it runs. Its phases and their
usual times: [startup sequence](startup.md#urbex-apply-env);
`urbex status --progress` follows them live.

1. Everything `plan` does, then `terraform apply`: one LXC per service.
   `terraform plan` runs first, and a plan that would delete an LXC
   with named volumes, declared in `urbex.yaml` or still on it, is
   refused, naming it: Proxmox deletes an LXC's volumes with it. A
   replacement names the attributes that force it and is never allowed.
   An application removed from `urbex.yaml` is a plain delete, which
   goes ahead only with `--delete-data`: `apply` names the LXCs and
   volumes first, and deletes them. Then each named volume the LXC
   lacks becomes a mount point (`backup=1`), and a bigger `size` grows
   it; a smaller one is refused. An LXC that can't mount them at once
   is restarted, and the restart is said first. An application whose
   shares the LXC lacks, or whose volumes are still not mounted, is
   left out of the next steps, and the operator's `pct set` commands
   are printed at the end (see [volumes](manifest.md#volumes)).
2. `ansible-playbook` with `ansible/project-playbook.yml`: Docker, the
   Komodo Periphery agent (registered under the LXC's hostname), `sops`
   and the compose wrapper that decrypts secrets. For each named
   volume, it removes the empty `lost+found` of a new one (ext4) so that
   Docker can fill the volume from the image, and stops if the folder is
   not a mount point.
3. **The project:** its repo on Gitea (if Gitea has no `main`, pushes
   `--repo-dir`'s `HEAD` there), a Komodo Build per service, and the
   project repo's webhook to the `urbex-release` Action. Applications
   from published images have no Build; a project made only of such
   applications has no webhook either.
4. **The environment:** waits for the LXCs' agents to connect to Komodo
   (accepting the new key of a recreated LXC), writes each service's
   folder in the GitOps repo - and the web frontend's, if the manifest
   has one - declares their Komodo Stacks, commits and pushes. Each
   application from a published image that has no version in this
   environment yet is pinned in the same commit: its tag is resolved to
   a digest, which `version.env` records. A new prod of a stack with
   staging takes instead the tag and digest staging runs, as `urbex
   promote` would, so that production never starts on a digest staging
   has not run. When the tag in `urbex.yaml`
   differs from the one pinned, `apply` reports it and leaves the pinned
   one in place.
5. **Identity**: once Keycloak answers (right after a bootstrap its first
   start can take minutes; `apply` waits up to 15, and says so), the
   environment's Keycloak realm (`<project>-<env>`),
   the services' roles, a client per frontend; in staging a test user per
   role and the `urbex-test` client, the passwords kept encrypted in the
   GitOps repo ([ADR-0024](../decisions/0024-keycloak-realm-per-environment.md)).
6. **Publishing**: registers every declared service's internal DNS name
   in Technitium - `<service>.<env>.<project>.<zone>`, `<service>.<project>.<zone>`
   in prod - at its LAN IP, regardless of Cloudflare
   ([ADR-0027](../decisions/0027-service-conventions.md)); a project
   named like a platform service (`git`, `auth`, ...) is refused;
   with Cloudflare, also routes the services with `public: true` through
   the platform's tunnel and points their public DNS records at it - a
   service no longer public loses its route and public record.
7. **What to run:**
   - a new **staging** follows `main`: `apply` builds `main`'s head and
     waits until staging runs it;
   - a new **prod** stays empty until `urbex promote` or `urbex deploy
     prod`, except for its applications from published images, which run
     the digest just pinned, staging's when staging has one;
   - in a stack whose services all come from published images, every
     environment runs its pinned digests at once;
   - an environment that already runs something is redeployed (e.g. onto
     a recreated LXC) and waited for.

When an application waits for its shares, or its volumes are not
mounted after the LXC restarted, `apply` does all of the above for the
others, then prints what is missing (for a share, the commands to run
on the node, as root) and exits with an error naming the application.
Fix it and run `apply` again.

| Flag | Default | Meaning |
|---|---|---|
| `--repo-dir <dir>` | `.` | The project's local repo, used only if Gitea has no `main` yet. |
| `--delete-data` | off | Let `apply` delete the LXC of an application removed from `urbex.yaml`, with its named volumes, and drop the PostgreSQL roles and schemas no application uses any more, with their data. `apply` names them first. Nothing is kept. A replacement of an LXC with volumes is refused with it as well. |

Needs: `URBEX_PROXMOX_TOKEN`, `URBEX_AGE_KEY`, the platform credentials
from bootstrap, `terraform`, `ansible-playbook`, `git`, the SSH agent.

```
Deployed acme-app (staging):
  api              http://192.168.1.210:8080  3f9c2e1 (git.urbex.example.com:3000/urbex/acme-app-api:3f9c2e1)
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

A release concerns the services built from source only. It is refused
for a stack without such services, and for a stack whose environments
are only `prod`, where there is no staging to release from.

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
  api              git.urbex.example.com:3000/urbex/acme-app-api:0.4.0
Put it in production with 'urbex promote' (or 'urbex deploy prod').
```

Needs: the platform credentials.

## `urbex deploy`

```
urbex deploy <env> [--version <version> | --follow-main] [--file urbex.yaml] [--gitops-repo <dir>]
urbex deploy <env> [--app <name>] (--update | --version <tag> [--no-save]) [--allow-major] [--file urbex.yaml] [--gitops-repo <dir>]
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
| `urbex deploy <env> --update` | Every application from a published image: its tag in `urbex.yaml`, resolved again to the digest it refers to now. |
| `urbex deploy <env> --app <name> --update` | The same, for one application. |
| `urbex deploy <env> --app <name> --version <tag>` | Another tag of one application, resolved to its digest. |

The first four forms concern the services built from source and leave
the applications from published images as they are; the last three
concern only the applications from published images, which run the
digest recorded in their `version.env` until one of these forms, or
`urbex promote`, replaces it. An application whose digest is unchanged
is reported as such (`already runs`) and not redeployed. `--update` and
`--version` cannot be combined, and `--version` requires `--app`, since
each application has its own tags.

`--app <name> --version <tag>` also writes the tag into the `version` of
the application in `urbex.yaml`, so that the manifest and the GitOps
repository do not diverge, when the environment is the first one of the
stack: staging, or prod for a stack that has only production. A
deployment to another environment, such as a rollback of prod, leaves
the manifest as it is. The file is edited in place, with its comments and
formatting preserved, and is not committed. `--no-save` leaves it
unchanged.

A change of major version (the leading number of the tag, `17` to
`18`) of an application with volumes is refused without
`--allow-major`, since its data may require a migration, such as a dump
and restore, before the new version can read it. A PostgreSQL's is
refused even with `--allow-major` while its data directory (`PG_VERSION`)
is the old major's, since the new one can't open it: see
[upgrade PostgreSQL to a new major version](../cookbook.md#upgrade-postgresql-to-a-new-major-version).

Deploying a version removes `TRACK=main`, so an environment that
followed `main` stays on that version (`deploy` says so);
`--follow-main` adds it back.

Before writing anything, `deploy` checks that every service built from
source has an image for the version, and that every tag of an
application from a published image exists in its registry, and refuses
otherwise. It also regenerates each
service's `compose.yaml` from `urbex.yaml`: this is how a changed port or
healthcheck takes effect.

If the environment hasn't moved after a few seconds - Komodo can miss a
push that follows another closely - `deploy` asks Komodo to reconcile.

Needs: the platform credentials. No Terraform, no SSH.

## `urbex promote`

```
urbex promote [--allow-major] [--file urbex.yaml] [--gitops-repo <dir>]
```

Sets production to what staging runs, for the whole stack, and waits
until it runs: the services built from source get the release staging
runs, and the applications from published images get the digests
staging runs, so that an update of such an application is tried in
staging first.

- Staging runs a release: prod gets that release.
- Staging runs a commit of `main`: prod gets the release tagged on that
  commit (the highest, if several). If there is none, `promote` refuses -
  `urbex release` first.

Prod is pinned to the release (no `TRACK=main`). Nothing is rebuilt: the
image is the one staging runs. Prints `Nothing to promote` when prod
already runs it. Configuration and secrets are not copied: they are per
environment.

A change of major version of an application with volumes requires
`--allow-major`, as for [`deploy`](#urbex-deploy). A stack whose
environments are only `prod` has nothing to promote, and `promote`
refuses it.

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
- `list` prints the names, one per line, then the secrets Urbex
  generates for the service's links (`DATABASE_URL`, `PGPASSWORD`,
  `POSTGRES_PASSWORD`...), each followed by `(generated by urbex)`.
  Names aren't encrypted: it needs neither `sops` nor the key, and never
  prints values.

`KEY` must be a valid environment variable name (letters, digits,
underscores, not starting with a digit, not `sops_...`). A key that Urbex
generates for a linked application, such as `PGPASSWORD` or
`POSTGRES_PASSWORD`, is refused, since `urbex apply` would overwrite it
([linked applications](manifest.md#linked-applications)).

Needs: `sops` and `URBEX_AGE_KEY` (`set`, `unset`), the platform
credentials.

## `urbex status`

```
urbex status [<env>] [--file urbex.yaml] [--gitops-repo <dir>] [--output text|json]
urbex status --progress [--watch] [--events json]
```

Without `<env>`: the platform and everything on it - which base-service
LXCs exist on Proxmox, every address of the platform (by internal name,
on the LAN and, with Cloudflare, public - a name whose record is missing
or points elsewhere says so), where the logins are, and every project
environment of the GitOps repo: per service its LAN address, its public
address (the tunnel's route, or the web frontend's Worker), the version
it is set to, its Stack's state in Komodo, and its internal name,
checked against Technitium. It runs from anywhere: no
`urbex.yaml` needed.

```
Base services:
  urbex-gitea              present
  ...

Endpoints:
  Gitea (web, git, registry)   http://git.urbex.example.com:3000            http://192.168.1.200:3000              https://git-urbex.example.com  (public: behind Cloudflare Access)
  Komodo                       http://komodo.urbex.example.com:9120         http://192.168.1.201:9120              https://komodo-urbex.example.com  (public: behind Cloudflare Access)
  Komodo webhooks              http://hooks.urbex.example.com:9120/listener/ http://192.168.1.201:9120/listener/    https://hooks-urbex.example.com/listener/  (signed calls only)
  Keycloak                     http://auth.urbex.example.com:8080           http://192.168.1.203:8080              https://auth-urbex.example.com  (realms public; admin console behind Cloudflare Access)
  Technitium DNS console       http://dns.urbex.example.com:5380            http://192.168.1.202:5380              https://dns-urbex.example.com  (public: behind Cloudflare Access)
  Grafana                      http://grafana.urbex.example.com:3000        http://192.168.1.204:3000              https://grafana-urbex.example.com  (public: behind Cloudflare Access; dashboards Urbex logs, Urbex resources)
  Prometheus                   http://prometheus.urbex.example.com:9090     http://192.168.1.204:9090              https://prometheus-urbex.example.com  (public: behind Cloudflare Access; remote write internal only)
  Loki                         http://loki.urbex.example.com:3100           http://192.168.1.204:3100              https://loki-urbex.example.com  (public: behind Cloudflare Access; push internal only)

Logins: Gitea and Komodo urbex-admin, Grafana admin, Keycloak admin, Technitium admin; passwords in ~/.urbex/credentials.yaml
(giteaAdminPassword, komodoAdminPassword, grafanaAdminPassword, keycloakAdminPassword, technitiumAdminPassword).

Projects:
  acme-app (staging)
    api            http://192.168.1.210:8080    https://api-staging-acme-app-urbex.example.com   version=8d41b07(follows-main) stack=running dns=api.staging.acme-app.urbex.example.com
    web            -                            https://staging-acme-app-urbex.example.com       version=8d41b07(follows-main) stack=running
  acme-app (prod)
    api            http://192.168.1.211:8080    https://api-acme-app-urbex.example.com           version=1.4.0 stack=running dns=api.acme-app.urbex.example.com
```

Both forms first update the GitOps repo from Gitea (the release Action
commits there too), and say so if they can't.

Through `urbex-op`, the credentials file is shown at its path on your
machine, `<workspace>/home/.urbex/credentials.yaml`, not at the
container's `/work/home/...`.

### `--output json`

`--output json` (`-o json`) prints the same as one JSON document on
standard output, for a program to read - a web UI, an MCP server, the
Claude Code plugin ([ADR-0032](../decisions/0032-web-ui-console-ai-assistant.md)).
What couldn't be checked or updated (Gitea, Komodo) is in `warnings`
instead of the text's bracketed lines; errors still go to standard error
with a non-zero exit status. It holds no password: `logins` names each
admin user and the key of its password in the credentials file.

Without `<env>`:

```json
{
  "baseServices": [
    { "service": "gitea", "hostname": "urbex-gitea", "present": true }
  ],
  "endpoints": [
    {
      "service": "gitea",
      "name": "Gitea (web, git, registry)",
      "internal": "http://git.urbex.example.com:3000",
      "lan": "http://192.168.1.200:3000",
      "public": "https://git-urbex.example.com",
      "note": "public: behind Cloudflare Access",
      "dns": { "name": "git.urbex.example.com", "state": "ok", "pointsTo": ["192.168.1.200"], "expected": "192.168.1.200" }
    }
  ],
  "logins": {
    "credentialsFile": "/home/me/urbex-work/home/.urbex/credentials.yaml",
    "users": [ { "service": "gitea", "user": "urbex-admin", "passwordKey": "giteaAdminPassword" } ]
  },
  "projects": [
    {
      "project": "acme-app",
      "env": "prod",
      "services": [
        {
          "service": "api",
          "lan": "http://192.168.1.211:8080",
          "public": "https://api-acme-app-urbex.example.com",
          "version": "1.4.0",
          "stack": "running",
          "dns": { "name": "api.acme-app.urbex.example.com", "state": "ok", "pointsTo": ["192.168.1.211"], "expected": "192.168.1.211" }
        }
      ]
    }
  ]
}
```

With `<env>`, per service its machine (`hostname`, `allocated`,
`provisioned`; `web: true` and its Worker for a web frontend), what the
GitOps repo asks for and Komodo runs (`version`, `followsMain`,
`stack`, `image`, when Komodo answered), the reconciler (`state` -
`running`, `stale` or `never-run` - `lastRun`, `open`, `looping`,
`unstable`, only for an environment whose applications use each other),
the endpoints and, for each PostgreSQL provider, its roles and schemas
(`databases`):

```json
{
  "project": "acme-app",
  "env": "prod",
  "services": [
    { "service": "api", "hostname": "acme-app-api-prod", "allocated": true, "provisioned": true,
      "version": "1.4.0", "stack": "running", "image": "192.168.1.200:3000/urbex/acme-app-api:1.4.0" }
  ],
  "reconciler": { "state": "running", "lastRun": "2026-11-12T07:36:02.411Z" },
  "endpoints": [
    { "service": "api", "lan": "http://192.168.1.211:8080",
      "dns": { "name": "api.acme-app.urbex.example.com", "state": "ok", "pointsTo": ["192.168.1.211"], "expected": "192.168.1.211" } }
  ],
  "databases": [
    { "service": "db", "database": "acme_app", "state": "listed",
      "roles": [ { "role": "api", "schema": "api", "use": "used", "usedBy": "api" } ] }
  ]
}
```

A database's `state` is `listed`, `not-running` (its schemas can't be
listed) or `error` (with `error`); a role's `use` is `used` (by
`usedBy`), `unused` (`--delete-data` drops it), `missing` (the next
apply makes it for `usedBy`) or `foreign` (not made by urbex).

A DNS record's `state` is `ok`, `missing`, `elsewhere` (`pointsTo`
isn't `expected`), `not-checked` (no Technitium token), `unreachable`
or `error` (with `detail`). A manifest that fails validation exits
non-zero with its errors on standard error. `--output json` doesn't
apply to `--progress`.

With `--progress`: how the latest `urbex bootstrap`, `apply`, `destroy` or `teardown` run
on this machine is getting on - from another terminal while it runs, or
afterwards - phase by phase ([startup sequence](startup.md)): each
finished phase with the time it took, the one running with its time so
far and what is usually left, those not begun with their estimate,
those skipped and why, and the time left in all. `--watch` refreshes it
every 2 seconds until the run ends.

```
urbex bootstrap: running for 7m12s, about 3m05s left (started 14:02)
  ✓ Check Proxmox, write the GitOps repo's files     1s
  - Build the LXC template                            skipped: the current one is there
  ✓ Create the LXCs (Terraform)                       56s
  ✓ Configure every LXC (Ansible)                     21s
  ✓ Install Technitium (DNS)                          26s
  ▶ Install Gitea and Komodo, pull the other images   4m29s so far, about 21s left
  · Prepare the telemetry agents                      about 5s
  ...
```

The estimates are the average of the same phase in the last three
successful runs of that command on this machine, or - before there are
any - the times of the startup sequence's tables. The runs are recorded
in `~/.urbex/progress/` (the last ten of each command, never in the
GitOps repo); a run that stopped without finishing - killed, a lost
terminal - shows as such after 2 minutes without news. `--progress`
needs no platform, credentials or GitOps repo, and takes no `<env>`.
With `--events json` it prints the run's [progress events](#progress-events)
instead, from the first, and with `--watch` follows them until the run
ends.

With `<env>`, for each service of the project:

```
acme-app (staging):
  api   acme-app-api-staging   allocated=yes provisioned=yes version=8d41b07(follows-main) stack=running image=git.urbex.example.com:3000/urbex/acme-app-api:8d41b07
```

| Field | Source |
|---|---|
| `allocated` | The service has a VMID/IP in `state/allocations.json`. |
| `provisioned` | Its LXC exists on Proxmox right now. |
| `version` | Its `version.env` in the GitOps repo; `(follows-main)` if it has `TRACK=main`; `none` if unset. |
| `stack`, `image` | What Komodo reports: the Stack's state and the image it runs. |

Then, under *Endpoints*, each service's address on the LAN
(`http://<ip>:<port>`), for a public service or the web frontend its
HTTPS address, and its internal name (`dns=...`), checked against
Technitium: `(missing)` without a record, `(points to ...)` when it
isn't the allocated IP, `(not checked: no technitium token)` on a
machine without the token. A PostgreSQL shows as
`postgres://<ip>:5432`.

For each PostgreSQL (`provides: postgres`), its database, then every
role and schema on it and which application uses each, read from the
server through a Komodo exec. Never a password.

```
Database db (postgres, database shop):
  role api              schema api              used by api
  role web              schema web              unused: 'urbex apply prod --delete-data' drops it
```

`unused` is a role and schema of an application that no longer uses the
database, kept with its data; `missing`, one `urbex apply` hasn't made
yet; `not made by urbex`, a role created by hand, which `--delete-data`
leaves alone.

For an environment whose applications use each other, a last section
says what the reconciler (the Komodo Action `urbex-reconcile`) does for
it, when it last ran and which Stacks it holds back.

```
Reconciler: running, last heard from 42s ago.
  restarted, what uses them waits until they stay up: shop-db-prod
```

| Line | Meaning |
|---|---|
| `running, last heard from <time> ago` | It ran in the last 10 minutes. |
| `has never run`, `last heard from <time> ago - not running` | The Action is not scheduled, or Komodo Core is down; nothing brings the applications back. |
| `circuit open, not deployed until it cools down` | The deploys of these Stacks failed 5 times in a row; the next is tried after 10 minutes. |
| `restarting (crash loop), what uses them waits` | These providers restarted twice within 10 minutes. |
| `restarted, what uses them waits until they stay up` | These providers restarted once, a reboot for instance; what uses them is deployed once they stay up for two runs. |

Needs: `URBEX_PROXMOX_TOKEN`; the platform credentials for the Komodo
columns.

## `urbex destroy`

```
urbex destroy <env> [--file urbex.yaml] [--gitops-repo <dir>] [--delete-data] [--events json]
```

Removes an environment of the project, in this order:

1. Updates the GitOps repo from Gitea.
2. Takes its Komodo Stacks down (`docker compose down`) and deletes them:
   from here on nothing deploys the environment. With Cloudflare, removes
   its public services' routes and DNS records, and its web frontend's
   Worker and custom domain. Removes each service's internal DNS record
   from Technitium ([ADR-0027](../decisions/0027-service-conventions.md)).
   Deletes its Keycloak realm, users included.
3. `terraform destroy` for the services' LXCs, with their disks and
   named volumes.
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

An environment whose applications have named volumes, declared in
`urbex.yaml` or still on their LXCs, is refused before any step, naming
them:

```
acme-vault (prod) has named volumes: vault/data. Destroying it deletes them with their machines: run 'urbex destroy prod --delete-data' to do so
```

| Flag | Meaning |
|---|---|
| `--delete-data` | Delete the named volumes with their machines. Nothing is kept. Shares are never touched. |

The project's repo and images stay on Gitea. Services that were never
applied are skipped; if none were, nothing happens. Base services are
never touched.

Needs: `URBEX_PROXMOX_TOKEN`, `URBEX_AGE_KEY`, the platform credentials,
`terraform`.

## `urbex teardown`

```
urbex teardown [--gitops-repo <dir>] [--yes] [--events json]
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
4. With Cloudflare: removes the platform's Access applications and
   policy, DNS records, and the tunnel. Then `terraform destroy` in
   `terraform/base/` (LXCs already gone are dropped from the state
   first), and deletes urbex's LXC templates (`urbex-template`, VMID
   `vmIdBase+90` to `+99`): `bootstrap` builds a new one.
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
resource pool, its storages, the token and the Debian template
(`proxmox.lxcTemplate`) are left as they are.

## `urbex users`

```
urbex users <env> [--file urbex.yaml] [--gitops-repo <dir>] [--output text|json]
```

Shows the environment's Keycloak realm and issuer and, in staging, the
test users - `test-<role>`, one per role the services declare - with
their passwords, decrypted from the GitOps repo, and the `curl` to get a
token for one:

```
Realm hello-staging, issuer https://auth-urbex.example.com/realms/hello-staging
  test-member              4f0c9b...

A token for one of them:
  curl -s https://auth-urbex.example.com/realms/hello-staging/protocol/openid-connect/token -d grant_type=password -d client_id=urbex-test \
    -d username=test-member -d password=4f0c9b... | jq -r .access_token
```

Needs `sops` and `URBEX_AGE_KEY`. Production has no test users.

With `--output json`, the same as one JSON document; `users` is empty
in production. The passwords are the test users', which is what the
command is for:

```json
{
  "realm": "hello-staging",
  "issuer": "https://auth-urbex.example.com/realms/hello-staging",
  "tokenUrl": "https://auth-urbex.example.com/realms/hello-staging/protocol/openid-connect/token",
  "client": "urbex-test",
  "users": [ { "username": "test-member", "password": "4f0c9b..." } ]
}
```

## Progress events

`urbex bootstrap`, `apply`, `destroy` and `teardown --yes` record their
progress as events, one JSON object per line, in `~/.urbex/progress/`
next to the run's record: what a program - the setup UI, the MCP
server, the plugin - follows instead of reading the output
([ADR-0032](../decisions/0032-web-ui-console-ai-assistant.md)).

With `--events json` the command prints its events on standard output
as they happen, and everything else - its own messages, Terraform's and
Ansible's output - goes to a log file named in the first event. The run
then ignores the loss of its terminal or of whoever reads its events
(`SIGHUP`, `SIGPIPE`): it goes on, and `urbex status --progress --events
json --watch` follows it again, from its first event, until it ends.
Through `urbex-op`, the container goes on running when the `urbex-op`
that started it is gone.

From the Cubotto lab, an `apply` whose reader stopped after three lines
and was followed again from another terminal:

```json
{"time":"2026-11-12T07:58:39.348481224Z","run":"apply-20261112-075839.348","kind":"apply","type":"run-start","command":"urbex apply prod (acme-app)","log":"/work/home/.urbex/progress/apply-20261112-075839.342.log"}
{"time":"2026-11-12T07:58:39.943780159Z","run":"apply-20261112-075839.348","kind":"apply","type":"phase-start","phase":"lxcs","title":"Create or update the LXCs (Terraform)","estimate":13}
{"time":"2026-11-12T07:58:57.578079707Z","run":"apply-20261112-075839.348","kind":"apply","type":"phase-end","phase":"lxcs","title":"Create or update the LXCs (Terraform)","seconds":18}
{"time":"2026-11-12T07:58:58.249714555Z","run":"apply-20261112-075839.348","kind":"apply","type":"step","phase":"configure","step":"Gathering Facts"}
{"time":"2026-11-12T07:59:49.575906508Z","run":"apply-20261112-075839.348","kind":"apply","type":"phase-skip","phase":"build","title":"Build main (Komodo)","note":"its version is built"}
{"time":"2026-11-12T08:00:12.532634795Z","run":"apply-20261112-075839.348","kind":"apply","type":"run-end","seconds":93,"result":"ok"}
```

| `type` | When | Fields besides `time`, `run`, `kind` |
|---|---|---|
| `run-start` | the run starts | `command`; `log`, with `--events json` |
| `phase-start` | a phase starts | `phase`, `title`, `estimate` (seconds) |
| `step` | an Ansible task starts, Terraform is done with a machine | `phase`, `step` |
| `phase-end` | a phase is done | `phase`, `title`, `seconds` |
| `phase-skip` | a phase won't run | `phase`, `title`, `note` (why) |
| `phase-fail` | the running phase failed | `phase`, `title`, `seconds`, `error` |
| `run-end` | the run ended | `result` (`ok`, `failed`, or `stopped` when the run stopped sending news without finishing), `error`, `seconds` |

`run` identifies the run (its record's name); `kind` is the command.
The phases are those of `urbex status --progress` and the
[startup sequence](startup.md) for `bootstrap` and `apply`; `destroy`
has `check`, `stacks`, `unlink`, `machines`, `servers` and `gitops`;
`teardown` has `check`, `cloudflare`, `lxcs`, `templates` and `forget`.
An error before the run starts - an invalid config, a missing
credential - is only on standard error, with the non-zero exit status,
as without `--events`.

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
`urbex status` and `urbex users` take `--output json` for a program to
read.
