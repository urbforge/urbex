# Known limitations

Everything Urbex doesn't do yet, or does with a catch, in one place - with
what to do meanwhile. What *is* supported, and the priorities, are in
[`status.md`](status.md); planned work is in [`roadmap.md`](roadmap.md).
Last reviewed: 2026-11-02, with the linked applications
([ADR-0031](decisions/0031-readiness-between-stacks.md)); before that
2026-10-17, with the applications from published images
([ADR-0028](decisions/0028-application-model.md)); before that
2026-10-08, with the gaps the service conventions
([ADR-0027](decisions/0027-service-conventions.md)) address; before
that 2026-10-05, after internal DNS registration in Technitium
([ADR-0026](decisions/0026-technitium-internal-dns-records.md)) was
validated against a real Proxmox node; before that, after the
validation on a real Proxmox VE 9.2 node and Cloudflare account, and of
Cloudflare Quick Tunnel
([ADR-0025](decisions/0025-cloudflare-quick-tunnel.md)) on the same node.

**v0.2.0 is a preview release.** In short: no backups of the platform
in v0.2.0 (on `main`, whole machines on Proxmox; restore and off-site
copies are planned in M3, [below](#operations-and-security)); Proxmox only
(VPS support is planned in M3, E3-bis); a single operator, from one
workspace; and while Urbex is 0.x, a
minor release may change how something works (see
[Upgrading](upgrading.md)).

- [Platform](#platform)
- [Projects and deploys](#projects-and-deploys)
- [Public endpoints (Cloudflare)](#public-endpoints-cloudflare)
- [Frontends](#frontends)
- [Identity, DNS, observability](#identity-dns-observability)
- [Operations and security](#operations-and-security)

## Platform

| Limitation | Workaround / consequence |
|---|---|
| **Docker Hub's anonymous limit** (100 pulls an hour per address) applies to every machine of the platform, which share the node's address; a bootstrap or many deploys in an hour can hit it (`429 Too Many Requests`). | [Pull from Docker Hub through a cache](cookbook.md#pull-from-docker-hub-through-a-cache) (`docker.registryMirrors`); a cache on the platform itself is tracked in [urbex-cli#33](https://github.com/urbforge/urbex-cli/issues/33). |
| **A platform installed with urbex 0.1.0 stays on Gitea 1.24**, which is out of support: newer urbex bootstraps Forgejo 15 LTS ([ADR-0034](decisions/0034-forgejo-lts-forge.md)), and doesn't migrate a running forge - Forgejo imports Gitea's database only up to Gitea 1.22. Its workspace keeps working with newer urbex (the old credential and config names are still read). | Bootstrap the platform again (`urbex teardown`, then `urbex bootstrap`; push the project repos somewhere else first), or push the repos to the new forge yourself. |
| **One Proxmox node.** Every LXC is created on `proxmox.node`; no clusters, no HA, no other providers (cloud providers are v2+). | - |
| **Addresses aren't checked or reserved.** Urbex takes static IPs from `proxmox.network` (base services from `baseHostOffset`, projects 10 after) without checking they're free; a DHCP server can hand them out too. | Keep the block out of the DHCP range. |
| **Every LXC resolves through Technitium**, then `proxmox.network.dnsServers` (the gateway when unset), which are also Technitium's forwarders: a gateway that doesn't answer DNS, or a resolver the LXCs can't reach (Tailscale's MagicDNS), breaks resolution ([ADR-0027](decisions/0027-service-conventions.md)). | Set `dnsServers` (or `dns.forwarders`) to a LAN resolver. |
| **`keyctl` needs `root@pam`**, so it is off by default (`proxmox.keyctl: false`). Docker has worked without it on Proxmox 9.2; other hosts may need it. | Run the application in a VM (`machine: vm`, [ADR-0033](decisions/0033-vm-for-keyctl-mount-fuse.md)); or an administrator enables it per LXC: `pct set <vmid> --features nesting=1,keyctl=1`. |
| **An application in a VM costs more**: about 300-400 MB of memory more than in an LXC, and a boot of tens of seconds. Its template needs the Debian cloud image on the node, added once by the operator (`proxmox.vmImage`): a pool-scoped token can't download it. | Use `machine: vm` only for what needs keyctl, mount or fuse. |
| **A VM has no boot order**: Proxmox lets only a user with `Sys.Modify` on `/` set a VM's startup order, which a pool-scoped token doesn't have. After a reboot of the node a VM starts with the unordered machines, after the platform and the ordered LXCs; its Stack still waits for what it uses ([ADR-0031](decisions/0031-readiness-between-stacks.md)). | An administrator sets it once: `qm set <vmid> --startup order=<n>`. |
| **No shares in a VM yet**: `urbex apply` refuses an application with `machine: vm` that declares one. | Keep such an application in an LXC; NFS and SMB shares mounted by the VM itself are next ([urbex-cli#83](https://github.com/urbforge/urbex-cli/issues/83)). |
| **Switching an application between LXC and VM replaces its machine**, and Urbex doesn't move its data. | `urbex apply` refuses it for a machine with named volumes: copy the data out first. |
| **Per-project Proxmox isolation** (resource pool, user group, technical users per project) isn't implemented: every LXC goes in the platform's pool, managed with the operator's token. | Planned ([roadmap](roadmap.md)). |
| **Keycloak's first start builds its image**, once per platform: about 7 minutes on a home lab node, which `urbex bootstrap` and `urbex apply` wait for (up to 15 minutes). Later starts take under a minute ([ADR-0029](decisions/0029-keycloak-production-postgresql.md)). | Wait. |
| **Base-service images** of Technitium, Prometheus, Loki and Grafana use `latest`. | - |
| **`urbex teardown` destroys Forgejo**, with every repository and image on it. | Keep project repos pushed elsewhere too. The GitOps repo survives as the local working copy: keep it. |
| **Rotating generated credentials isn't supported**: bootstrap keeps every value in `~/.urbex/credentials.yaml`, and changing one by hand (the Komodo database password, say) can break the service. | Only by rebuilding the platform: `urbex teardown` then `urbex bootstrap`. |

## Projects and deploys

| Limitation | Workaround / consequence |
|---|---|
| **A `healthcheck` probes with `wget` inside the container**: many published images (Vaultwarden, Paperless-ngx, Jellyfin) have only `curl`, and the container then never turns healthy. | Leave `healthcheck` out on such an image (its own Docker `HEALTHCHECK`, if it has one, still runs); an application others `use` needs one, so pick an image with `wget` or don't link it. |
| **A `healthcheck` is an HTTP path**: an application others `use` needs one (or the `postgres` interface), so a service that speaks no HTTP - Redis/Valkey, MQTT, a game server - can't be in `uses`. | Reach it by its internal name in `env`, without `uses`, as the [Paperless-ngx recipe](cookbook.md#run-a-stack-of-linked-apps-paperless-ngx-with-postgresql-and-redis) does; the app isn't held back until it answers. |
| **A `postgres` provider gives each application a role without superuser rights**: an app that creates PostgreSQL extensions itself - Immich (VectorChord), some with PostGIS - can't use it. | None yet: such an app needs its database as an application of its own that it administers, which isn't supported. |
| **No GPU or other device passed to an application**: hardware transcoding (Jellyfin, Plex), machine learning (Immich, Frigate) run on the CPU. | Give the application more `resources.cpu`. |
| **`auth.keycloak` gives an application its realm's addresses, not a login**: an app with its own OIDC settings (Paperless, Jellyfin's plugin, Nextcloud) is configured by hand with a client you create in Keycloak. | Create the client in its environment's realm and set the app's OIDC variables with `urbex secret` and `config.env`. |
| **Only `vX.Y.Z` tags are releases**: no pre-releases (`-rc.1`). | Staging runs every commit of `main`; release a patch version. |
| **`urbex promote` commits straight to the GitOps repo.** | [Gate production behind a pull request](cookbook.md#gate-production-behind-a-pull-request) with Forgejo's protected file patterns. |
| **Komodo can miss a push** made within ~5 seconds of the previous one (it caches the repo); the scheduled run catches up within 15 minutes. | The `urbex` commands handle it; by hand, run the `urbex-gitops` Procedure. |
| **Every push to `main` is built**, documentation-only ones included, and **images are never pruned.** | Delete old ones in Forgejo, under the organization's *Packages*. |
| **Removing a service from `urbex.yaml`**: the next `urbex apply` deletes its LXC (the project's Terraform has one per declared service) but leaves its Stack, folder, routes and internal DNS record. With named volumes, `apply` refuses: Proxmox deletes an LXC's volumes with it. | Remove the leftovers by hand. For an application with named volumes, put it back, or run `urbex apply <env> --delete-data` to delete it with its volumes. |
| **Changing a port or healthcheck** needs `urbex deploy <env>` (it regenerates the compose files); configuration in `urbex.yaml`'s `env` only seeds `config.env` once. | Edit `config.env` in the GitOps repo afterwards. |
| **No concurrency guard across machines** on the Terraform state and the address ledger. | Don't run `plan`, `apply`, `destroy` from two machines at once. |
| **Terraform state isn't encrypted** (it holds no secrets). | Keep the GitOps repo private. |
| Applications from published images must be public: a registry that requires credentials is refused when the tag is resolved ([ADR-0028](decisions/0028-application-model.md)). | None at present. |
| **Named volumes can't survive a replacement of their LXC**: Proxmox deletes an LXC's volumes with it, and Urbex doesn't detach and re-attach them, so `urbex apply` refuses a change that would replace an LXC with named volumes (a different `proxmox.storagePool`, for instance). | Revert the change; or copy the data out, `urbex destroy <env> --delete-data`, and apply again. |
| **A named volume can only grow**: Proxmox can't shrink one, and `urbex apply` refuses a smaller `size`. | Keep the size; or copy the data out and recreate the environment. |
| **A volume removed from `urbex.yaml`** is no longer mounted in the container, but stays on its LXC, and in its backups, until `urbex destroy <env> --delete-data`; `urbex apply` still refuses to replace that LXC. | Remove the mount point by hand (`pct set <vmid> -delete mp<n>`): Proxmox keeps the volume as an unused disk of the LXC, and removing that disk too deletes the data. |
| **An image that changes the user it runs as** between versions leaves the files of a volume with the old owner: Docker fills a volume from the image only the first time, when it is empty. | As with any Docker volume: change the owner of the volume's folder on the LXC (`chown -R`, as root) once, before the new version starts. |
| **Shares need the operator**: binding a folder of the Proxmox node into an LXC needs `root@pam`, which an API token never has. `urbex apply` prints the `pct set` commands and deploys the application once they have been run. A share is not in Proxmox's backups of the LXC (vzdump skips bind mount points): the NAS's data is backed up on the NAS. The LXCs are unprivileged, so the folder's files must be readable, or writable, by user 100000 on the node ([how](cookbook.md#mount-a-nas-share)). | Run the printed commands on the node, as root. Shares without root, mounted by a VM, are tracked in [urbex-cli#83](https://github.com/urbforge/urbex-cli/issues/83). |
| A stack cannot change from two environments to production only by editing `environments`: removing `staging` from the list leaves its LXCs, Stacks and folder in place. | Run `urbex destroy staging` before removing it. |
| A stack whose services built from source are all replaced by applications from published images keeps their Builds in Komodo: `urbex apply` removes the release webhook, but not the Builds, as with any service removed from `urbex.yaml`. | Delete the Builds in Komodo's UI. |
| **A PostgreSQL's own password can't be recovered**: if the GitOps repo loses the provider's `urbex.sops.env` while its volume stays, Urbex can no longer manage the server's roles and schemas. An application's lost password is regenerated and set on its role by the next `urbex apply` ([ADR-0030](decisions/0030-postgresql-application.md)). | Keep the GitOps repo backed up. Or reset the password of the user `urbex` by hand, as root in the container, to the value of a new `POSTGRES_PASSWORD`. |
| **No rotation of a PostgreSQL role's password on demand.** | Delete the password from the application's `urbex.sops.env`; the next `urbex apply` generates a new one and sets it on the role. |
| **No automated major upgrade of PostgreSQL**: a new major can't open the old data directory, so `urbex deploy` and `urbex promote` refuse it, `--allow-major` or not, while the data directory (its `PG_VERSION`) is the old major's. | Upgrade by hand: dump, move the data directory aside, deploy the new major, restore ([how](cookbook.md#upgrade-postgresql-to-a-new-major-version)). |
| The wait sees a provider from outside, so it cannot see a restart. A provider in a crash loop that stays up longer than 20 s at a time passes the wait, and the application starts on it ([ADR-0031](decisions/0031-readiness-between-stacks.md)). | Watch the provider's restarts in Komodo or Grafana. |
| Every level of `uses` starts at least 20 s after the one it uses, the time a provider must answer without a failure. | None; it is the price of the check. |
| The reconciler acts once a minute, and Komodo refreshes its view of the containers about every 15 seconds, so an application whose provider came back starts a few minutes later. | Deploy its Stack in Komodo to have it at once. |
| The reconciler sees a restart only between two runs. A provider that restarts twice within one run counts as one restart, and the crash loop alert comes at the second restart seen, within 10 minutes. | None at present; an alert on every restart of an application is planned. |
| Urbex's alerts - the reconciler's, and those on disk and memory - notify nobody unless `observability.alerts` names a channel. With it, Urbex owns Grafana's notification policies, so a contact point added by hand isn't used; alerts can't be silenced from the chat. | [Get the alerts on Telegram or Discord](cookbook.md#get-the-alerts-on-telegram-or-discord); silence one in Grafana (Alerting, Silences). |
| A platform bootstrapped before the reconciler existed has neither the `urbex-reconcile` Action nor its Grafana alerts. | Run `urbex bootstrap` again with the new CLI; it installs both. |
| An application used by others needs an HTTP healthcheck or the `postgres` interface; a provider that speaks another protocol, such as Redis or MQTT, cannot be used yet. | Give it an HTTP healthcheck, if it has one. |
| The wait runs `postgres:17-alpine`, pulled on the LXC of every application that uses others, by tag. | None at present; an image of Urbex's own, pinned by digest, is planned. |

## Public endpoints (Cloudflare)

| Limitation | Workaround / consequence |
|---|---|
| **`nested` hostnames need Advanced Certificate Manager**, which Urbex doesn't enable or order certificates for. | Use the default `flat` names, or enable ACM and order the wildcard certificates by hand. |
| **Public names are derived** from the project's and services' names; `domain.subdomain` in the manifest isn't used. | - |
| **Forgejo and Komodo behind Access are for browsers.** `git` and the CLI keep using the LAN addresses, and the links Forgejo and Komodo generate use their internal names (Forgejo's registry needs `ROOT_URL` reachable from every LXC). | Use the LAN, or a VPN, for git and the CLI. |
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
| **Keycloak covers the projects' users only** ([ADR-0024](decisions/0024-keycloak-realm-per-environment.md)): no admin SSO for Forgejo/Komodo/Grafana, no confidential clients for services calling each other, one client per frontend (and one frontend per project); destroying an environment deletes its realm's users. | Add what's missing in Keycloak's console: urbex keeps what it doesn't manage (extra redirect URIs, users, clients). |
| **A platform bootstrapped before internal DNS registration existed keeps Technitium's original admin password**: `DNS_SERVER_ADMIN_PASSWORD` only takes effect while Technitium has no configuration yet, so re-running `urbex bootstrap` on an already-configured instance doesn't rotate it, and minting the API token fails ([ADR-0026](decisions/0026-technitium-internal-dns-records.md)). | Seed the real password into `~/.urbex/credentials.yaml`'s `technitiumAdminPassword` before bootstrapping. |
| Technitium does not validate DNSSEC: it leaves validation to its forwarders, since many LAN resolvers, and routers that intercept DNS traffic, do not return the records validation requires, and Technitium would then fail every public name. | Use forwarders that validate DNSSEC, if validation is required. |
| **When Technitium is down, internal names don't resolve**: the LXCs fall back to the forwarders, which only know public names. | Re-run `urbex bootstrap` to reinstall it. |
| **The internal zone (`urbex.<domain>`) shadows Cloudflare on the LAN**: Technitium answers for every name under it, so a record you created there on Cloudflare doesn't resolve from the LXCs; with `nested` public hostnames, neither do the web frontends' (they have no LXC, so no internal record) ([ADR-0027](decisions/0027-service-conventions.md)). | Keep your own records out of the platform's subdomain, or set `dns.zone`. |
| **Without Cloudflare, the token issuer is Keycloak's LAN address** (`KEYCLOAK_ISSUER`): the address your users' browsers reach it at, which the tokens carry. The services fetch the signing keys by internal name. | Configure Cloudflare for a stable, public issuer. |
| **The internal names don't resolve on your machine** unless it asks Technitium: images (`git.<zone>:3000/...`), the links Forgejo and Komodo generate, and the URLs services are configured with use the internal names ([ADR-0027](decisions/0027-service-conventions.md)). The CLI uses the LAN addresses, after checking them against Technitium. | Have your router forward the zone to Technitium ([cookbook](cookbook.md#resolve-a-service-by-name-on-the-lan)). |
| **Logs and resource metrics only** ([ADR-0023](decisions/0023-service-logs-to-loki.md), [ADR-0027](decisions/0027-service-conventions.md)): the services' own metrics (`observability.metrics`) aren't scraped, per-container metrics are CPU and memory only, the only alerts are the reconciler's and those on the LXCs' disk and memory - on the Proxmox node's memory and storages only with the optional [monitoring token](reference/credentials.md#proxmox-monitoring-token), never on a VM - and web frontends' runtime logs are on Cloudflare (their deploy container's are in Loki). | Cloudflare's Workers logs for frontends. |
| **Loki keeps logs forever**: default single-node configuration, no retention set; the observability LXC's disk fills up over time. | Grow its disk (`terraform/base`), or clean Loki's volume. |
| **Grafana's admin password** is the only login (no Keycloak SSO), after Cloudflare Access when reached from outside. | `admin` / `grafanaAdminPassword` from `~/.urbex/credentials.yaml`. |
| **Transactional email** (`email.provider: brevo`) is validated only. | - |

## Operations and security

| Limitation | Workaround / consequence |
|---|---|
| **Java4Shell (CVE-2026-114938) is mitigated, not fixed**: Keycloak's image (`quay.io/keycloak/keycloak:26.7.5`, OpenJDK 21.0.12.1) and the `runtime: java` images (Temurin 21) carry an OpenJDK whose Base64 intrinsic corrupts memory on x86-64 CPUs with AVX-512 VBMI (recent Intel Xeon and Core, AMD Zen 4 and 5); Keycloak decodes Base64 before login. Urbex starts both without that intrinsic (`-XX:-UseBASE64Intrinsics`), until images with a fixed OpenJDK exist ([urbex-cli#130](https://github.com/urbforge/urbex-cli/issues/130)). | Run `urbex bootstrap` with a urbex that has the fix (see the CHANGELOG) to apply it to an existing platform; a `runtime: java` service gets it with its next build. An app that sets its own `JAVA_TOOL_OPTIONS` replaces Urbex's and should add the flag. CPUs without AVX-512 VBMI aren't affected (`grep -c avx512vbmi /proc/cpuinfo` on the node gives 0). |
| **Forgejo and its registry are plain HTTP on the LAN**, trusted by the LXCs' Docker as an insecure registry. | Keep the LAN trusted. |
| **Backups are only whole machines, on Proxmox** ([ADR-0036](decisions/0036-backups-and-restore.md)): with `backups.proxmox.storage`, the pool's machines are backed up every day with vzdump, each database dumped first. `urbex restore`, the off-site file layer (restic), the backup metrics and alert, and a VPS's backups are still to come (E3). Without a storage, nothing is backed up. | Proxmox's own backups of the LXCs, which include the applications' named volumes (`backup=1`); a restore brings them back and `urbex apply` takes it as it is ([how](cookbook.md#back-up-and-restore-an-applications-data)). |
| **No fleet-wide status**: `urbex status <env>` is per project. | Komodo's UI; `grep -r '^VERSION' environments/` in the GitOps repo. |
