# Real-world walkthrough

A step-by-step walkthrough of the six things you'd actually do with
Urbex today, using the real `urbex` CLI (see
[`urbforge/urbex-cli`](https://github.com/urbforge/urbex-cli)) against a
worked example: **acme-app**, a personal project with a Go backend
service (`api`) and a web frontend. A [Cookbook](#cookbook-additional-scenarios)
section after it covers eight more situations you'll run into:
decommissioning a project, running from a fresh machine/agent session,
adding a second service, rolling back a bad release, updating a
service's config, secrets, or resources, declaring a service with its own
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

Each project has a repo on the Gitea that Urbex provisions, developed
**trunk-based** on `main`. A **release is a tag** (`vX.Y.Z`): tagging
makes Komodo build the project's images, once. What each environment
runs is written in the **GitOps repo**, in
`environments/<env>/<project>/<service>/`: the version, the
configuration, the secrets. Komodo deploys those folders, so deploying,
promoting, and rolling back are commits to the GitOps repo - which the
`urbex` CLI makes for you (`deploy`, `promote`, `secret`), but which you
can just as well make by hand. See
[ADR-0020](decisions/0020-trunk-releases-gitops-environments.md).

## Prerequisites

- A running Proxmox server, reachable over the network, with an API
  token and a **Debian 13** LXC template (`pveam download local
  debian-13-standard_...`).
- `terraform` (or `tofu`) and `ansible-playbook` installed on whichever
  machine runs `urbex bootstrap`/`apply` - the CLI shells out to both.
  Also `git` and `ssh` (with an agent holding the key matching
  `proxmox.sshPublicKey`, since Ansible connects over SSH).
- An `age` keypair for `URBEX_AGE_KEY`: every secret in the GitOps repo
  is encrypted for it. And `sops`, if you'll use `urbex secret`.

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
  repo, writes `.sops.yaml` (the age public key secrets are encrypted
  for), and pushes the GitOps repo there;
- gives Komodo the Gitea account it needs to clone repos and push images
  to Gitea's container registry, and creates the onboarding key project
  LXCs will join Komodo with. Komodo's own LXC doubles as the image
  builder (`urbex-komodo`);
- installs in Komodo the two things every project shares: the
  `urbex-release` Action, which builds release tags, and the
  `urbex-gitops` Procedure, which deploys the GitOps repo's environment
  folders whenever they change (a webhook on the repo) and every 15
  minutes regardless.

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

`apply` sets up the project and the environment, and deploys nothing
yet:

1. creates the LXC (Terraform) and installs Docker and the Komodo
   Periphery agent on it (Ansible);
2. creates `urbex/acme-app` on Gitea - with `main` taken from your local
   HEAD, since Gitea doesn't have it yet - a Komodo Build for `api`, and
   the webhook that has Komodo build every release tag;
3. writes `environments/staging/acme-app/api/` in the GitOps repo
   (compose file, `config.env` seeded from the manifest's `env.staging`,
   an empty secrets file) and declares the Komodo Stack that deploys
   that folder on the LXC.

```
Created urbex/acme-app on Gitea with branch main from the local HEAD.
acme-app (staging) is ready, with no version to run yet:
  api              http://192.168.1.210:8080
Release one with 'urbex release', then run 'urbex deploy staging'.
```

Make Gitea your remote for the project:

```sh
git remote add origin http://192.168.1.200:3000/urbex/acme-app.git
git fetch origin
```

Then release what's on `main` and put it on staging:

```sh
urbex release            # tags v0.1.0 on main; Komodo builds acme-app-api:0.1.0
urbex deploy staging     # writes VERSION=0.1.0 into the GitOps repo and pushes; Komodo deploys
```

```
Tagged v0.1.0 on main; Komodo is building it...
Released acme-app 0.1.0:
  api              192.168.1.200:3000/urbex/acme-app-api:0.1.0

Waiting for Komodo to deploy acme-app (staging) from the GitOps repo...
Deployed acme-app (staging):
  api              http://192.168.1.210:8080  0.1.0 (192.168.1.200:3000/urbex/acme-app-api:0.1.0)
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
acme-app (staging):
  api              acme-app-api-staging             allocated=yes provisioned=yes version=0.1.0 stack=running image=192.168.1.200:3000/urbex/acme-app-api:0.1.0

DNS and TLS certificates are not tracked yet.
```

`allocated=yes` means `urbex apply` gave it a VMID/IP;
`provisioned=yes` means the LXC actually exists on Proxmox right now
(the two can disagree - e.g. right after a failed `apply`, or after a
manual deletion on Proxmox); `version` is what the GitOps repo asks for,
`stack` and `image` what Komodo reports running.

`apply` and `deploy` print the service's URL; the IP is also in the
allocation ledger in the GitOps repo:

```sh
cat ~/urbex-gitops/state/allocations.json
# {"entries":{"acme-app-api-staging":{"vmid":9100,"ip":"192.168.1.210"}}, ...}
curl http://192.168.1.210:8080/healthz
```

⚠️ There's no ingress/DNS yet: it's always `http://<ip>:<port>`.

## 4. Ship a fix or a new feature

Develop on `main` (directly or through short-lived branches and pull
requests - Urbex doesn't care), then release and deploy:

```sh
git push origin main
urbex release            # v0.1.1
urbex deploy staging     # staging now runs 0.1.1
```

Pushing to `main` builds and deploys nothing; the tag is what builds.
`urbex release` is only a convenience for it - this does the same:

```sh
git tag -a v0.1.1 -m "Release 0.1.1" && git push origin v0.1.1
```

Likewise `urbex deploy` only edits the GitOps repo. By hand:

```sh
cd ~/urbex-gitops
echo "VERSION=0.1.1" > environments/staging/acme-app/api/version.env
git commit -am "acme-app 0.1.1 on staging" && git push
```

⚠️ There's no continuous deployment of `main` to staging yet: staging
moves when you deploy a release to it.

What else changes, and where:

- **Configuration** (non-secret env vars): edit
  `environments/<env>/acme-app/api/config.env` in the GitOps repo and
  push. Komodo redeploys the service.
- **Secrets**:
  ```sh
  printf %s "$DB_PASSWORD" | urbex secret set staging api DB_PASSWORD
  ```
  encrypts it into `secrets.sops.env` next to the configuration and
  pushes; the service is redeployed with `DB_PASSWORD` in its
  environment. See the [Cookbook](#updating-a-services-config-or-resources).
- **Port, healthcheck, Dockerfile** (`urbex.yaml`): `urbex deploy <env>`
  regenerates the compose file from the manifest.
- **Infrastructure** (a new service, changed `resources`):
  ```sh
  urbex plan staging     # review the diff
  urbex apply staging    # allocates a new LXC if you added a service; re-provisions changed ones
  ```

## 5. Promote to production

Prod needs its own infrastructure first - separate LXCs from staging
(see [ADR-0009](decisions/0009-one-lxc-per-service-per-env.md)). Once:

```sh
urbex apply prod
```

Then, every time staging is good:

```sh
urbex promote
```

```
api: none -> 0.1.1
Waiting for Komodo to deploy acme-app (prod) from the GitOps repo...
Deployed acme-app (prod):
  api              http://192.168.1.220:8080  0.1.1 (192.168.1.200:3000/urbex/acme-app-api:0.1.1)
```

`promote` copies each service's version from `environments/staging` to
`environments/prod` and pushes. Production runs **the very image staging
ran** - nothing is rebuilt. Configuration and secrets are not copied:
they are per environment on purpose.

⚠️ `promote` commits to the GitOps repo directly. If production should
be gated by review, protect `environments/prod/` on Gitea and make the
change through a pull request on the GitOps repo instead.

## 6. Overall status: what's deployed where, which version, how to reach it

The GitOps repo is the answer to "what should be running":

```sh
grep -r VERSION ~/urbex-gitops/environments/
# environments/prod/acme-app/api/version.env:VERSION=0.1.1
# environments/staging/acme-app/api/version.env:VERSION=0.1.2
git -C ~/urbex-gitops log --oneline -- environments/     # the deployment history
```

What actually is running:

1. **Base services:** `urbex status`
2. **A project's services, wanted against running** - from inside each
   app repo:
   ```sh
   urbex status staging
   urbex status prod
   ```
3. **Everything at once:** Komodo's UI (`http://<komodo-ip>:9120`) lists
   every Server, Build, and Stack. ⚠️ There's no `urbex` command for a
   cross-project view yet.
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

Each takes the environment's Komodo Stacks down and deletes them,
removes the project's folder from that environment in the GitOps repo,
tears down the LXCs via `terraform destroy`, removes their Servers from
Komodo, then removes their entries from `state/allocations.json` so
`status`/`deploy` correctly stop considering them provisioned. The
project's Builds and release webhook go with its last environment:

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

Releasing and deploying need no particular machine: a tag on the
project repo, a commit to the GitOps repo. For the `urbex` commands, a
new machine, or a new Claude Code/Codex session with no prior state,
gets there like this:

1. **Clone the GitOps repo** from Gitea
   (`http://<gitea-ip>:3000/urbex/gitops.git`, as `urbex-admin`). Its
   `terraform.tfstate` is plaintext JSON today (not yet SOPS-encrypted
   as [ADR-0013](decisions/0013-terraform-state-in-gitops-repo.md)
   specifies) - that's why the repo is private.
2. **Copy `~/.urbex/credentials.yaml`** from the machine that ran
   bootstrap: besides your Proxmox token and age key, it holds the
   generated Gitea/Komodo passwords, token, and keys. Transfer it like
   any secret - the age key above all: it decrypts every secret in the
   GitOps repo. For `apply`, also make sure an SSH agent holds the
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

Commit it to `main`, then:

```sh
urbex plan staging    # the terraform plan shows only the new worker LXC - api is untouched
urbex apply staging   # new LXC, new Build, new folder and Stack for the worker
urbex release         # the first release that has a worker image
urbex deploy staging
```

`apply` allocates a new VMID/IP for `acme-app-worker-staging` only;
`api`'s existing allocation and LXC are left alone
(`allocation.Ledger.Allocate` is idempotent per hostname). Releases made
before the worker existed have no image for it, which is why `deploy`
needs a new one - it refuses a version some service was never built
for. Do the same with `urbex apply prod` before promoting.

### Rolling back a bad prod release

Deploy the previous release - its image is still in the registry, so
nothing is rebuilt:

```sh
urbex deploy prod --version 0.1.0
```

or, equivalently, revert the commit that changed
`environments/prod/.../version.env` in the GitOps repo and push. Either
way the GitOps repo's history shows the rollback.

If the bad release changed configuration or secrets too, those are
separate commits in the environment's folder: revert them as well.

### Updating a service's config or resources

Different day-2 changes, each with its place:

- **Non-secret configuration**: edit
  `environments/<env>/acme-app/api/config.env` in the GitOps repo,
  commit, push. Komodo redeploys the service. (The `env` block in
  `urbex.yaml` only seeds this file the first time an environment is
  applied.)
- **Secrets**:
  ```sh
  printf %s "$DB_PASSWORD" | urbex secret set prod api DB_PASSWORD
  urbex secret list prod api          # names only
  urbex secret unset prod api DB_PASSWORD
  ```
  The value is read from standard input, encrypted with SOPS for the
  platform's age key into `secrets.sops.env`, committed and pushed. It
  is decrypted only on the service's LXC, when Komodo deploys. With
  `URBEX_AGE_KEY` exported as `SOPS_AGE_KEY`, plain `sops
  environments/prod/acme-app/api/secrets.sops.env` edits the same file.
- **Port or healthcheck path** (`urbex.yaml`): commit the change, then
  `urbex deploy <env>` - it regenerates the compose file from the
  manifest.
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
needs it. Like any service, it is built once per release tag.

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
| No continuous deployment to staging | Step 4 | `urbex release && urbex deploy staging` after pushing to `main` |
| `promote` commits straight to the GitOps repo | Step 5 | Protect `environments/prod/` on Gitea and change it by pull request |
| Only `vX.Y.Z` tags are releases | Step 4 | No pre-release tags; use a patch version |
| A push seconds after another can be missed by Komodo | Steps 4, 5 | The `urbex` commands that wait handle it; by hand, it is picked up within 15 minutes, or run the `urbex-gitops` Procedure in Komodo |
| No fleet-wide status | Step 6 | `grep -r VERSION environments/` in the GitOps repo, `urbex status [env]` per project, or Komodo's UI |
| Frontend not deployed | Step 2 | Deploy to Cloudflare Pages/Firebase yourself |
| Terraform state unencrypted in practice | Step 1 | `terraform.tfstate` is plain JSON, not yet SOPS-encrypted as ADR-0013 specifies - the GitOps repo on Gitea is private; keep it that way |
| No cross-machine concurrency guard | Cookbook: fresh machine | Keep one GitOps repo copy in active use at a time, pulled before and pushed after every command |
| No removal of Keycloak/DNS/ingress on destroy | Cookbook: decommissioning | Nothing extra to clean up yet, since those integrations don't exist either |

These are natural next increments, roughly in the order a real deployment
would need them: DNS+ingress, then continuous deployment to staging and
promotion by pull request.
