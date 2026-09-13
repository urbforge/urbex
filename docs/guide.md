# Real-world walkthrough

A step-by-step walkthrough of the six things you'd actually do with
Urbex today, using the real `urbex` CLI (see
[`urbforge/urbex-cli`](https://github.com/urbforge/urbex-cli)) against a
worked example: **acme-app**, a personal project with a Go backend
service (`api`) and a web frontend. A [Cookbook](#cookbook-additional-scenarios)
section after it covers four more situations you'll run into:
decommissioning a project, running from a fresh machine/agent session,
adding a second service, and rolling back a bad release.

> **Read this first.** This guide is written against the CLI as it
> exists today, not the finished v1 vision in
> [`architecture.md`](architecture.md). Every place where the real
> behavior falls short of that vision is called out inline with ⚠️, and
> summarized in [Known limitations](#known-limitations-surfaced-by-this-walkthrough)
> at the end. Don't skip that section before using this for a real
> deployment.

## Prerequisites

- A running Proxmox server, reachable over the network, with an API
  token (`user@realm!tokenid=secret`).
- `terraform` (or `tofu`) and `ansible-playbook` installed on whichever
  machine runs `urbex` commands - the CLI shells out to both. Also `git`
  and `ssh` (with an agent holding the key matching
  `proxmox.sshPublicKey`, since Terraform's provider and Ansible both
  connect over SSH).
- An `age` keypair for `URBEX_AGE_KEY` (required by `urbex bootstrap`'s
  credential check even though secret encryption itself isn't wired up
  yet - see [Known limitations](#known-limitations-surfaced-by-this-walkthrough)).
- A Git host for your app repos (GitHub, GitLab, or a self-hosted
  server) and for the GitOps repo - `urbex bootstrap` creates a Gitea LXC
  but does **not** push to it yet (see
  [ADR-0006](decisions/0006-bootstrap-command.md)), so for now the
  GitOps repo is just a local directory you manage yourself.

## 1. Bootstrap the infrastructure

The GitOps repo starts as a local working directory:

```sh
urbex bootstrap --gitops-repo ~/urbex-gitops
```

First run scaffolds `~/urbex-gitops/urbex.platform.yaml` and stops.
Edit it - at minimum `proxmox.apiUrl`, `proxmox.node`, `proxmox.lxcTemplate`,
`proxmox.sshPublicKey`, `proxmox.network.cidr`/`gateway`, and `git.giteaUrl`.
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
Ansible. Re-running the same command later is safe - it's idempotent,
and aborts instead of duplicating anything if it finds a
`urbex-*`-named container Terraform doesn't know about (see
[ADR-0017](decisions/0017-embedded-base-infra-assets.md)).

⚠️ **Nothing here is reachable by name yet.** DNS registration in
Technitium isn't implemented, so note the IPs Terraform assigned - they're
in `~/urbex-gitops/terraform/base/terraform.tfstate` (encrypt this
yourself for now; see [Known limitations](#known-limitations-surfaced-by-this-walkthrough)) -
and reach the base services directly, e.g.
`ssh root@<gitea-ip>` or `http://<keycloak-ip>:8080`.

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
urbex apply staging                     # creates the LXC, installs Docker, starts compose
```

⚠️ **The container that starts has no real image yet.** `apply` renders
`/opt/urbex/docker-compose.yml` on the new LXC referencing a placeholder
`acme-app/api:staging-latest`, since building/pushing an image from
your Dockerfile or source is not implemented (tracked alongside `urbex
deploy` - see the TODO in
[`docker-compose.yml.j2`](https://github.com/urbforge/urbex-cli/blob/main/platform/ansible/roles/service/templates/docker-compose.yml.j2)
in `urbex-cli`). `docker compose up -d` will fail to pull it. Today,
close this gap yourself: build and push your image under that exact
name/tag to a registry the LXC can reach, or SSH in and edit
`docker-compose.yml` directly, then `docker compose up -d`.

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

`allocated=yes` means `urbex apply` gave it a VMID/IP;
`provisioned=yes` means the LXC actually exists on Proxmox right now
(the two can disagree - e.g. right after a failed `apply`, or after a
manual deletion on Proxmox).

⚠️ **`status` doesn't print the IP or port**, only presence. Get the IP
from the allocation ledger in the GitOps repo:

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
urbex apply prod       # same "placeholder image" caveat as staging - resolve it there too
urbex promote
```

`promote` tags HEAD of the `acme-app` repo (`v0.1.0`, auto-incrementing
the patch version on each subsequent call), pushes the tag, then
immediately redeploys prod itself:

```
Tagged and pushed v0.1.0.
Redeployed acme-app (prod).
Note: this ran ansible-playbook directly against the existing LXCs - it is
not yet integrated with Komodo's GitOps reconciliation (docs/decisions/0004-gitops-gitea-komodo.md).
Promoted v0.1.0 to prod.
```

⚠️ That note is the key thing to understand about `promote` today: per
[ADR-0010](decisions/0010-promotion-flow.md), pushing a tag is supposed
to be *the* trigger - Komodo watches for it and redeploys prod on its
own. Since that integration doesn't exist yet, `urbex promote` fakes it
by calling the same direct-Ansible redeploy `urbex deploy` uses,
immediately, from your machine. The tag it pushes is real Git history;
the automatic reaction to it is not real yet.

Use `--skip-deploy` to only create/push the tag without the immediate
redeploy (closer to the eventual behavior, but nothing will pick it up
until Komodo integration exists).

## 5. Ship a fix or a new feature

Make your change, then:

- **App code only** (same service, same resources): commit, push to
  `main`, then
  ```sh
  urbex deploy staging
  ```
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
3. **Which version is deployed where** - ⚠️ not tracked by Urbex at all
   yet. The compose file's image tag is always the placeholder
   `<project>/<service>:<env>-latest` regardless of what was actually
   promoted; there's no record linking a `urbex promote` tag to what's
   currently running. For now, cross-reference manually:
   ```sh
   git -C /path/to/acme-app tag --list      # every version ever promoted
   git -C /path/to/acme-app log -1 --oneline main   # what's on staging (last push)
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

Since `urbex bootstrap` doesn't push the GitOps repo to Gitea yet (see
[Known limitations](#known-limitations-surfaced-by-this-walkthrough)),
"the GitOps repo" is only as durable as wherever you put it - there's
nothing to `git clone` from a server by default. To run commands from a
different machine, or from a new Claude Code/Codex session with no prior
state:

1. **Make the GitOps repo directory reachable.** Put it under your own
   Git remote and clone it, or `rsync`/`scp` the directory as-is. Its
   `terraform.tfstate` is plaintext JSON today (not yet SOPS-encrypted
   as [ADR-0013](decisions/0013-terraform-state-in-gitops-repo.md)
   specifies) - treat the whole directory like a secret in transit and
   at rest.
2. **Recreate credentials on the new machine**: export
   `URBEX_PROXMOX_TOKEN` and `URBEX_AGE_KEY` (or write
   `~/.urbex/credentials.yaml`), and make sure an SSH agent holds the
   private key matching `proxmox.sshPublicKey` in `urbex.platform.yaml` -
   both Terraform's provider and Ansible connect over SSH.
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

⚠️ There's no `urbex rollback` command, and since image builds/pushes
aren't automated yet (see
[Known limitations](#known-limitations-surfaced-by-this-walkthrough)),
"rollback" today really means "get the compose file back to whatever the
previous good version looked like." Two honest options:

1. If you edited `docker-compose.yml` on the LXC by hand for the
   previous version, SSH in and revert it, then `docker compose up -d`
   yourself.
2. If you've only ever used `urbex deploy`/`urbex promote`: `git
   checkout` the previous tag in the app repo, then re-run `urbex deploy
   prod`. This only actually helps if `urbex.yaml` itself was unchanged
   between the two versions - `deploy` re-renders the inventory from the
   **current** `urbex.yaml` on disk, not from Git history, so it can't
   reconstruct an older manifest's shape for you.

A real rollback needs the deployed-version tracking gap below closed
first - today, "which version is live" is something you have to remember
yourself.

## Known limitations surfaced by this walkthrough

Everything below is tracked as unimplemented in
[`urbforge/urbex-cli`](https://github.com/urbforge/urbex-cli)'s README
and the relevant ADRs; listed together here because this walkthrough is
where they actually bite:

| Gap | Where it shows up | Workaround today |
|---|---|---|
| No image build/push | `apply`/`deploy` | Build and push manually under the exact placeholder name, or edit `docker-compose.yml` on the LXC by hand |
| No DNS/ingress/TLS | Steps 3, 4, 6 | Reach services by IP from `state/allocations.json` |
| No Komodo integration | Steps 4, 5 | `urbex deploy`/`urbex promote` redeploy directly instead of reacting to Git |
| No deployed-version tracking | Step 6 | Cross-reference `git tag`/`git log` with what you last ran `deploy`/`promote` against manually |
| No fleet-wide status | Step 6 | Run `urbex status [env]` per project, per environment |
| GitOps repo not pushed to Gitea | Step 1 onward | The "GitOps repo" is just a local directory you manage (and should back up / put under your own Git remote) |
| Terraform state unencrypted in practice | Step 1 | `terraform.tfstate` is plain JSON on disk today, not yet SOPS-encrypted as ADR-0013 specifies - keep the GitOps repo private and access-controlled |
| No cross-machine concurrency guard | Cookbook: fresh machine | Keep one GitOps repo copy in active use at a time, pulled before and pushed after every command |
| No rollback command, no removal of Keycloak/DNS/ingress on destroy | Cookbook: rollback, decommissioning | Manual compose/tag surgery for rollback; nothing extra to clean up yet since those integrations don't exist either |

These are natural next increments, roughly in the order a real deployment
would need them: image build/push, then DNS+ingress, then Komodo
integration and version tracking.
