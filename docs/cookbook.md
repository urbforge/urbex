# Cookbook

Recipes for what you do with Urbex after [getting started](getting-started.md).
Each one says what to run and what happens; details of every command are in
the [CLI reference](reference/cli.md), of every file in
[the GitOps repo reference](reference/gitops-repo.md).

The examples use project `acme-app` with a service `api`, Gitea at
`192.168.1.200:3000`, and `URBEX_GITOPS_REPO` pointing at your working
copy of the GitOps repo.

**Shipping**

- [Ship a change to staging](#ship-a-change-to-staging)
- [Release and promote to production](#release-and-promote-to-production)
- [Release by hand with git](#release-by-hand-with-git)
- [Release something other than what staging runs](#release-something-other-than-what-staging-runs)
- [Fix production quickly](#fix-production-quickly)
- [Roll back production](#roll-back-production)
- [Hold staging on a version, then follow main again](#hold-staging-on-a-version-then-follow-main-again)
- [Deploy a specific commit](#deploy-a-specific-commit)
- [Gate production behind a pull request](#gate-production-behind-a-pull-request)

**On the internet**

- [Put the platform on the internet](#put-the-platform-on-the-internet)
- [Publish a service](#publish-a-service)
- [Deploy a web frontend](#deploy-a-web-frontend)
- [Let someone else into Gitea and Komodo](#let-someone-else-into-gitea-and-komodo)

**Configuration and secrets**

- [Change configuration](#change-configuration)
- [Add, rotate, or remove a secret](#add-rotate-or-remove-a-secret)
- [Edit secrets with sops directly](#edit-secrets-with-sops-directly)

**Shape of a project**

- [Add a service](#add-a-service)
- [Use your own Dockerfile](#use-your-own-dockerfile)
- [Several services in one repo](#several-services-in-one-repo)
- [Change a port or the healthcheck](#change-a-port-or-the-healthcheck)
- [Give a service more CPU, memory, or disk](#give-a-service-more-cpu-memory-or-disk)
- [Several projects on one platform](#several-projects-on-one-platform)
- [Decommission an environment or a project](#decommission-an-environment-or-a-project)
- [Remove the whole platform](#remove-the-whole-platform)

**Operating**

- [Find every endpoint](#find-every-endpoint)
- [See what runs where](#see-what-runs-where)
- [Read logs, watch resources](#read-logs-watch-resources)
- [Run urbex from a container](#run-urbex-from-a-container)
- [Run urbex from another machine or a new agent session](#run-urbex-from-another-machine-or-a-new-agent-session)
- [A push didn't deploy](#a-push-didnt-deploy)
- [A build or a deploy failed](#a-build-or-a-deploy-failed)
- [An LXC was recreated](#an-lxc-was-recreated)
- [Bootstrap was interrupted](#bootstrap-was-interrupted)
- [Ansible refuses an LXC: host key changed](#ansible-refuses-an-lxc-host-key-changed)
- [The LXCs can't resolve names](#the-lxcs-cant-resolve-names)
- [Drive Urbex from an LLM agent](#drive-urbex-from-an-llm-agent)
- [Known limitations and workarounds](#known-limitations-and-workarounds)

---

## Ship a change to staging

```sh
git commit -am "Paginate the orders endpoint"
git push origin main
```

That's all. Komodo builds the commit (`acme-app-api:<short hash>`), sets
staging to it with a commit to the GitOps repo, and deploys it, usually
within a couple of minutes. Watch it with:

```sh
urbex status staging
```

or in Komodo's UI: the `urbex-release` Action run, then the
`acme-app-api-staging` Stack.

Branches and pull requests on the project repo work as usual - only what
lands on `main` is built.

## Release and promote to production

```sh
urbex release      # v0.4.0 on the commit staging runs
urbex promote      # prod runs v0.4.0
```

`release` picks the next patch version (`--version v0.5.0` for another)
and tags **the commit staging runs**, so the release is exactly what was
tested. Komodo publishes that commit's images under the version - no
rebuild. `promote` finds the release on staging's commit and writes it
into prod's version files.

If staging runs a commit that isn't released, `promote` refuses and says
so: release first.

## Release by hand with git

A release is just a tag, so this is equivalent to `urbex release`:

```sh
git tag -a v0.4.0 -m "Release 0.4.0" 3f9c2e1   # the commit staging runs
git push origin v0.4.0
```

Only `vMAJOR.MINOR.PATCH` tags are releases; anything else
(`v1.0.0-rc.1`, `nightly`) is ignored. `urbex status staging` shows the
commit staging runs.

## Release something other than what staging runs

```sh
urbex release --ref main          # main's head, built or not
urbex release --ref 3f9c2e1       # any commit
urbex release --ref v0.3.0        # e.g. re-tag an existing release
```

If `main` never built that commit (a tag on an old commit, say), Komodo
builds it first; the release takes a minute longer.

## Fix production quickly

Trunk-based: the fix goes on `main` like any change, then is released and
promoted.

```sh
git commit -am "Fix the null total on refunds" && git push
urbex status staging              # wait until staging runs the fix
urbex release && urbex promote
```

If `main` has moved on with things that must not reach production yet,
release the fix's commit explicitly and deploy it to prod:

```sh
urbex release --ref <fix-commit>
urbex deploy prod --version 0.4.1
```

## Roll back production

```sh
urbex deploy prod --version 0.3.2
```

The image of every release stays in the registry, so this is a commit to
the GitOps repo and a redeploy - no build. Equivalently, revert the
commit that changed `environments/prod/acme-app/*/version.env` and push.

If the bad release also changed configuration or secrets, those were
separate commits to prod's folder: revert them too.

## Hold staging on a version, then follow main again

To test something on staging without every push replacing it:

```sh
urbex deploy staging --version 0.4.0      # a release, or a commit hash
```

Deploying a version removes the `TRACK=main` line from staging's version
files, so pushes to `main` are still built but no longer deployed there.
To resume:

```sh
urbex deploy staging --follow-main        # back on main's head, and following it
```

## Deploy a specific commit

Every commit pushed to `main` has an image tagged with its short hash:

```sh
urbex deploy staging --version 8d41b07
```

Production only ever gets releases from `urbex promote`; `urbex deploy
prod --version <commit>` works, but skips the release - avoid it.

## Gate production behind a pull request

`urbex promote` and `urbex deploy prod` commit straight to the GitOps
repo. To have production changes reviewed instead:

1. In Gitea, add a branch protection rule on `main` of `urbex/gitops`
   with **protected file patterns** `environments/prod/**`: direct
   pushes touching prod are refused, pull requests are not. Staging,
   which Komodo and `urbex` update directly, keeps working.
2. Change prod in a branch and open a pull request:
   ```sh
   cd ~/urbex-gitops && git pull && git switch -c promote-0.4.0
   sed -i 's/^VERSION=.*/VERSION=0.4.0/' environments/prod/acme-app/*/version.env
   git commit -am "acme-app 0.4.0 to prod" && git push -u origin promote-0.4.0
   ```
3. Merging it deploys: Komodo deploys what lands on `main`.

## Put the platform on the internet

With a domain on Cloudflare, add to `urbex.platform.yaml`:

```yaml
domain: example.com          # the Cloudflare zone
cloudflare:
  accountId: <account id>
  zoneId: <zone id of example.com>
  access:
    emails: [you@example.com]
```

then, with a token with the [permissions it needs](reference/credentials.md#cloudflare-api-token):

```sh
export URBEX_CLOUDFLARE_TOKEN=...
urbex bootstrap
```

```
Published on Cloudflare: Keycloak https://auth-urbex.example.com, Gitea https://git-urbex.example.com and Komodo https://komodo-urbex.example.com (behind Access), webhooks https://hooks-urbex.example.com.
```

Bootstrap adds a small LXC running `cloudflared`, sets up Access first
(the one-time PIN login if missing, a policy for the listed e-mails, an
application per protected service), then routes and DNS. Nothing on the
Proxmox side is opened to the internet. Names are one level under the
zone (`auth-urbex`), which Cloudflare's free certificate covers; with
Advanced Certificate Manager, `cloudflare.hostnames: nested` gives
`auth.urbex.example.com` instead.

## Publish a service

```yaml
# urbex.yaml
services:
  - name: api
    runtime: go
    port: 8080
    public: true
```

```sh
urbex apply staging     # https://api-staging-acme-app-urbex.example.com
urbex apply prod        # https://api-acme-app-urbex.example.com
```

The service's own authentication is its gate (Keycloak, at
`https://auth-urbex.example.com`, once realms are wired). Set `public:
false` and apply again to take it off the internet.

## Deploy a web frontend

```yaml
# urbex.yaml
frontend:
  type: web
  provider: cloudflare-pages
  buildCommand: npm ci && npm run build
  outputDir: dist
```

```sh
git commit -am "Add the frontend" && git push
urbex apply staging
```

The frontend is built with every push to `main`, like the services, and
staging serves it at `https://staging-acme-app-urbex.example.com`.
`urbex release` and `urbex promote` put the same build on
`https://acme-app-urbex.example.com`; `urbex deploy prod --version 0.3.0`
rolls it back. Each environment is a Cloudflare Worker with static
assets, `urbex-acme-app-web-<env>`; unknown paths serve `index.html`.

## Let someone else into Gitea and Komodo

Add their e-mail to `cloudflare.access.emails` and run `urbex bootstrap`.
They open `https://git-urbex.example.com`, enter the address, and get a
PIN by e-mail. That opens the door; Gitea and Komodo still ask for their
own login (`urbex-admin`, or accounts you create in them).

## Change configuration

Each environment's non-secret configuration is a dotenv file in the
GitOps repo:

```sh
cd $URBEX_GITOPS_REPO && git pull
$EDITOR environments/staging/acme-app/api/config.env
git commit -am "acme-app staging: enable the new checkout" && git push
```

Komodo redeploys the service with it. `urbex.yaml`'s `env` block only
provides the first version of this file, when the environment is created;
editing it later changes nothing.

> ⚠️ Komodo can miss a push that lands within a few seconds of another
> one (it caches the repo briefly). It catches up within 15 minutes; see
> [A push didn't deploy](#a-push-didnt-deploy) to do it right away.

## Add, rotate, or remove a secret

```sh
printf %s "$DB_PASSWORD" | urbex secret set prod api DB_PASSWORD   # add or rotate
urbex secret list prod api                                         # names only
urbex secret unset prod api DB_PASSWORD
```

The value is read from standard input (never from the command line),
encrypted with SOPS for the platform's age key into
`environments/prod/acme-app/api/secrets.sops.env`, committed, and pushed;
the service is redeployed with the new value in its environment. Needs
`sops` and `URBEX_AGE_KEY`.

Secrets are per environment: setting one in staging doesn't set it in
prod.

## Edit secrets with sops directly

The files are ordinary SOPS dotenv files, encrypted according to the
repo's `.sops.yaml`:

```sh
export SOPS_AGE_KEY="$URBEX_AGE_KEY"
cd $URBEX_GITOPS_REPO && git pull
sops environments/prod/acme-app/api/secrets.sops.env    # opens the decrypted file in $EDITOR
git commit -am "acme-app prod: rotate DB_PASSWORD" && git push
```

A service with no secrets has a placeholder file (a comment, not
encrypted); `urbex secret set` replaces it. Don't delete the file - the
Stack expects it.

## Add a service

```yaml
# urbex.yaml
services:
  - name: api
    runtime: go
    port: 8080
  - name: worker
    runtime: go
    port: 9000
```

```sh
git commit -am "Add the worker" && git push
urbex apply staging      # a new LXC, Build, folder, and Stack for the worker
```

The other services are untouched. Staging then runs the worker built from
`main`. For prod, `urbex apply prod`, then release and promote as usual -
releases made before the worker existed have no image for it.

## Use your own Dockerfile

```yaml
services:
  - name: web
    runtime: docker
    dockerfile: ./web/Dockerfile      # built with ./web as context
    port: 3000
    healthcheck: /health
```

The container gets `PORT` set to `port`; a healthcheck runs `wget` inside
the container, so the image needs it.

## Several services in one repo

For Go, `./cmd/<service>` is built if it exists, so one module can hold
several services:

```
acme-app/
  go.mod
  cmd/api/main.go
  cmd/worker/main.go
```

For other languages, give each service its own Dockerfile
(`runtime: docker`). See [runtimes](reference/manifest.md#runtimes).

## Change a port or the healthcheck

Edit `urbex.yaml`, commit, then regenerate the compose files:

```sh
urbex deploy staging --follow-main     # staging: regenerate and keep following main
urbex deploy prod --version 0.4.0      # prod: regenerate at its current release
```

`deploy` rewrites `compose.yaml` in each service's folder from the
manifest. A changed port is also where the service is reached:
`http://<ip>:<new port>`.

## Give a service more CPU, memory, or disk

```yaml
services:
  - name: api
    resources: { cpu: 2, memory: 2Gi, disk: 20Gi }
```

```sh
urbex plan prod      # read the plan: a disk change may replace the LXC
urbex apply prod
```

CPU and memory change in place; growing a disk usually does too, but
read the plan. If the LXC is replaced, `apply` redeploys onto it.

## Several projects on one platform

Nothing special: run `urbex apply` from each project's repo with the same
`URBEX_GITOPS_REPO`. Each gets its own LXCs (names
`<project>-<service>-<env>`), addresses from one shared ledger, and its
own folders under `environments/`.

## Decommission an environment or a project

```sh
urbex destroy staging
urbex destroy prod
```

Each takes the environment's containers down, deletes its Stacks and
folders, destroys its LXCs, and frees their addresses. With the last
environment gone, the project's Builds and webhook go too. The repo and
its images stay on Gitea - delete them there if you want them gone.

## Remove the whole platform

First every project's environments, then the platform:

```sh
cd ~/src/acme-app && urbex destroy staging && urbex destroy prod   # each project
urbex teardown            # says what it will destroy and lose
urbex teardown --yes      # destroys the base-service LXCs
```

`teardown` refuses while any project environment exists. It destroys
Gitea's LXC, and with it every repository and image there: make sure
project repos are pushed somewhere else first. Afterwards the GitOps
repo's working copy is the only copy left - keep it - and
`~/.urbex/credentials.yaml` keeps only what you provided. `urbex
bootstrap` builds a new platform from that working copy.

## Find every endpoint

```sh
urbex status                 # the platform
urbex status staging         # a project's environment, from its folder
```

`urbex status` lists every address of the platform - Gitea, Komodo and
its webhooks, Keycloak, Technitium, Grafana, Prometheus, Loki - on the
LAN and, with Cloudflare, on the internet, and where the logins are.
`urbex status <env>` lists, after each service's state, its LAN address
and, if it is public or the web frontend, its HTTPS address. Both are
computed from `urbex.platform.yaml` and the address ledger in the GitOps
repo; `urbex apply` and `urbex deploy` print a project's addresses too.

The names follow fixed rules (see
[public hostnames](reference/platform-config.md#public-hostnames)): with
the default `flat` names under `example.com`,

| | Address |
|---|---|
| Keycloak / Gitea / Komodo | `https://auth-urbex.example.com`, `git-urbex`, `komodo-urbex` |
| An API, staging / prod | `https://api-staging-acme-app-urbex.example.com`, `https://api-acme-app-urbex.example.com` |
| The web frontend, staging / prod | `https://staging-acme-app-urbex.example.com`, `https://acme-app-urbex.example.com` |
| A service on the LAN | `http://<its LXC's IP>:<port>` - `state/allocations.json` in the GitOps repo |

## See what runs where

```sh
grep -r '^VERSION' $URBEX_GITOPS_REPO/environments/     # what should run
urbex status staging                                    # wanted vs running, per service
git -C $URBEX_GITOPS_REPO log --oneline -- environments/   # every deploy, ever
```

Komodo's UI shows every Stack, Build, and their logs, across projects.

## Read logs, watch resources

Every LXC sends its service's logs to Loki and its CPU, memory, disk and
network to Prometheus ([ADR-0023](decisions/0023-service-logs-to-loki.md)),
labelled `kind="platform"` for the base services (Gitea, Komodo,
Keycloak, Technitium, observability, tunnel) and `kind="app"` for the
projects' services, which also carry `project` and `env`.

In Grafana - its address and login are in `urbex status` - open
*Dashboards → Urbex*:

- **Urbex logs**: pick the kind, project, environment and service, or
  search a text;
- **Urbex resources**: a table of every LXC's current CPU, memory and
  disk, and their history, with the same filters.

In *Explore*, LogQL and PromQL work on the same labels:

```logql
{kind="app", project="acme-app", env="prod"} |= "error"
{kind="platform", service="komodo"}
```

```promql
100 * (1 - node_memory_MemAvailable_bytes{kind="app", project="acme-app"} / node_memory_MemTotal_bytes{kind="app", project="acme-app"})
# CPU %: busy time over the CPUs (the idle counter is unreliable in an LXC)
100 * sum by (host) (rate(node_cpu_seconds_total{mode!~"idle|iowait|steal", kind="platform"}[5m])) / count by (host) (node_cpu_seconds_total{mode="idle", kind="platform"})
```

From a terminal, Loki's API:

```sh
curl -s -G http://<observability IP>:3100/loki/api/v1/query_range \
  --data-urlencode 'query={project="acme-app", service="api", env="staging"}' | jq -r '.data.result[].values[][1]'
```

A service logs what it writes to stdout and stderr: an API that gets no
requests has nothing new to show, and a web frontend's requests never
reach Loki - Cloudflare serves them from the Worker (its logs are in the
Cloudflare dashboard, *Workers & Pages → the Worker → Logs*). Keycloak
logs every request and every login (`type="LOGIN"`, `type="LOGIN_ERROR"`):

```logql
{kind="platform", service="keycloak"} |= "type=\"LOGIN"
```

The dashboards look at the last 6 hours by default; widen the time range
to see older lines.

The logs are also where they always were: `docker logs` on the LXC, and
the Stack's page in Komodo. To keep a project's logs out of Loki, set
`observability.logs: false` in `urbex.yaml` and run `urbex apply <env>`;
its resource metrics are still collected.

## Run urbex from a container

Rather than installing `terraform`, `ansible-playbook`, `sops` and the
rest, run `urbex` with `tools/operator/urbex-op` from `urbforge/urbex-cli`
(podman or docker). It works on a **workspace**: one folder with the
credentials, the SSH and age keys, the GitOps repo and your projects.

```sh
cd urbex-cli
tools/operator/urbex-op build                     # the image, with urbex built from the checkout
tools/operator/urbex-op -w ~/urbex-work init      # SSH key, age key, folders
tools/operator/urbex-op -w ~/urbex-work set proxmoxToken   # stored in the workspace (or export URBEX_PROXMOX_TOKEN)
tools/operator/urbex-op -w ~/urbex-work 'urbex bootstrap'
tools/operator/urbex-op -w ~/urbex-work 'cd /work/projects/acme-app && urbex apply staging'
tools/operator/urbex-op -w ~/urbex-work shell     # an interactive shell
```

The workspace is `/work` in the container (`$HOME` is `/work/home`, the
GitOps repo `/work/gitops`). Details in `tools/operator/README.md`.

## Run urbex from another machine or a new agent session

1. Clone the GitOps repo:
   `git clone http://192.168.1.200:3000/urbex/gitops.git ~/urbex-gitops`
   (user `urbex-admin`).
2. Copy `~/.urbex/credentials.yaml` from the machine that ran bootstrap -
   it holds the Proxmox token, the age key, and everything bootstrap
   generated. Treat it like a password manager export.
3. For `apply`, `plan`, and `destroy`: load the SSH key
   (`ssh-add ~/.ssh/urbex`) and install `terraform` and `ansible`.
4. `export URBEX_GITOPS_REPO=~/urbex-gitops`.

`release`, `deploy`, `promote`, `secret`, and `status` only need step 1,
2, and 4.

## A push didn't deploy

Komodo deploys on the GitOps repo's webhook - but it caches a repo for a
few seconds after reading it, so a push that lands right after another
can go unnoticed until the scheduled run, at most 15 minutes later. To
deploy now, run the `urbex-gitops` Procedure in Komodo's UI, or:

```sh
urbex deploy staging --follow-main      # or: urbex deploy <env> --version <its version>
```

The `urbex` commands themselves account for this; it only concerns pushes
made by hand.

## A build or a deploy failed

- **Build:** Komodo → Actions → `urbex-release` shows the run for the
  push or tag; Builds → `acme-app-api` shows the build log (clone,
  Dockerfile, push).
- **Deploy:** Komodo → Stacks → `acme-app-api-staging` → its latest
  update (pull, `docker compose up`); the container's own logs are on the
  Stack page.
- `urbex deploy`, `promote`, `release` and `apply` wait for the result and
  print the failing step when they can.

Common causes: the build fails (the Dockerfile, or the conventions of a
[runtime](reference/manifest.md#runtimes)); the service doesn't listen
on `$PORT`; the healthcheck path is wrong, so the container stays
unhealthy and `urbex` keeps waiting until it times out.

To redo a release whose Action run failed, delete the tag in Gitea and
create it again (`urbex release --version <same> --ref <commit>`). A tag
pushed while `main` is still building that commit is fine: runs of the
Action queue up.

## An LXC was recreated

When an LXC is destroyed and created again under the same name - `urbex
destroy` then `apply`, or Terraform replacing it - its Komodo agent comes
back with a new identity. `urbex apply` notices, accepts it, and says
so:

```
Komodo server acme-app-api-staging reconnected with a new key (its LXC was recreated): accepted.
```

## Bootstrap was interrupted

Run `urbex bootstrap` again: Terraform resumes from its state, Ansible
skips what's done, and secrets already generated are kept. If it stops
with `found existing Proxmox container(s) ... not tracked`, it found
`urbex-*` containers that the GitOps repo you pointed it at doesn't know
about: point `--gitops-repo` at the right one, or remove the stray
containers.

## Ansible refuses an LXC: host key changed

Symptom: `bootstrap` or `apply` fails with `REMOTE HOST IDENTIFICATION
HAS CHANGED` for an LXC's address. The LXC at that address isn't the one
whose key is recorded in the GitOps repo's `state/known_hosts`. `urbex`
handles the LXCs it creates and destroys itself; this happens when one
was replaced some other way (by hand in Proxmox, or by Terraform when a
change forces it). If you know why it changed, forget the old key and
run the command again:

```sh
ssh-keygen -f $URBEX_GITOPS_REPO/state/known_hosts -R 192.168.1.210
```

If you don't, find out first: that is what the check is for.

## The LXCs can't resolve names

Symptom: `bootstrap` or `apply` fails in Ansible with `Failed to update
apt cache`, while the LXCs can ping the internet. They copied the
Proxmox host's `resolv.conf`, and the host resolves through something
they can't reach - typically Tailscale's MagicDNS (`100.100.100.100`).
Give them a resolver on the LAN in `urbex.platform.yaml`:

```yaml
proxmox:
  network:
    dnsServers: [192.168.1.1]
```

and run `urbex bootstrap` (or `urbex apply <env>`) again: Terraform
updates the LXCs and Ansible picks up where it stopped.

## Drive Urbex from an LLM agent

The CLI is built for it: plain output, every command idempotent or
explicit about what it changes, nothing interactive. A minimal briefing
for an agent working on a project:

> This project is deployed with Urbex. Push to `main` deploys to staging
> automatically; check with `urbex status staging`. To ship to
> production: `urbex release && urbex promote`. Configuration and secrets
> are per environment in the GitOps repo (`$URBEX_GITOPS_REPO`); set
> secrets with `printf %s "$VALUE" | urbex secret set <env> <service> KEY`.
> Never edit `compose.yaml` there; change `urbex.yaml` and run
> `urbex deploy <env>`.

Give the agent the credentials file only if it should be able to deploy
to production.

## Known limitations and workarounds

They are all in [`known-limitations.md`](known-limitations.md), each
with what to do meanwhile.
