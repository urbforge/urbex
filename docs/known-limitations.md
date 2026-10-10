# Known limitations

Everything Urbex doesn't do yet, or does with a catch, in one place - with
what to do meanwhile. What *is* supported, and the priorities, are in
[`status.md`](status.md); planned work is in [`roadmap.md`](roadmap.md).
Last reviewed: 2026-10-08, with the gaps the service conventions
([ADR-0027](decisions/0027-service-conventions.md)) address; before
that 2026-10-05, after internal DNS registration in Technitium
([ADR-0026](decisions/0026-technitium-internal-dns-records.md)) was
validated against a real Proxmox node; before that, after the
validation on a real Proxmox VE 9.2 node and Cloudflare account, and of
Cloudflare Quick Tunnel
([ADR-0025](decisions/0025-cloudflare-quick-tunnel.md)) on the same node.

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
| **Every LXC resolves through Technitium**, then `proxmox.network.dnsServers` (the gateway when unset), which are also Technitium's forwarders: a gateway that doesn't answer DNS, or a resolver the LXCs can't reach (Tailscale's MagicDNS), breaks resolution ([ADR-0027](decisions/0027-service-conventions.md)). | Set `dnsServers` (or `dns.forwarders`) to a LAN resolver. |
| **`keyctl` needs `root@pam`.** With a pool-scoped token, `proxmox.keyctl: false`. Docker has worked without it on Proxmox 9.2; other hosts may need it. | An administrator enables it per LXC: `pct set <vmid> --features nesting=1,keyctl=1`. |
| **Per-project Proxmox isolation** (resource pool, user group, technical users per project) isn't implemented: every LXC goes in the platform's pool, managed with the operator's token. | Planned ([roadmap](roadmap.md)). |
| **Keycloak runs in development mode** (embedded H2 database, rebuilt when its configuration changes): it becomes reachable ~4-6 minutes after `urbex bootstrap` reports "Platform ready", and a Keycloak upgrade has to keep the database's credentials (urbex pins those 26.0 used). | Wait; production mode (a real database) is planned with realm provisioning. |
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
| **Removing a service from `urbex.yaml`** leaves its LXC, Stack, folder, routes and internal DNS record. | `urbex destroy <env>` before removing it, or remove them by hand. |
| **Changing a port or healthcheck** needs `urbex deploy <env>` (it regenerates the compose files); configuration in `urbex.yaml`'s `env` only seeds `config.env` once. | Edit `config.env` in the GitOps repo afterwards. |
| **No concurrency guard across machines** on the Terraform state and the address ledger. | Don't run `plan`, `apply`, `destroy` from two machines at once. |
| **Terraform state isn't encrypted** (it holds no secrets). | Keep the GitOps repo private. |

## Public endpoints (Cloudflare)

| Limitation | Workaround / consequence |
|---|---|
| **`nested` hostnames need Advanced Certificate Manager**, which Urbex doesn't enable or order certificates for. | Use the default `flat` names, or enable ACM and order the wildcard certificates by hand. |
| **Public names are derived** from the project's and services' names; `domain.subdomain` in the manifest isn't used. | - |
| **Gitea and Komodo behind Access are for browsers.** `git` and the CLI keep using the LAN addresses, and the links Gitea and Komodo generate use their internal names (Gitea's registry needs `ROOT_URL` reachable from every LXC). | Use the LAN, or a VPN, for git and the CLI. |
| **Prometheus' and Loki's APIs behind Access are for browsers.** A script or tool calling them from outside needs a Cloudflare Access service token, which Urbex doesn't create. | Create a service token in Zero Trust and add it to the `urbex-operators` policy, or use the LAN. |
| **Access allows a list of e-mail addresses** with a one-time PIN; no identity provider, no groups. | Keycloak as Access's identity provider is a possible next step. |
| **The Cloudflare token is broad and stored in Komodo** (secret variable) for the web deploys. | Use a token scoped to the one zone and account, as in [credentials](reference/credentials.md#cloudflare-api-token). |
| **Only HTTP services are published**; no TCP/UDP, no per-path routing within a service. | - |
| **Cloudflare Quick Tunnel (`cloudflare.quickTunnel`) has no authentication whatsoever** and the hostname is not stable across a sidecar recreation (LXC reboot, manual restart, a change to the compose file `quicktunnel` renders); recovery after an actual network interruption to the connector isn't guaranteed. A plain `urbex apply` re-application, by itself, does not recreate the sidecar and so does not change the hostname ([ADR-0025](decisions/0025-cloudflare-quick-tunnel.md)). | For evaluation, demos and local development only; never the only public endpoint of a real deployment. `cloudflare.accountId`/`zoneId` ([ADR-0022](decisions/0022-cloudflare-tunnel-access-workers.md)) for anything else. |
| **Quick Tunnel doesn't apply to web frontends.** `frontend.type: web` keeps needing `cloudflare.accountId`/`zoneId` regardless of `quickTunnel`. | - |

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
| **Keycloak covers the projects' users only** ([ADR-0024](decisions/0024-keycloak-realm-per-environment.md)): no admin SSO for Gitea/Komodo/Grafana, no confidential clients for services calling each other, one client per frontend (and one frontend per project); destroying an environment deletes its realm's users. | Add what's missing in Keycloak's console: urbex keeps what it doesn't manage (extra redirect URIs, users, clients). |
| **A platform bootstrapped before internal DNS registration existed keeps Technitium's original admin password**: `DNS_SERVER_ADMIN_PASSWORD` only takes effect while Technitium has no configuration yet, so re-running `urbex bootstrap` on an already-configured instance doesn't rotate it, and minting the API token fails ([ADR-0026](decisions/0026-technitium-internal-dns-records.md)). | Seed the real password into `~/.urbex/credentials.yaml`'s `technitiumAdminPassword` before bootstrapping. |
| **When Technitium is down, internal names don't resolve**: the LXCs fall back to the forwarders, which only know public names. | Re-run `urbex bootstrap` to reinstall it. |
| **The internal zone (`urbex.<domain>`) shadows Cloudflare on the LAN**: Technitium answers for every name under it, so a record you created there on Cloudflare doesn't resolve from the LXCs; with `nested` public hostnames, neither do the web frontends' (they have no LXC, so no internal record) ([ADR-0027](decisions/0027-service-conventions.md)). | Keep your own records out of the platform's subdomain, or set `dns.zone`. |
| **Without Cloudflare, the token issuer is Keycloak's LAN address** (`KEYCLOAK_ISSUER`): the address your users' browsers reach it at, which the tokens carry. The services fetch the signing keys by internal name. | Configure Cloudflare for a stable, public issuer. |
| **The internal names don't resolve on your machine** unless it asks Technitium: images (`git.<zone>:3000/...`), the links Gitea and Komodo generate, and the URLs services are configured with use the internal names ([ADR-0027](decisions/0027-service-conventions.md)). The CLI uses the LAN addresses, after checking them against Technitium. | Have your router forward the zone to Technitium ([cookbook](cookbook.md#resolve-a-service-by-name-on-the-lan)). |
| **Logs and resource metrics only** ([ADR-0023](decisions/0023-service-logs-to-loki.md), [ADR-0027](decisions/0027-service-conventions.md)): the services' own metrics (`observability.metrics`) aren't scraped, per-container metrics are CPU and memory only, there is no alerting, and web frontends' runtime logs are on Cloudflare (their deploy container's are in Loki). | Cloudflare's Workers logs for frontends. |
| **Loki keeps logs forever**: default single-node configuration, no retention set; the observability LXC's disk fills up over time. | Grow its disk (`terraform/base`), or clean Loki's volume. |
| **Grafana's admin password** is the only login (no Keycloak SSO), after Cloudflare Access when reached from outside. | `admin` / `grafanaAdminPassword` from `~/.urbex/credentials.yaml`. |
| **Transactional email** (`email.provider: brevo`) is validated only. | - |

## Operations and security

| Limitation | Workaround / consequence |
|---|---|
| **Gitea and its registry are plain HTTP on the LAN**, trusted by the LXCs' Docker as an insecure registry. | Keep the LAN trusted. |
| **No backups** of Gitea, Komodo, Keycloak or the services' data. | Proxmox's own backups of the LXCs. |
| **No fleet-wide status**: `urbex status <env>` is per project. | Komodo's UI; `grep -r '^VERSION' environments/` in the GitOps repo. |
