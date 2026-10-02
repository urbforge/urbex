# Getting started

From an empty Proxmox server to a service running in production, with
every command and what it prints. The example project is **acme-app**, a
Go service called `api`. Allow an hour the first time, most of it waiting
for downloads.

If you want the ideas before the commands, read
[How Urbex works](#how-urbex-works) first; if you want every option, see
the [reference](reference/).

> ⚠️ Urbex is early-stage. Everything here has been run end to end by the
> CLI's test suite and on a real Proxmox VE 9.2 node - see
> [`status.md`](status.md) and [`known-limitations.md`](known-limitations.md).
> Gaps are called out with ⚠️.

## How Urbex works

```
 your machine (or an agent)        Proxmox
 ┌───────────────────────┐   ┌──────────────────────────────────────────┐
 │ acme-app working copy │   │ base: Gitea, Komodo, Technitium,         │
 │   urbex.yaml          │──▶│       Keycloak, Prometheus/Grafana/Loki  │
 │ urbex CLI             │   │ acme-app-api-staging   acme-app-api-prod │
 └───────────────────────┘   └──────────────────────────────────────────┘
```

- **Base services.** `urbex bootstrap` creates five LXCs: Gitea (Git
  server and container registry), Komodo (builds and deploys),
  Technitium (DNS), Keycloak (identity), and an observability stack.
- **Project repos** live on Gitea and are developed **trunk-based** on
  `main`. Every push to `main` is built by Komodo into one image per
  service, tagged with the commit (`acme-app-api:a1b2c3d`).
- **A release is a Git tag** (`v1.4.2`). It gives the commit's existing
  image the version as tag - nothing is rebuilt.
- **The GitOps repo** (also on Gitea) says what each environment runs:
  `environments/<env>/<project>/<service>/` holds the version, the
  configuration, and the SOPS-encrypted secrets. Komodo deploys a folder
  whenever it changes.
- **Staging follows `main`**: after each build of `main`, its version is
  set to the new commit, so every push is on staging within minutes.
  **Production runs releases**, set by `urbex promote`.
- **One LXC per service per environment**, each running Docker and the
  Komodo agent (Periphery).

The CLI is for the things around that loop - creating the platform,
creating environments, releasing, promoting. Day to day, a push to
`main` is enough.

## Prerequisites

On Proxmox:

- an API token (see [credentials](reference/credentials.md#proxmox-api-token)),
  with `PVEVMAdmin` on the node or on a resource pool, and `SDN.Use` on
  the bridge;
- the Debian 13 LXC template:
  ```sh
  pveam update && pveam available --section system | grep debian-13
  pveam download local debian-13-standard_13.6-1_amd64.tar.zst
  ```
- a free block of IPs on the LAN: 5 for the base services, then one per
  service per environment.

On the machine that runs `urbex` (yours, or an agent's):

- the `urbex` binary, built from a checkout of
  [`urbforge/urbex-cli`](https://github.com/urbforge/urbex-cli):
  `go build -o ~/bin/urbex ./cmd/urbex`;
- `terraform` (or `tofu`), `ansible-playbook`, `git`, `ssh`, and - for
  secrets - [`sops`](https://github.com/getsops/sops);
- an SSH key in an agent; Ansible connects to the LXCs with it:
  ```sh
  ssh-keygen -t ed25519 -f ~/.ssh/urbex -C urbex && ssh-add ~/.ssh/urbex
  ```
- an [age](https://github.com/FiloSottile/age) key, which encrypts every
  secret:
  ```sh
  age-keygen -o ~/urbex.key        # keep this file safe: it can't be recovered
  ```

## 1. Bootstrap the platform

The GitOps repo starts as an empty local directory:

```sh
urbex bootstrap --gitops-repo ~/urbex-gitops
```

```
Created /home/you/urbex-gitops/urbex.platform.yaml.
Edit it with your Proxmox/domain details, then run 'urbex bootstrap' again.
```

Edit it ([every field](reference/platform-config.md)):

```yaml
domain: acme.example
git:
  giteaUrl: https://git.acme.example
  org: urbex
proxmox:
  apiUrl: https://192.168.1.10:8006/api2/json
  insecure: true                  # Proxmox's default self-signed certificate
  node: pve
  storagePool: local-zfs
  lxcTemplate: local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst
  sshPublicKey: "ssh-ed25519 AAAA... urbex"
  pool: urbex                     # if the token is scoped to a pool
  keyctl: false                   # if the token isn't root@pam
  network:
    cidr: 192.168.1.0/24
    gateway: 192.168.1.1
    baseHostOffset: 200           # base services at .200-.204, projects from .210
    dnsServers: [192.168.1.1]     # if the Proxmox host resolves via Tailscale or a local stub
```

Then provide the two credentials Urbex can't generate, and run it again:

```sh
export URBEX_PROXMOX_TOKEN='acme@pve!urbex=xxxxxxxx-...'
export URBEX_AGE_KEY="$(grep AGE-SECRET-KEY ~/urbex.key)"
export URBEX_GITOPS_REPO=~/urbex-gitops

urbex bootstrap
```

It creates the five LXCs with Terraform, configures them with Ansible,
then wires Gitea and Komodo together:

```
Base services to provision: [urbex-gitea urbex-komodo urbex-technitium urbex-keycloak urbex-observability]
...
Base services provisioned.
Gitea ready at http://192.168.1.200:3000 (org urbex).
Komodo ready at http://192.168.1.201:9120 (builder urbex-komodo).
GitOps repo pushed to http://192.168.1.200:3000/urbex/gitops.git.
Platform ready. Gitea/Komodo admin user: urbex-admin; generated passwords and tokens are in /home/you/.urbex/credentials.yaml.
```

Both UIs are now up: Gitea on `:3000` of the first IP, Komodo on `:9120`
of the second, user `urbex-admin`, passwords in
`~/.urbex/credentials.yaml`. What exactly was created is listed in
[platform resources](reference/platform-resources.md).

Running `urbex bootstrap` again is safe: it changes nothing that is
already right.

## 2. Describe the project

In the project's repository:

```sh
cd ~/src/acme-app
urbex init --project acme-app      # writes a starter urbex.yaml
```

Edit `urbex.yaml` ([every field](reference/manifest.md)):

```yaml
apiVersion: urbex/v1
project: acme-app
services:
  - name: api
    runtime: go          # Urbex supplies the Dockerfile; or: java, python, docker
    port: 8080           # the service must listen on $PORT, set to this
    healthcheck: /healthz
    env:                 # first values of each environment's configuration
      staging:
        LOG_LEVEL: debug
      prod:
        LOG_LEVEL: info
```

```sh
urbex init                          # validates it
git add urbex.yaml && git commit -m "Add urbex manifest"
```

## 3. Create staging

```sh
urbex plan staging                  # what Terraform will create
urbex apply staging
```

`apply` creates the LXC, installs Docker and the Komodo agent on it,
creates `urbex/acme-app` on Gitea from your local `main`, declares the
project's Build and the environment's Stack in Komodo, writes
`environments/staging/acme-app/api/` in the GitOps repo - and, since
staging follows `main`, builds `main` and deploys it:

```
Created urbex/acme-app on Gitea with branch main from the local HEAD.
Building acme-app main@3f9c2e1 on Komodo...
Waiting for Komodo to deploy acme-app (staging) from the GitOps repo...
Deployed acme-app (staging):
  api              http://192.168.1.210:8080  3f9c2e1 (192.168.1.200:3000/urbex/acme-app-api:3f9c2e1)
staging follows main: every push to main is deployed here.
```

```sh
curl http://192.168.1.210:8080/healthz
```

From now on Gitea is the project's remote:

```sh
git remote add origin http://192.168.1.200:3000/urbex/acme-app.git
git fetch origin && git branch -u origin/main
```

Without Cloudflare, services are reached on their LAN IP and port; see
[Put it on the internet](cookbook.md#put-the-platform-on-the-internet)
for public HTTPS endpoints.

## 4. Push, and it's on staging

```sh
# ... change code ...
git commit -am "Better greeting"
git push
```

Nothing else. Within a minute or two Komodo has built the commit,
written it into staging's `version.env` in the GitOps repo, and deployed
it:

```sh
urbex status staging
```

```
acme-app (staging):
  api              acme-app-api-staging             allocated=yes provisioned=yes version=8d41b07(follows-main) stack=running image=192.168.1.200:3000/urbex/acme-app-api:8d41b07
```

## 5. Release and promote to production

When staging looks right, release what it runs and promote it:

```sh
urbex apply prod        # once: prod's LXC and Stack, empty until promoted
urbex release           # tags v0.1.0 on the commit staging runs
urbex promote           # prod runs v0.1.0
```

```
Releasing acme-app v0.1.0 from the commit staging runs (8d41b07).
Tagged v0.1.0 on 8d41b07; Komodo is publishing its images...
Released acme-app 0.1.0:
  api              192.168.1.200:3000/urbex/acme-app-api:0.1.0
Put it in production with 'urbex promote' (or 'urbex deploy prod').

api: none -> 0.1.0
Waiting for Komodo to deploy acme-app (prod) from the GitOps repo...
Deployed acme-app (prod):
  api              http://192.168.1.211:8080  0.1.0 (192.168.1.200:3000/urbex/acme-app-api:0.1.0)
```

The release is the image staging ran, under a second tag; promoting
writes `VERSION=0.1.0` into `environments/prod/acme-app/api/version.env`
and pushes. Prod's configuration and secrets are its own.

## 6. Configuration and secrets

Configuration lives in the GitOps repo, per environment. Edit and push:

```sh
cd ~/urbex-gitops && git pull
$EDITOR environments/prod/acme-app/api/config.env     # LOG_LEVEL=warn
git commit -am "acme-app: quieter prod logs" && git push
```

Komodo redeploys the service. Secrets go through the CLI, which encrypts
them for the platform's age key:

```sh
printf %s "$STRIPE_KEY" | urbex secret set prod api STRIPE_KEY
urbex secret list prod api
```

The service gets `STRIPE_KEY` in its environment; the GitOps repo only
ever holds it encrypted.

## Where to go from here

- [Cookbook](cookbook.md): rolling back, pinning staging, adding a
  service, decommissioning, running from another machine, and more.
- [Reference](reference/): every command, manifest field, platform
  setting, and file.
- [Architecture](architecture.md) and the
  [decision records](decisions/) for the why.
