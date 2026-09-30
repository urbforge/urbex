# Real-world walkthrough

A step-by-step walkthrough of the six things you'd actually do with
Urbex today, using the real `urbex` CLI (see
[`urbforge/urbex-cli`](https://github.com/urbforge/urbex-cli)) against a
worked example: **acme-app**, a personal project with a Go backend
service (`api`) and a web frontend. A [Cookbook](#cookbook-additional-scenarios)
section after it covers eight more situations you'll run into:
decommissioning a project, running from a fresh machine/agent session,
adding a second service, rolling back a bad release, updating a
service's config/resources, declaring a service with its own
Dockerfile, running several projects on one platform, and recovering
from an interrupted bootstrap.

> **Read this first.** This guide is written against the CLI as it
> exists today, not the finished v1 vision in
> [`architecture.md`](architecture.md). Every place where the real
> behavior falls short of that vision is called out inline with ⚠️, and
> summarized in [Known limitations](#known-limitations-surfaced-by-this-walkthrough)
> at the end. Don't skip that section before using this for a real
> deployment.

## The model in one paragraph

Each project has a repo on the Gitea that Urbex provisions, with one
branch per environment: **`staging`** and **`main`** (production).
Merging a pull request into one of them makes Komodo build the project's
images and roll them out on that environment's LXCs - no command, no
SSH, no operator machine involved. The `urbex` CLI is for everything
around that: creating the platform (`bootstrap`), creating or changing
an environment's infrastructure and pipeline (`apply`), and opening the
promotion pull request (`promote`). See
[ADR-0019](decisions/0019-branch-environments-komodo-rollouts.md).

## Prerequisites

- A running Proxmox server, reachable over the network, with an API
  token and a **Debian 13** LXC template (`pveam download local
  debian-13-standard_...`).
- `terraform` (or `tofu`) and `ansible-playbook` installed on whichever
  machine runs `urbex bootstrap`/`apply` - the CLI shells out to both.
  Also `git` and `ssh` (with an agent holding the key matching
  `proxmox.sshPublicKey`, since Ansible connects over SSH).
- An `age` keypair for `URBEX_AGE_KEY` (required by `urbex bootstrap`'s
  credential check even though secret encryption itself isn't wired up
  yet - see [Known limitations](#known-limitations-surfaced-by-this-walkthrough)).

**Don't have these yet?** See [`credentials.md`](credentials.md) for
exactly where each one comes from (Proxmox token, SSH key, age keypair),
which ones bootstrap generates for you (Gitea/Komodo/Keycloak/Grafana
passwords, tokens, keys), and the ones you'll only need once later
integrations land (Cloudflare, Brevo).

## 1. Bootstrap the infrastructure

The GitOps repo starts as a local working directory:

```sh
urbex bootstrap --gitops-repo ~/urbex-gitops
```

First run scaffolds `~/urbex-gitops/urbex.platform.yaml` and stops.
Edit it - at minimum `proxmox.apiUrl`, `proxmox.node`, `proxmox.lxcTemplate`,
`proxmox.sshPublicKey`, `proxmox.network.cidr`/`gateway`, and `git.giteaUrl`.
If your API token is scoped to a resource pool, also set `proxmox.pool`
(and `proxmox.keyctl: false` unless the token is `root@pam` - see
[`credentials.md`](credentials.md#proxmox-api-token)).
Then set credentials (never written to any file the GitOps repo tracks):

```sh
export URBEX_PROXMOX_TOKEN='acme@pve!urbex=xxxxxxxx-...'
export URBEX_AGE_KEY='AGE-SECRET-KEY-1...'
```

Run it again to actually provision:

```sh
urbex bootstrap --gitops-repo ~/urbex-gitops
```

This creates 5 LXCs on Proxmox (Gitea, Komodo, Technitium, Keycloak,
observability) via Terraform, then configures each with Docker via
Ansible. Then it wires the platform together:

- generates admin passwords for Gitea, Komodo, Keycloak, and Grafana,
  and stores them - with the Gitea token and the Komodo keys it creates
  next - in `~/.urbex/credentials.yaml` (mode 0600, never in the GitOps
  repo);
- creates the Gitea org (`git.org`, default `urbex`) and its `gitops`
  repo, and pushes the GitOps repo there;
- gives Komodo the Gitea account it needs to clone app repos and push
  images to Gitea's container registry, and creates the onboarding key
  project LXCs will join Komodo with. Komodo's own LXC doubles as the
  image builder (`urbex-komodo`).

```
Base services provisioned.
Gitea ready at http://192.168.1.200:3000 (org urbex).
Komodo ready at http://192.168.1.201:9120 (builder urbex-komodo).
GitOps repo pushed to http://192.168.1.200:3000/urbex/gitops.git.
Platform ready. Gitea/Komodo admin user: urbex-admin; generated passwords and tokens are in /home/you/.urbex/credentials.yaml.
```

Re-running the same command later is safe - it's idempotent, keeps the
secrets and tokens it already generated, and aborts instead of
duplicating anything if it finds a `urbex-*`-named container Terraform
doesn't know about (see
[ADR-0017](decisions/0017-embedded-base-infra-assets.md)).

⚠️ **Nothing here is reachable by name yet.** DNS registration in
Technitium isn't implemented, and everything is plain HTTP on the LAN
(no ingress/TLS yet). Base services get consecutive IPs starting at
`proxmox.network.baseHostOffset`, in the order Gitea (`:3000`), Komodo
(`:9120`), Technitium (`:5380`), Keycloak (`:8080`), observability
(Grafana `:3000`). Log in to Gitea and Komodo as `urbex-admin` with the
passwords from `~/.urbex/credentials.yaml`.

## 2. Deploy a service (frontend + backend)

### Backend

In the `acme-app` repo:

```sh
urbex init --project acme-app
```

This scaffolds `urbex.yaml`. Edit it to declare the backend service:

```yaml
apiVersion: urbex/v1
project: acme-app

frontend:
  type: web
  provider: cloudflare-pages
  buildCommand: npm run build
  outputDir: dist

services:
  - name: api
    runtime: go
    port: 8080
    healthcheck: /healthz
    env:
      staging:
        LOG_LEVEL: debug
      prod:
        LOG_LEVEL: info
```

Validate it, commit, then create staging:

```sh
urbex init                              # validates urbex.yaml
git add urbex.yaml && git commit -m "Add urbex manifest"
export URBEX_GITOPS_REPO=~/urbex-gitops
urbex plan staging                      # terraform plan, nothing applied yet
urbex apply staging
```

`apply` does everything needed for staging to run and to keep deploying
itself:

1. creates the LXC (Terraform) and installs Docker and the Komodo
   Periphery agent on it (Ansible);
2. creates `urbex/acme-app` on Gitea and, since it has no `staging`
   branch yet, creates it from your local HEAD;
3. declares in Komodo a Build and a Deployment for `api`, and the
   `acme-app-staging` Procedure that runs them;
4. adds a webhook on the Gitea repo that triggers that Procedure on
   every push to `staging`;
5. runs the Procedure once, so staging is up when `apply` returns.

```
Created branch staging of urbex/acme-app on Gitea from the local HEAD.
Building and deploying acme-app-staging from branch staging on Komodo...
Deployed acme-app (staging) from branch staging:
  api              http://192.168.1.210:8080  running (192.168.1.200:3000/urbex/acme-app-api:0.0.1-staging)
From now on, merging into staging deploys staging automatically.
```

Now make Gitea your remote for the project, so your pull requests land
there:

```sh
git remote add origin http://192.168.1.200:3000/urbex/acme-app.git
git fetch origin
```

For `runtime: go`, `python`, and `java`, Urbex supplies the Dockerfile.
Its conventions:

| Runtime | Builds | Runs |
|---|---|---|
| `go` | `./cmd/<service>` if it exists, else the module root | the binary |
| `python` | `pip install -r requirements.txt` if present | `python main.py` |
| `java` | Gradle wrapper if present, else Maven (`mvnw` or `mvn`) | the built executable jar |

Every service must listen on `$PORT`, which Urbex sets to the manifest's
`port`. For anything else, use `runtime: docker` with your own
Dockerfile (see the [Cookbook](#declaring-a-service-with-its-own-dockerfile)).

### Frontend

⚠️ **Urbex doesn't deploy the frontend at all yet.** `frontend` in
`urbex.yaml` is currently documentation only - there's no `urbex`
command that runs `npm run build` and pushes `dist/` to Cloudflare
Pages. Do that yourself for now (`wrangler pages deploy dist/`, a
Cloudflare Pages Git integration, or your own CI step), and point it at
your API's IP (see the next section) until DNS/ingress exist.

## 3. Test the app and see its status

```sh
urbex status staging
```

```
acme-app (staging, branch staging):
  api              acme-app-api-staging             allocated=yes provisioned=yes deployment=running image=192.168.1.200:3000/urbex/acme-app-api:0.0.1-staging

DNS and TLS certificates are not tracked yet.
```

`allocated=yes` means `urbex apply` gave it a VMID/IP;
`provisioned=yes` means the LXC actually exists on Proxmox right now
(the two can disagree - e.g. right after a failed `apply`, or after a
manual deletion on Proxmox); `deployment` and `image` are what Komodo
reports the LXC is running.

`apply` printed the service's URL; the IP is also in the allocation
ledger in the GitOps repo:

```sh
cat ~/urbex-gitops/state/allocations.json
# {"entries":{"acme-app-api-staging":{"vmid":9100,"ip":"192.168.1.210"}}, ...}
curl http://192.168.1.210:8080/healthz
```

⚠️ There's no ingress/DNS yet: it's always `http://<ip>:<port>`.

## 4. Ship a fix or a new feature

This is the everyday loop, and it doesn't involve `urbex` at all:

```sh
git checkout -b fix-greeting origin/staging
# ... change code, commit ...
git push origin fix-greeting
```

Open a pull request into **`staging`** on Gitea and merge it. Gitea
calls Komodo, which builds the new image and replaces the container -
staging serves the new version seconds after the build finishes. Follow
it in Komodo's UI (Procedure `acme-app-staging`), or:

```sh
urbex status staging      # image=...:0.0.2-staging
```

Only changes to `urbex.yaml` need the CLI:

- **Env vars, port, healthcheck**: once the change is merged, run
  ```sh
  git checkout staging && git pull
  urbex deploy staging
  ```
  which re-syncs Komodo's Build/Deployment from the manifest and
  redeploys.
- **Infrastructure** (a new service, changed `resources`):
  ```sh
  urbex plan staging     # review the diff
  urbex apply staging    # allocates a new LXC if you added a service; re-provisions changed ones
  ```

⚠️ A merge deploys code, never the manifest: Komodo keeps running with
the settings from the last `urbex apply`/`deploy`.

## 5. Promote to production

Prod needs its own infrastructure first - separate LXCs from staging
(see [ADR-0009](decisions/0009-one-lxc-per-service-per-env.md)). Once:

```sh
urbex apply prod       # same as staging, tracking branch main
```

Then, every time staging is good:

```sh
urbex promote
```

```
Opened pull request #7 (staging -> main): http://192.168.1.200:3000/urbex/acme-app/pulls/7
Merge it to deploy production (or re-run with --merge).
```

Merging that pull request deploys production, exactly like a merge into
`staging` deploys staging. `urbex promote --merge` opens and merges it in
one go; `urbex promote` alone says `Nothing to promote` when `main`
already has everything `staging` has.

⚠️ Production is **rebuilt** from `main`, not given staging's image (a
merge commit is a different commit). Builds are from the same sources,
but if you need byte-identical artifacts across environments, that's not
what this flow gives you.

## 6. Overall status: what's deployed where, which version, how to reach it

This is the honest state of things today - there is **no single command**
that answers "show me everything, across every project and
environment." `urbex status` is scoped to one project (the `urbex.yaml`
in your current directory) and, with an argument, one environment.

To build the full picture yourself right now:

1. **Which base services are up:**
   ```sh
   urbex status
   ```
2. **Which project services are up, and running what** - repeat from
   inside each app repo:
   ```sh
   urbex status staging
   urbex status prod
   ```
   The image tag is `<version>-<env>`; Komodo also pushes a
   `<commit>-<env>` tag for every build, and its UI shows the commit and
   log of each one. Komodo's UI (`http://<komodo-ip>:9120`) is the
   cross-project view: every Server, Build, Deployment, and Procedure.
3. **What Urbex asked Komodo to run** - recorded in the GitOps repo on
   every `apply`/`deploy`:
   ```sh
   ls ~/urbex-gitops/komodo/*/          # <project>/<env>.json
   git -C ~/urbex-gitops log --oneline  # "urbex apply acme-app staging", ...
   ```
4. **How to reach each service** - IPs live in the GitOps repo, per
   project+env:
   ```sh
   cat ~/urbex-gitops/state/allocations.json
   ```
   Ports and healthcheck paths come from each app's `urbex.yaml`
   (`services[].port`, `services[].healthcheck`). There's no DNS or
   public URL yet (see [ADR-0007](decisions/0007-technitium-configurable-domain.md)
   and [ADR-0005](decisions/0005-cloudflare-tunnel-ingress.md), both
   still unimplemented) - it's always `http://<ip>:<port>`.

## Cookbook: additional scenarios

More real situations you'll run into, kept separate from the core
walkthrough above so that one stays a straight line.

### Decommissioning a project

```sh
urbex destroy staging
urbex destroy prod
```

Each removes the environment's webhook on Gitea and its Komodo resources
(Procedure, Deployments, Builds - which stops the containers), tears
down the LXCs via `terraform destroy`, removes their Servers from
Komodo, then removes their entries from `state/allocations.json` so
`status`/`deploy` correctly stop considering them provisioned:

```
$ urbex destroy staging
Destroyed acme-app (staging): [acme-app-api-staging acme-app-worker-staging].
```

Running it again afterwards is a safe no-op (`Nothing to destroy: no
services of acme-app (staging) have been applied.`), since nothing is
left allocated.

⚠️ The project's repo and its images stay on Gitea - delete them there
if you want them gone. Nothing else needs cleaning up yet - a Keycloak
realm ([ADR-0014](decisions/0014-keycloak-realm-per-project.md)),
DNS records ([ADR-0007](decisions/0007-technitium-configurable-domain.md)),
and Cloudflare Tunnel routes ([ADR-0005](decisions/0005-cloudflare-tunnel-ingress.md))
don't get created by `apply` yet, so `destroy` has nothing extra to
remove for them today. When those land, `destroy` will need to grow to
cover them too.

### Running urbex from a fresh machine (or a fresh agent session)

Deploying needs no machine at all - merge a pull request. The CLI is
only needed for `apply`/`deploy`/`promote`/`destroy`, and a new machine,
or a new Claude Code/Codex session with no prior state, gets there like
this:

1. **Clone the GitOps repo** from Gitea
   (`http://<gitea-ip>:3000/urbex/gitops.git`, as `urbex-admin`). Its
   `terraform.tfstate` is plaintext JSON today (not yet SOPS-encrypted
   as [ADR-0013](decisions/0013-terraform-state-in-gitops-repo.md)
   specifies) - that's why the repo is private.
2. **Copy `~/.urbex/credentials.yaml`** from the machine that ran
   bootstrap: besides your Proxmox token and age key, it holds the
   generated Gitea/Komodo passwords, token, and keys. Transfer it like
   any secret. For `apply`, also make sure an SSH agent holds the
   private key matching `proxmox.sshPublicKey` in `urbex.platform.yaml`.
3. **Point at the repo**: `export URBEX_GITOPS_REPO=/path/to/the/clone`.
4. Anything you now run (`status`, `plan`, `apply`, `deploy`) sees
   exactly the state the previous machine left behind -
   `allocations.json` and the Terraform state are the source of truth,
   not anything local to a given machine.

⚠️ Nothing enforces this today. If two machines run `apply` concurrently
against copies of the GitOps repo that have drifted, they can conflict or
silently overwrite each other's state - see the concurrency risk called
out in [ADR-0013](decisions/0013-terraform-state-in-gitops-repo.md)'s
Consequences. Treat "one GitOps repo copy in active use at a time, pulled
before and pushed after every command" as a manual discipline for now.

### Adding a second service to an existing project

A small, common day-2 change. Edit `urbex.yaml` to add another entry
under `services:`, e.g. a background worker alongside `api`:

```yaml
services:
  - name: api
    runtime: go
    port: 8080
  - name: worker
    runtime: go
    port: 9000
```

Merge that into `staging`, then, from an up-to-date checkout of it:

```sh
urbex plan staging    # the terraform plan shows only the new worker LXC - api is untouched
urbex apply staging
```

`apply` allocates a new VMID/IP for `acme-app-worker-staging` only;
`api`'s existing allocation and LXC are left alone
(`allocation.Ledger.Allocate` is idempotent per hostname). It adds the
worker's Build and Deployment to the `acme-app-staging` Procedure, so
the next merge builds and deploys both. `urbex status staging` then
lists both services. Do the same with `urbex apply prod` once the change
reaches `main`.

### Rolling back a bad prod release

⚠️ There's no `urbex rollback` command yet. Two ways, both outside the
CLI:

1. **Revert in Git** - the one that keeps Git and production in
   agreement. On Gitea (or locally), revert the offending merge on
   `main`; pushing the revert deploys it like any other change:
   ```sh
   git checkout main && git pull
   git revert -m 1 <merge-commit>
   git push origin main
   ```
2. **Pin the previous image in Komodo** - faster, no rebuild: in
   Komodo's UI, open the Deployment (`acme-app-api-prod`), set its image
   version to the previous one (e.g. `0.0.6`) and deploy. It stays
   pinned - merges into `main` keep building but redeploy the pinned
   version - until you clear the version in Komodo or run `urbex deploy
   prod`, which puts it back on the latest build.

### Updating a service's config or resources

Two different day-2 changes, handled two different ways:

- **Non-secret env vars** (`services[].env`) or the healthcheck path:
  edit `urbex.yaml`, then just
  ```sh
  urbex deploy staging
  ```
  `deploy` re-syncs the service's Komodo Deployment from the manifest on
  disk and redeploys, so the container is recreated with the new
  settings - no `apply` needed, since the LXC itself isn't changing. Run
  it from a checkout of the environment's branch, so the manifest you
  apply is the one that was merged.
- **`resources` (cpu/memory/disk)**: these are Terraform-managed
  (`platform/terraform/modules/lxc`), so you need
  ```sh
  urbex plan staging     # review the diff before touching anything
  urbex apply staging
  ```
  ⚠️ Untested against real Proxmox (see the CLI's own README caveat):
  CPU/memory changes are ordinarily applied in place by the `bpg/proxmox`
  provider, but disk changes - especially shrinking - may not be
  supported the same way and could force replacing the container. Always
  read the `terraform plan` output before running `apply` for a resize.

### Declaring a service with its own Dockerfile

Not every service has to be `java`/`python`/`go` - a service can point at
a Dockerfile you already have instead:

```yaml
services:
  - name: worker
    runtime: docker
    dockerfile: ./worker/Dockerfile
    port: 9000
```

`dockerfile` is required whenever `runtime: docker` (enforced by
[`schemas/urbex.schema.json`](../schemas/urbex.schema.json) - `urbex
init` rejects a manifest that sets one without the other). Komodo builds
it with the Dockerfile's directory as build context (`./worker` here),
like `build: ./worker` in docker compose. Everything else about
`plan`/`apply`/`deploy` for this service works exactly like any other.
The container still gets `PORT` set to the manifest's `port`, and the
healthcheck (if declared) runs `wget` inside the container, so your image
needs it. Like any service, it is built from the environment's branch on
every merge.

### Running multiple independent projects on one platform

Nothing special to do - just `urbex init`/`apply` a second project
(`sidekick`, say) against the same `--gitops-repo`. Hostnames are always
`<project>-<service>-<env>`, and VMIDs/IPs come from one shared counter
in `state/allocations.json` across *every* project that uses this GitOps
repo, so they never collide:

```json
{
  "entries": {
    "acme-app-api-staging":    {"vmid": 9100, "ip": "192.168.1.210"},
    "acme-app-worker-staging": {"vmid": 9101, "ip": "192.168.1.211"},
    "sidekick-api-staging":    {"vmid": 9102, "ip": "192.168.1.212"}
  },
  "nextVmid": 9103,
  "nextIpOffset": 213
}
```

`urbex status`/`plan`/`apply`/`deploy`/`destroy` all still operate on one
project at a time (the `urbex.yaml` in your current directory) - see the
[no fleet-wide status](#known-limitations-surfaced-by-this-walkthrough)
gap for what that means day to day with several projects running.

### Recovering from an interrupted or partial bootstrap

`urbex bootstrap` is designed to be safely re-run - if it dies partway
(network blip during `terraform apply`, a failed Ansible task, you
`Ctrl-C`'d it), just run the exact same command again:

```sh
urbex bootstrap --gitops-repo ~/urbex-gitops
```

Terraform's state already reflects whatever it finished creating before
the failure, so re-running only creates what's still missing and leaves
already-provisioned LXCs alone; Ansible's tasks are idempotent, so
already-configured services aren't touched either (see
[ADR-0006](decisions/0006-bootstrap-command.md)).

⚠️ The one case this can't recover from automatically: a container named
`urbex-gitea` (etc.) exists on Proxmox but Terraform's local state
(`terraform/base/terraform.tfstate` in the GitOps repo) doesn't know
about it - e.g. you're pointing `--gitops-repo` at a fresh empty
directory while the LXCs from an earlier run are still on Proxmox. The
pre-flight check refuses to guess and aborts loudly instead:

```
found existing Proxmox container(s) [urbex-gitea] not tracked in
/home/you/urbex-gitops/terraform/base/terraform.tfstate - resolve
manually (rename/remove them, or point --gitops-repo at the repo that
already manages them) before running bootstrap
```

That message is the fix: point `--gitops-repo` at wherever the original
GitOps repo actually is, or manually rename/remove the stray containers
on Proxmox if they're genuinely orphaned.

## Known limitations surfaced by this walkthrough

Everything below is tracked as unimplemented in
[`urbforge/urbex-cli`](https://github.com/urbforge/urbex-cli)'s README
and the relevant ADRs; listed together here because this walkthrough is
where they actually bite:

| Gap | Where it shows up | Workaround today |
|---|---|---|
| No DNS/ingress/TLS | Steps 1, 3, 6 | Reach services by IP (printed by `apply`/`deploy`, also in `state/allocations.json`); Gitea and its registry are plain HTTP, trusted via Docker's `insecure-registries` |
| Manifest changes aren't applied by a merge | Step 4 | Run `urbex deploy <env>` (or `apply` for infrastructure) from a checkout of the branch after merging |
| Prod is rebuilt, not promoted as an artifact | Step 5 | Accept it, or pin a version on the Komodo Deployment |
| No rollback command | Cookbook: rollback | Revert on the branch, or pin the previous version in Komodo |
| No fleet-wide status | Step 6 | Run `urbex status [env]` per project, per environment, or use Komodo's UI |
| Frontend not deployed | Step 2 | Deploy to Cloudflare Pages/Firebase yourself |
| Terraform state unencrypted in practice | Step 1 | `terraform.tfstate` is plain JSON, not yet SOPS-encrypted as ADR-0013 specifies - the GitOps repo on Gitea is private; keep it that way |
| No cross-machine concurrency guard | Cookbook: fresh machine | Keep one GitOps repo copy in active use at a time, pulled before and pushed after every command |
| No removal of Keycloak/DNS/ingress on destroy | Cookbook: decommissioning | Nothing extra to clean up yet, since those integrations don't exist either |

These are natural next increments, roughly in the order a real deployment
would need them: DNS+ingress, then applying manifest changes on merge,
then rollback.
