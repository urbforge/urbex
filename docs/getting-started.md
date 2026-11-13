# Getting started

From an empty Proxmox server to an app in staging and production. This
page has what every way of doing it shares: how Urbex works, and the
prerequisites. Then pick a guide: Claude Code with the Urbex plugin,
any other AI agent, or the commands typed by you. Allow an hour the
first time, most of it spent waiting for downloads.

> ⚠️ Urbex is early-stage. Everything here has been run end to end on a
> real Proxmox VE 9.2 node - see [`status.md`](status.md) and
> [`known-limitations.md`](known-limitations.md).
>
> The CLI is open source (Apache-2.0), in
> [`urbforge/urbex-cli`](https://github.com/urbforge/urbex-cli); this
> repository, `urbforge/urbex`, holds the documentation.

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

## Prerequisites

### Required: a Proxmox VE node

- **Proxmox VE 9**, and a root shell on it **once**, to create a token
  and download the template. Run this as `root` on the node (the web
  UI's *node* → *Shell* works): it picks the storage, the bridge and the
  latest Debian 13 template itself, and prints them.
  [Credentials](reference/credentials.md#proxmox-api-token) explains each
  line and the web-UI way:
  ```sh
  STORAGE=$(pvesm status --content rootdir --enabled 1 | awk 'NR>1 && $3=="active" && $2!="dir" {print $1; exit}')
  [ -n "$STORAGE" ] || STORAGE=$(pvesm status --content rootdir --enabled 1 | awk 'NR>1 && $3=="active" {print $1; exit}')
  TEMPLATES=$(pvesm status --content vztmpl --enabled 1 | awk 'NR>1 && $3=="active" {print $1; exit}')
  BRIDGE=$(ip -o route show default | awk '{print $5; exit}')
  pveam update >/dev/null
  TEMPLATE=$(pveam available --section system | awk -v arch="$(dpkg --print-architecture)" '$2 ~ /^debian-13-standard_/ && $3 == arch {print $2}' | sort -V | tail -1)
  echo "disks on $STORAGE, templates on $TEMPLATES, bridge $BRIDGE, template $TEMPLATE"

  pveum pool add urbex --comment "Urbex"
  pveum pool modify urbex --storage "$STORAGE,$TEMPLATES"
  pveum group add urbex --comment "Urbex operators: pool urbex only"
  pveum acl modify /pool/urbex --groups urbex --roles PVEVMAdmin,PVEDatastoreUser,PVEPoolUser
  pveum acl modify "/sdn/zones/localnetwork/$BRIDGE" --groups urbex --roles PVESDNUser
  pveum user add urbex@pve --comment "Urbex CLI" --groups urbex
  pveam download "$TEMPLATES" "$TEMPLATE"
  pveum user token add urbex@pve cli --privsep 0 --comment "urbex"   # prints the token once: keep it
  ```
  The token is `urbex@pve!cli=<value>`, with the value the last command
  prints.
- **Memory and disk**: about **6 GiB of free memory** and **30 GiB of
  free disk** for the platform and a first app in two environments.
  Measured over a month on the test node (Proxmox VE 9.2, ZFS storage),
  with the platform and a three-service app in production:

  | | Memory used, at its peak | Disk used | Limits urbex sets |
  |---|---|---|---|
  | The six platform LXCs together | 4 GiB (Keycloak alone up to 1.75) | about 20 GiB (Komodo's build cache included) | 11.5 GiB memory, 79 GiB disk |
  | Each service, per environment | 0.25 GiB | 2 GiB | 1 GiB memory, 5 GiB disk (`resources`) |

  The limits aren't reserved: an LXC's memory is a ceiling, and on a
  thin storage (ZFS, LVM-thin) a disk takes only what is written on it.
  The node needs what is actually used, plus room for builds; on a
  storage that isn't thin (plain LVM), each disk takes its full size.
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

Every guide below uses the container. With the native tools, run the
same `urbex ...` commands directly, after the extra setup in
[Native tools](getting-started/with-the-cli.md#native-tools).

## Pick a guide

| Guide | For you if |
|---|---|
| [With Claude Code](getting-started/with-claude-code.md) | You use Claude Code: install the `urbex` plugin, run `/urbex:setup`, and confirm what it proposes. Then ask in plain words: "deploy to staging", "release and promote". |
| [With an AI agent](getting-started/with-an-ai-agent.md) | You use another agent that runs commands, such as Codex, or Claude Code without the plugin: you paste one prompt, it finds your network and Proxmox settings, asks you to confirm them, and sets everything up. |
| [With the CLI](getting-started/with-the-cli.md) | You want to type every command yourself and see what each does. |

Either way, two things stay yours: the commands that need root on
Proxmox (above), and the tokens, which you enter in your own terminal so
that they never go through a chat.

## Where to go from here

- [Cookbook](cookbook.md): rolling back, adding a service, putting the
  platform on the internet, running from another machine, and more.
- [Reference](reference/): every command, manifest field, platform
  setting, and file.
- [Architecture](architecture.md) and the [decision records](decisions/)
  for the why.
