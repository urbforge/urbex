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

## Prerequisites

- A running Proxmox server, reachable over the network, with an API
  token.
- `terraform` (or `tofu`) and `ansible-playbook` installed on whichever
  machine runs `urbex` commands - the CLI shells out to both. Also `git`
  and `ssh` (with an agent holding the key matching
  `proxmox.sshPublicKey`, since Terraform's provider and Ansible both
  connect over SSH).
- An `age` keypair for `URBEX_AGE_KEY` (required by `urbex bootstrap`'s
  credential check even though secret encryption itself isn't wired up
  yet - see [Known limitations](#known-limitations-surfaced-by-this-walkthrough)).
- Your app repos can live anywhere (GitHub, GitLab, just local). Urbex
  keeps its own copy of each on the Gitea it provisions - that's what
  Komodo builds images from - and pushes the GitOps repo there too.

**Don't have these yet?** See [`credentials.md`](credentials.md) for
exactly where each one comes from (Proxmox token, SSH key, age keypair),
which ones bootstrap generates for you (Gitea/Komodo admin passwords and
tokens), and the ones you'll only need once later integrations land
(Cloudflare, Brevo).

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

- generates admin passwords for Gitea, Komodo, and Keycloak, and
  stores them - with the Gitea tokens and the Komodo API key it creates
  next - in `~/.urbex/credentials.yaml` (mode 0600, never in the GitOps
  repo);
- creates the Gitea org (`git.org`, default `urbex`) and its `gitops`
  repo, and pushes the GitOps repo there;
- gives Komodo the Gitea account it needs to clone app repos and push
  images to Gitea's container registry. Komodo's own LXC doubles as the
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
(Grafana `:3000`).

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

Validate it, then provision staging:

```sh
urbex init                              # validates urbex.yaml
export URBEX_GITOPS_REPO=~/urbex-gitops
urbex plan staging                      # terraform plan, nothing applied yet
urbex apply staging                     # creates the LXC, builds the image, deploys it
```

`apply` creates the LXC, then builds and deploys the **committed HEAD**
of the app repo ([ADR-0018](decisions/0018-image-build-komodo-gitea-registry.md)):

1. pushes HEAD to `urbex/acme-app` on Gitea (branch `main`);
2. has Komodo build one image per service at that commit and push it to
   Gitea's registry as `<gitea>/urbex/acme-app-api:<short-sha>`;
3. deploys it with Ansible, pinning that exact tag in the LXC's
   `docker-compose.yml`;
4. commits and pushes the GitOps repo, whose inventory now records the
   deployed image.

```
Building acme-app-api at 3f9c2e1 on Komodo...
Built 192.168.1.200:3000/urbex/acme-app-api:3f9c2e1.
Deployed acme-app (staging) at 3f9c2e1:
  api              http://192.168.1.210:8080  (192.168.1.200:3000/urbex/acme-app-api:3f9c2e1)
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
Only committed code is built: `apply`/`deploy` warn if the working tree
is dirty and deploy HEAD without those changes.

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
acme-app (staging):
  api              acme-app-api-staging             allocated=yes provisioned=yes

DNS, TLS certificates, and the latest deployed release are not tracked yet.
```

`apply`/`deploy` already printed each service's URL. `allocated=yes` means `urbex apply` gave it a VMID/IP;
`provisioned=yes` means the LXC actually exists on Proxmox right now
(the two can disagree - e.g. right after a failed `apply`, or after a
manual deletion on Proxmox).

⚠️ **`status` doesn't print the IP or port**, only presence. Besides the
`apply`/`deploy` output, the IP is in the allocation ledger in the GitOps
repo:

```sh
cat ~/urbex-gitops/state/allocations.json
# {"entries":{"acme-app-api-staging":{"vmid":9100,"ip":"192.168.1.210"}}, ...}
```

Then hit the service directly - there's no ingress/DNS yet:

```sh
curl http://192.168.1.210:8080/healthz
```

## 4. Promote to production

Prod needs its own infrastructure first - it's a separate LXC from
staging (see [ADR-0009](decisions/0009-one-lxc-per-service-per-env.md)):

```sh
urbex apply prod
urbex promote
```

`promote` tags HEAD of the `acme-app` repo (`v0.1.0`, auto-incrementing
the patch version on each subsequent call), pushes the tag to `origin`
and to Gitea, then deploys that commit to prod. The image is **reused**,
not rebuilt: it's the one staging got for the same commit, so prod runs
exactly what you tested:

```
Tagged and pushed v0.1.0.
Image 192.168.1.200:3000/urbex/acme-app-api:3f9c2e1 already built, reusing it.
Deployed acme-app (prod) at 3f9c2e1:
  api              http://192.168.1.220:8080  (192.168.1.200:3000/urbex/acme-app-api:3f9c2e1)
Promoted v0.1.0 to prod.
```

⚠️ Per [ADR-0010](decisions/0010-promotion-flow.md), pushing a tag is
supposed to be *the* trigger - Komodo watches for it and rolls prod out
on its own. Komodo builds the images today, but doesn't roll them out
yet: `urbex promote` runs that rollout itself, from your machine, with
the same Ansible step `urbex deploy` uses. Use `--skip-deploy` to only
create/push the tag.

## 5. Ship a fix or a new feature

Make your change, then:

- **App code only** (same service, same resources): commit, then
  ```sh
  urbex deploy staging
  ```
  which builds the new commit and rolls it out.
  ⚠️ Per [ADR-0010](decisions/0010-promotion-flow.md), a push to `main`
  is supposed to auto-deploy staging. That push-triggered reconciliation
  doesn't exist yet - `urbex deploy staging` is the manual stand-in.

- **Infrastructure change** (new service, changed `resources`, new env
  var): edit `urbex.yaml`, then re-run
  ```sh
  urbex plan staging     # review the diff
  urbex apply staging    # allocates a new LXC if you added a service; re-provisions changed ones
  ```

Once staging looks right:

```sh
urbex status staging     # confirm allocated=yes provisioned=yes for everything
# ... manually verify the app, see step 3 ...
urbex apply prod          # if the infra change needs to land in prod too
urbex promote
```

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
2. **Which project services are up, per project+env** - repeat from
   inside each app repo:
   ```sh
   urbex status staging
   urbex status prod
   ```
3. **Which version is deployed where** - the GitOps repo records it:
   every `apply`/`deploy`/`promote` commits the rendered inventory, which
   pins each service's image to the deployed commit:
   ```sh
   grep docker_image ~/urbex-gitops/ansible/projects/*/*/inventory.yml
   git -C ~/urbex-gitops log --oneline      # "urbex deploy acme-app staging @ 3f9c2e1", ...
   git -C /path/to/acme-app tag --points-at 3f9c2e1   # which release that commit is
   ```
   ⚠️ There's no command that summarizes this yet.
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

Four more real situations you'll run into, kept separate from the core
walkthrough above so that one stays a straight line.

### Decommissioning a project

```sh
urbex destroy staging
urbex destroy prod
```

Each tears down every service currently applied for that environment via
`terraform destroy`, then removes their entries from
`state/allocations.json` (`allocation.Ledger.Remove`) so `status`/`deploy`
correctly stop considering them provisioned:

```
$ urbex destroy staging
Destroyed acme-app (staging): [acme-app-api-staging acme-app-worker-staging].
```

Running it again afterwards is a safe no-op (`Nothing to destroy: no
services of acme-app (staging) have been applied.`), since nothing is
left allocated.

⚠️ This only removes the LXCs. There's nothing else to clean up yet
either way - a Keycloak realm ([ADR-0014](decisions/0014-keycloak-realm-per-project.md)),
DNS records ([ADR-0007](decisions/0007-technitium-configurable-domain.md)),
and Cloudflare Tunnel routes ([ADR-0005](decisions/0005-cloudflare-tunnel-ingress.md))
don't get created by `apply` yet, so `destroy` has nothing extra to
remove for them today. When those land, `destroy` will need to grow to
cover them too. Git tags from `urbex promote` are untouched - they're
just history.

### Running urbex from a fresh machine (or a fresh agent session)

Every `bootstrap`/`apply`/`deploy`/`promote`/`destroy` pushes the GitOps
repo to Gitea, so a new machine, or a new Claude Code/Codex session with
no prior state, starts from there:

1. **Clone the GitOps repo** from Gitea
   (`http://<gitea-ip>:3000/urbex/gitops.git`, as `urbex-admin`). Its
   `terraform.tfstate` is plaintext JSON today (not yet SOPS-encrypted
   as [ADR-0013](decisions/0013-terraform-state-in-gitops-repo.md)
   specifies) - that's why the repo is private.
2. **Copy `~/.urbex/credentials.yaml`** from the machine that ran
   bootstrap: besides your Proxmox token and age key, it holds the
   generated Gitea/Komodo passwords, tokens, and API key that `apply`/
   `deploy` need. Transfer it like any secret. Also make sure an SSH
   agent holds the private key matching `proxmox.sshPublicKey` in
   `urbex.platform.yaml` - both Terraform's provider and Ansible connect
   over SSH.
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

Then:

```sh
urbex plan staging    # the terraform plan shows only the new worker LXC - api is untouched
urbex apply staging
```

`apply` allocates a new VMID/IP for `acme-app-worker-staging` only;
`api`'s existing allocation and LXC are left alone
(`allocation.Ledger.Allocate` is idempotent per hostname). `urbex status
staging` then lists both services.

### Rolling back a bad prod release

⚠️ There's no `urbex rollback` command yet, but images are immutable
and tagged by commit, so rolling back is a redeploy of an older commit:

```sh
git -C /path/to/acme-app checkout v0.1.3     # the last good release
urbex deploy prod                             # reuses that commit's image - no rebuild
git -C /path/to/acme-app checkout main
```

Caveats: `deploy` pushes HEAD to Gitea's `main`, so after a rollback
Gitea's copy is behind your real `main` until the next deploy (that's
fine - the next `deploy` fast-forwards it). And the manifest used is the
checked-out `urbex.yaml`, so ports/env vars roll back too, which is
usually what you want.

### Updating a service's config or resources

Two different day-2 changes, handled two different ways:

- **Non-secret env vars** (`services[].env`) or the healthcheck path:
  edit `urbex.yaml`, then just
  ```sh
  urbex deploy staging
  ```
  `deploy` re-renders the Ansible inventory from the manifest on disk
  every time, so a changed `env_vars`/`healthcheck_path` reaches the
  compose file and `docker compose up -d` recreates the container (it's a
  no-op when nothing changed) - no `apply` needed, since the LXC itself
  isn't changing.
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
needs it.

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
| No DNS/ingress/TLS | Steps 1, 3, 4, 6 | Reach services by IP (printed by `apply`/`deploy`, also in `state/allocations.json`); the Gitea registry is plain HTTP, trusted via Docker's `insecure-registries` |
| Rollouts not driven by Komodo | Steps 4, 5 | Komodo builds images, but `urbex deploy`/`urbex promote` roll them out with Ansible from your machine instead of Komodo reacting to Git pushes/tags |
| No deployed-version summary | Step 6 | `grep docker_image` in the GitOps repo's inventories, or its `git log` |
| No fleet-wide status | Step 6 | Run `urbex status [env]` per project, per environment |
| Terraform state unencrypted in practice | Step 1 | `terraform.tfstate` is plain JSON on disk today, not yet SOPS-encrypted as ADR-0013 specifies - keep the GitOps repo private and access-controlled |
| No cross-machine concurrency guard | Cookbook: fresh machine | Keep one GitOps repo copy in active use at a time, pulled before and pushed after every command |
| No rollback command, no removal of Keycloak/DNS/ingress on destroy | Cookbook: rollback, decommissioning | Manual compose/tag surgery for rollback; nothing extra to clean up yet since those integrations don't exist either |

These are natural next increments, roughly in the order a real deployment
would need them: DNS+ingress, then Komodo-driven rollouts
(push-to-deploy), then version tracking and rollback.
