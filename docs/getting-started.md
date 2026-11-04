# Getting started

From an empty Proxmox server to an app in staging and production. There
are two ways to do it: [type the commands](#path-1-step-by-step-from-the-cli)
yourself, or [let an AI agent do it](#path-2-with-an-ai-agent). Both
start from the same [prerequisites](#prerequisites). Allow an hour the
first time, most of it spent waiting for downloads.

> ⚠️ Urbex is early-stage. Everything here has been run end to end on a
> real Proxmox VE 9.2 node - see [`status.md`](status.md) and
> [`known-limitations.md`](known-limitations.md).
>
> ⚠️ The CLI's repository, [`urbforge/urbex-cli`](https://github.com/urbforge/urbex-cli),
> isn't public yet: it will be, as open source, with the first release.
> Until then, cloning it needs access to it. This repository,
> `urbforge/urbex`, is public and holds the documentation.

## Prerequisites

### Required: a Proxmox VE node

- **Proxmox VE 9**, and a root shell on it **once**, to create a token
  and download the template. These are the commands, as `root` on the
  node; [credentials](reference/credentials.md#proxmox-api-token)
  explains each line and the web-UI way:
  ```sh
  pveum pool add urbex --comment "Urbex"
  pveum pool modify urbex --storage local-zfs,local
  pveum group add urbex --comment "Urbex operators: pool urbex only"
  pveum acl modify /pool/urbex --groups urbex --roles PVEVMAdmin,PVEDatastoreUser,PVEPoolUser
  pveum acl modify /sdn/zones/localnetwork/vmbr0 --groups urbex --roles PVESDNUser
  pveum user add urbex@pve --comment "Urbex CLI" --groups urbex
  pveum user token add urbex@pve cli --privsep 0 --comment "urbex"   # prints the token once: keep it
  pveam update && pveam download local debian-13-standard_13.6-1_amd64.tar.zst
  ```
  Change `local-zfs` and `vmbr0` if your storage or bridge are named
  differently.
- **A free block of IPs on the LAN**: 10 for the platform, then one per
  service per environment.
- **A domain name.** With Cloudflare, it's your Cloudflare zone.
  Without Cloudflare, any name works: Urbex uses it for internal names
  (`*.urbex.<domain>`) and for the admin's e-mail address.

### Optional: Cloudflare

Without Cloudflare everything works on the LAN, and you reach your apps
at their IP and port. Choose one:

| | What you get | What you need |
|---|---|---|
| **Nothing** | Apps and admin tools on the LAN only | - |
| **Quick Tunnel** | A public `https://*.trycloudflare.com` address per public service | No account ([ADR-0025](decisions/0025-cloudflare-quick-tunnel.md)) |
| **Your zone** | Public HTTPS on your domain; Gitea, Komodo and the consoles behind Cloudflare Access | A Cloudflare account, the domain's zone on it, an API token ([credentials](reference/credentials.md)) |

You can add Cloudflare later: see
[Put the platform on the internet](cookbook.md#put-the-platform-on-the-internet).

### On your machine

Linux or macOS, `git`, and one of the following:

| | Install | Notes |
|---|---|---|
| **Container** (recommended) | `podman` or `docker` | Nothing else: the image has `urbex`, Terraform, Ansible, sops and age at the versions the CLI is tested with. Go isn't needed. |
| **Native** | [mise](https://mise.jdx.dev), then `mise install` in the `urbex-cli` checkout | Installs the pinned versions of Go (only to build `urbex`), Terraform, Ansible, sops and age, listed in `urbex-cli`'s `mise.toml`. Without mise, install them yourself: Go 1.26, Terraform 1.13 (or OpenTofu), `ansible-core`, `sops`, `age`, plus `ssh`. |

The steps below use the container. With the native tools, run the same
`urbex ...` commands directly, after the extra setup in
[Native tools](#native-tools).

## Path 1: step by step from the CLI

### 1. Get Urbex

```sh
git clone https://github.com/urbforge/urbex-cli.git ~/src/urbex-cli
cd ~/src/urbex-cli
tools/operator/urbex-op build           # builds the image, with urbex compiled from this checkout
ln -s "$PWD/tools/operator/urbex-op" ~/bin/urbex-op
export URBEX_WORKSPACE=~/urbex-work     # put this in your shell's profile
urbex-op init
```

`init` creates the **workspace**: one folder with the SSH key Urbex
reaches its LXCs with, the age key that encrypts every secret, the
GitOps repo and your projects. It prints the SSH public key, which you
need in step 3.

> Back up `~/urbex-work/home/age.key`: without it, the secrets can't be
> recovered.

### 2. Give it the Proxmox token

```sh
urbex-op set proxmoxToken               # paste urbex@pve!cli=<value>; it isn't echoed
urbex-op set cloudflareToken            # only if you use your Cloudflare zone
```

### 3. Create the platform

```sh
urbex-op 'urbex bootstrap'
```

The first run only writes `~/urbex-work/gitops/urbex.platform.yaml`.
Fill it in ([every field](reference/platform-config.md)):

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
  sshPublicKey: "ssh-ed25519 AAAA... urbex"   # the key init printed
  pool: urbex
  keyctl: false
  network:
    cidr: 192.168.1.0/24
    gateway: 192.168.1.1
    baseHostOffset: 200           # platform at .200 and up, projects after it
```

Then run it again:

```sh
urbex-op 'urbex bootstrap'
```

It takes about twenty minutes. It creates the platform's LXCs (Gitea,
Komodo, Technitium, Keycloak, observability, and the tunnel when
Cloudflare is configured), configures them and connects them. At the end
it prints the address of each service. The `urbex-admin` passwords are in
`~/urbex-work/home/.urbex/credentials.yaml`. Running it again is safe: it
changes nothing that is already right.

### 4. Describe your app

Put your app's repository in the workspace and add a manifest:

```sh
git clone <your app> ~/urbex-work/projects/acme-app
urbex-op 'cd /work/projects/acme-app && urbex init --project acme-app'
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
```

```sh
urbex-op 'cd /work/projects/acme-app && urbex init'    # validates it
cd ~/urbex-work/projects/acme-app && git add urbex.yaml && git commit -m "Add urbex manifest"
```

### 5. Staging

```sh
urbex-op 'cd /work/projects/acme-app && urbex apply staging'
```

It creates the LXC, the repository on Gitea from your local `main`, the
build and the deploy, then builds `main` and deploys it. It prints the
address of each service:

```
Deployed acme-app (staging):
  api              http://192.168.1.210:8080  3f9c2e1 (...)
```

Gitea is now your app's remote. Every push to `main` is built and
deployed to staging within a few minutes:

```sh
git remote add origin http://192.168.1.200:3000/urbex/acme-app.git
git fetch origin && git branch -u origin/main
git commit -am "Better greeting" && git push
urbex-op 'cd /work/projects/acme-app && urbex status staging'
```

### 6. Production

```sh
urbex-op 'cd /work/projects/acme-app && urbex apply prod'    # once: prod's LXC, empty until promoted
urbex-op 'cd /work/projects/acme-app && urbex release'       # tags v0.1.0 on the commit staging runs
urbex-op 'cd /work/projects/acme-app && urbex promote'       # prod runs the very image staging ran
```

That's it. For configuration and secrets see
[Configuration and secrets](#configuration-and-secrets) below.

### Native tools

Without the container, build `urbex` and set up what the container does
for you:

```sh
cd ~/src/urbex-cli
mise install && mise run build && mv urbex ~/bin/          # or: go build -o ~/bin/urbex ./cmd/urbex
ssh-keygen -t ed25519 -f ~/.ssh/urbex -C urbex && ssh-add ~/.ssh/urbex
age-keygen -o ~/urbex.key                                   # back it up
export URBEX_PROXMOX_TOKEN='urbex@pve!cli=<value>'
export URBEX_AGE_KEY="$(grep AGE-SECRET-KEY ~/urbex.key)"
export URBEX_GITOPS_REPO=~/urbex-gitops
urbex bootstrap
```

Then run the commands of steps 3 to 6 without `urbex-op '...'`, from
your app's folder, wherever it is. Terraform, Ansible and sops must be
on the `PATH` there: with mise, that is `mise use -g` for each tool, or a
`mise.toml` in that folder.

## Path 2: with an AI agent

An agent like Claude Code or Codex can do Path 1 for you. Two things stay
yours:

1. **The Proxmox prerequisites**: they need root on the node.
2. **The tokens**: give them to Urbex yourself, so they never go through
   the chat. After the agent has run `urbex-op init`, run
   `urbex-op set proxmoxToken` (and `cloudflareToken`) in your own
   terminal.

Start the agent in an empty folder and give it this prompt, adapted to
your app:

```text
Set up Urbex for me and deploy my app with it.

1. Clone https://github.com/urbforge/urbex and https://github.com/urbforge/urbex-cli
   side by side, then read urbex/docs/getting-started.md and follow
   "Path 1: step by step from the CLI" with the container (urbex-op).
2. After `urbex-op init`, stop and ask me to run `urbex-op set proxmoxToken`
   myself. Never ask me for a token in the chat, and never print the
   credentials file or the age key.
3. Before filling in urbex.platform.yaml, ask me for the values you
   can't know: the Proxmox URL, node, storage, bridge, the LAN's CIDR and
   gateway, the first free IP, the domain, and whether I use Cloudflare.
4. My app is <git URL or path>. Write its urbex.yaml from its code, show
   it to me, then deploy it to staging and give me its address.
5. Ask me before `urbex apply prod`, `urbex release` and `urbex promote`.
```

From then on, ask in plain words: "deploy to staging", "what runs in
prod?", "set the STRIPE_KEY secret in prod", "release and promote". The
agent finds the commands in the [CLI reference](reference/cli.md).

## Configuration and secrets

Configuration lives in the GitOps repo, per environment: edit
`environments/<env>/<project>/<service>/config.env` in
`~/urbex-work/gitops`, commit and push, and Komodo redeploys the service.
Secrets go through the CLI, which encrypts them with the platform's age
key. It reads the value on standard input, so set it from a shell in the
container:

```sh
urbex-op shell
cd /work/projects/acme-app
read -rs VALUE && printf %s "$VALUE" | urbex secret set prod api STRIPE_KEY
urbex secret list prod api
```

The service gets `STRIPE_KEY` in its environment. The GitOps repo only
ever holds it encrypted.

## How Urbex works

```
 your machine (or an agent)        Proxmox
 ┌───────────────────────┐   ┌──────────────────────────────────────────┐
 │ acme-app working copy │   │ platform: Gitea, Komodo, Technitium,     │
 │   urbex.yaml          │──▶│   Keycloak, Prometheus/Grafana/Loki      │
 │ urbex CLI             │   │ acme-app-api-staging   acme-app-api-prod │
 └───────────────────────┘   └──────────────────────────────────────────┘
```

- **The platform**: Gitea (Git and the container registry), Komodo
  (builds and deploys), Technitium (internal DNS), Keycloak (login), and
  an observability stack, each in its own LXC.
- **Your app** lives on Gitea, developed on `main`. Every push is built
  into one image per service and deployed to **staging**.
- **A release is a Git tag** (`v1.4.2`) on a commit staging ran: it gives
  that image the version, without rebuilding it. **Production runs
  releases**, set by `urbex promote`.
- **The GitOps repo** says what each environment runs: the version, the
  configuration and the encrypted secrets of every service. Komodo
  deploys whatever changes there.
- **One LXC per service per environment**, with Docker.

Day to day, a push to `main` is enough. The CLI is for what's around it:
creating the platform and the environments, releasing, promoting.

## Where to go from here

- [Cookbook](cookbook.md): rolling back, adding a service, putting the
  platform on the internet, running from another machine, and more.
- [Reference](reference/): every command, manifest field, platform
  setting, and file.
- [Architecture](architecture.md) and the [decision records](decisions/)
  for the why.
