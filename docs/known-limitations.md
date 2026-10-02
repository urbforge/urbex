# Known limitations

Everything Urbex doesn't do yet, or does with a catch, in one place - with
what to do meanwhile. What *is* supported, and the priorities, are in
[`status.md`](status.md); planned work is in [`roadmap.md`](roadmap.md).
Last reviewed: 2026-10-02, after the validation on a real Proxmox VE 9.2
node and Cloudflare account.

- [Platform](#platform)
- [Projects and deploys](#projects-and-deploys)
- [Public endpoints (Cloudflare)](#public-endpoints-cloudflare)
- [Frontends](#frontends)
- [Identity, DNS, observability](#identity-dns-observability)
- [Operations and security](#operations-and-security)

## Platform

| Limitation | Workaround / consequence |
|---|---|
| **One Proxmox node.** Every LXC is created on `proxmox.node`; no clusters, no HA, no other providers (cloud providers are v2+). | - |
| **Addresses aren't checked or reserved.** Urbex takes static IPs from `proxmox.network` (base services from `baseHostOffset`, projects 10 after) without checking they're free; a DHCP server can hand them out too. | Keep the block out of the DHCP range. |
| **LXCs copy the Proxmox host's DNS** unless `proxmox.network.dnsServers` is set; a host resolving through Tailscale's MagicDNS breaks them. | Set `dnsServers` to a LAN resolver. |
| **`keyctl` needs `root@pam`.** With a pool-scoped token, `proxmox.keyctl: false`. Docker has worked without it on Proxmox 9.2; other hosts may need it. | An administrator enables it per LXC: `pct set <vmid> --features nesting=1,keyctl=1`. |
| **Per-project Proxmox isolation** (resource pool, user group, technical users per project) isn't implemented: every LXC goes in the platform's pool, managed with the operator's token. | Planned ([roadmap](roadmap.md)). |
| **Keycloak becomes reachable ~4 minutes after** `urbex bootstrap` reports "Platform ready": it runs in development mode and rebuilds itself when its configuration changes. | Wait; production mode is planned with realm provisioning. |
| **Base-service images** of Technitium, Prometheus, Loki and Grafana use `latest`. | - |
| **`urbex teardown` destroys Gitea**, with every repository and image on it. | Keep project repos pushed elsewhere too. The GitOps repo survives as the local working copy: keep it. |
| **Rotating generated credentials isn't supported**: bootstrap keeps every value in `~/.urbex/credentials.yaml`, and changing one by hand (the Komodo database password, say) can break the service. | Only by rebuilding the platform: `urbex teardown` then `urbex bootstrap`. |

## Projects and deploys

| Limitation | Workaround / consequence |
|---|---|
| **Only `vX.Y.Z` tags are releases**: no pre-releases (`-rc.1`). | Staging runs every commit of `main`; release a patch version. |
| **`urbex promote` commits straight to the GitOps repo.** | [Gate production behind a pull request](cookbook.md#gate-production-behind-a-pull-request) with Gitea's protected file patterns. |
| **Komodo can miss a push** made within ~5 seconds of the previous one (it caches the repo); the scheduled run catches up within 15 minutes. | The `urbex` commands handle it; by hand, run the `urbex-gitops` Procedure. |
| **Every push to `main` is built**, documentation-only ones included, and **images are never pruned.** | Delete old ones in Gitea, under the organization's *Packages*. |
| **Removing a service from `urbex.yaml`** leaves its LXC, Stack, folder and routes. | `urbex destroy <env>` before removing it, or remove them by hand. |
| **Changing a port or healthcheck** needs `urbex deploy <env>` (it regenerates the compose files); configuration in `urbex.yaml`'s `env` only seeds `config.env` once. | Edit `config.env` in the GitOps repo afterwards. |
| **No concurrency guard across machines** on the Terraform state and the address ledger. | Don't run `plan`, `apply`, `destroy` from two machines at once. |
| **Terraform state isn't encrypted** (it holds no secrets). | Keep the GitOps repo private. |

## Public endpoints (Cloudflare)

| Limitation | Workaround / consequence |
|---|---|
| **`nested` hostnames need Advanced Certificate Manager**, which Urbex doesn't enable or order certificates for. | Use the default `flat` names, or enable ACM and order the wildcard certificates by hand. |
| **Public names are derived** from the project's and services' names; `domain.subdomain` in the manifest isn't used. | - |
| **Gitea and Komodo behind Access are for browsers.** `git` and the CLI keep using the LAN addresses, and the links Gitea and Komodo generate are LAN ones (Gitea's registry needs its LAN `ROOT_URL`). | Use the LAN, or a VPN, for git and the CLI. |
| **Access allows a list of e-mail addresses** with a one-time PIN; no identity provider, no groups. | Keycloak as Access's identity provider is a possible next step. |
| **The Cloudflare token is broad and stored in Komodo** (secret variable) for the web deploys. | Use a token scoped to the one zone and account, as in [credentials](reference/credentials.md#cloudflare-api-token). |
| **Only HTTP services are published**; no TCP/UDP, no per-path routing within a service. | - |

## Frontends

| Limitation | Workaround / consequence |
|---|---|
| **One frontend per project.** | Planned: several, web and mobile ([roadmap](roadmap.md)). |
| **Mobile frontends (Firebase) aren't deployed**: `frontend.type: mobile` is validated only. | `firebase deploy` yourself. |
| **A project needs at least one service**: frontend-only projects aren't supported. | - |
| **The web build runs at the repo root** in `node:22`, with only `buildCommand`; no build-time configuration per environment (one build serves staging and prod). | Read environment-specific settings at runtime (e.g. from the API). |
| **Unknown paths serve `index.html`** (single-page-application fallback), always. | - |

## Identity, DNS, observability

| Limitation | Workaround / consequence |
|---|---|
| **Keycloak realms and clients aren't provisioned**: `auth.keycloak`/`auth.roles` are validated only, and frontends aren't registered as clients. | Create them in Keycloak's console. Automatic registration is planned ([roadmap](roadmap.md)). |
| **No internal DNS**: Technitium runs, nothing registers names in it. | Reach services by IP on the LAN. |
| **Logs and LXC resource metrics only** ([ADR-0023](decisions/0023-service-logs-to-loki.md)): the services' own metrics (`observability.metrics`) aren't scraped, there is no per-container resource usage, no alerting, and web frontends' logs are on Cloudflare. | Cloudflare's Workers logs for frontends. |
| **Loki keeps logs forever**: default single-node configuration, no retention set; the observability LXC's disk fills up over time. | Grow its disk (`terraform/base`), or clean Loki's volume. |
| **Grafana's admin password** is the only login (no Keycloak SSO), and Grafana is reachable on the LAN only. | `admin` / `grafanaAdminPassword` from `~/.urbex/credentials.yaml`, on `http://<observability IP>:3000`. |
| **Transactional email** (`email.provider: brevo`) is validated only. | - |

## Operations and security

| Limitation | Workaround / consequence |
|---|---|
| **Gitea and its registry are plain HTTP on the LAN**, trusted by the LXCs' Docker as an insecure registry. | Keep the LAN trusted. |
| **No backups** of Gitea, Komodo, Keycloak or the services' data. | Proxmox's own backups of the LXCs. |
| **No fleet-wide status**: `urbex status <env>` is per project. | Komodo's UI; `grep -r '^VERSION' environments/` in the GitOps repo. |
