# Platform config reference (`urbex.platform.yaml`)

`urbex.platform.yaml` is at the root of the GitOps repo and describes the
platform: the Proxmox server, the network, the domain. `urbex bootstrap`
writes a starter one the first time; every command reads it. It holds no
secrets - those are [credentials](credentials.md).

## Example

```yaml
domain: acme.example

git:
  forgeUrl: https://git.acme.example
  org: urbex

proxmox:
  apiUrl: https://192.168.1.10:8006/api2/json
  insecure: true
  node: pve
  storagePool: local-zfs
  lxcTemplate: local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst
  sshPublicKey: "ssh-ed25519 AAAA... urbex"
  vmIdBase: 9000
  pool: urbex
  vmImage: local:import/debian-13-genericcloud-amd64.qcow2   # only for machine: vm
  network:
    cidr: 192.168.1.0/24
    gateway: 192.168.1.1
    baseHostOffset: 200
    bridge: vmbr0
    dnsServers: [192.168.1.1]

cloudflare:                       # optional: public endpoints
  accountId: 0123456789abcdef0123456789abcdef
  zoneId: fedcba9876543210fedcba9876543210   # the zone of "domain"
  access:
    emails: [you@example.com, them@example.com]
```

Without a Cloudflare account, `cloudflare.quickTunnel: true` is an
alternative that publishes `public: true` services on
`https://*.trycloudflare.com` instead - see
[ADR-0025](../decisions/0025-cloudflare-quick-tunnel.md):

```yaml
cloudflare:
  quickTunnel: true    # alternative to accountId/zoneId, not both
```

## Fields

| Field | Default | Meaning |
|---|---|---|
| `domain` | required | The platform's domain: the Cloudflare zone public hostnames are created in, and the Forgejo admin's e-mail domain. |
| `git.forgeUrl` | required | The public URL the forge (Forgejo) will have; `git.giteaUrl`, its name before [ADR-0034](../decisions/0034-forgejo-lts-forge.md), is still read. ⚠️ Not used yet: Urbex reaches Gitea at `http://<its IP>:3000`. |
| `git.org` | `urbex` | Forgejo organization holding the GitOps repo (`<org>/gitops`), every project repo (`<org>/<project>`), and their images (`<ip>:3000/<org>/<project>-<service>`). |
| `proxmox.apiUrl` | required | Proxmox API URL, ending in `/api2/json`. |
| `proxmox.insecure` | `false` | Skip TLS verification of the Proxmox API (its default certificate is self-signed). |
| `proxmox.node` | required | The node every LXC is created on. |
| `proxmox.storagePool` | `local-lvm` | Storage for the LXCs' root disks and the applications' named volumes. |
| `proxmox.lxcTemplate` | required | The Debian 13 template volume, e.g. `local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst` (`pveam list local` shows yours). |
| `proxmox.sshPublicKey` | required | Public key installed for `root` on every LXC; Ansible connects with the matching private key, from your SSH agent. |
| `proxmox.vmIdBase` | `9000` | First VMID: base services get `vmIdBase` to `+4`, project LXCs `vmIdBase+100` onwards. |
| `proxmox.pool` | none | Resource pool every LXC goes in. Required when the API token's permissions are on a pool. |
| `proxmox.keyctl` | `false` | Enable the LXC `keyctl` feature, which Docker needs on some hosts. Only `root@pam` may set it, so leave it off with any other token; turn it on only with a `root@pam` token and if Docker fails with overlayfs `permission denied` errors ([upgrading](#keyctl-on-a-platform-created-before-it-was-off)). |
| `proxmox.vmImage` | none | The Debian 13 cloud image urbex's VM template is built from, on a storage with the `import` content type, e.g. `local:import/debian-13-genericcloud-amd64.qcow2`. Required only once an application has `machine: vm`; see [a VM image](#a-vm-image). |
| `proxmox.network.cidr` | required | LAN the LXCs are on; their static IPs are taken from it. |
| `proxmox.network.gateway` | required | Default gateway of the LXCs. |
| `proxmox.network.baseHostOffset` | `200` | Host number of the first base service's IP (`.200` in a /24). Base services take 5 addresses from there; project LXCs start 10 after it (`.210`). |
| `proxmox.network.bridge` | `vmbr0` | Proxmox bridge the LXCs attach to. The API token needs `SDN.Use` on it (see [credentials](credentials.md#proxmox-api-token)). |
| `proxmox.network.dnsServers` | the gateway | Your LAN's resolvers. Every LXC resolves through Technitium first, then these; they are also Technitium's default forwarders (`dns.forwarders`). Unset, the gateway. Don't use a resolver the LXCs can't reach, such as Tailscale's MagicDNS (`100.100.100.100`). |
| `cloudflare.accountId`, `cloudflare.zoneId` | none | The Cloudflare account and the zone of `domain`. Set both to publish endpoints on Cloudflare ([ADR-0022](../decisions/0022-cloudflare-tunnel-access-workers.md)); leave both empty to keep everything on the LAN. Needs `URBEX_CLOUDFLARE_TOKEN`. |
| `cloudflare.name` | `urbex` | Last label of every public hostname, telling Urbex's apart from the zone's others. |
| `cloudflare.hostnames` | `flat` | How labels are joined - see [public hostnames](#public-hostnames). |
| `cloudflare.tunnelName` | `<name>-platform` | The Cloudflare Tunnel Urbex creates and routes through. |
| `cloudflare.access.emails` | required with Cloudflare | Who may open Forgejo and Komodo through Cloudflare Access (one-time PIN sent to the address). |
| `cloudflare.quickTunnel` | `false` | Alternative to `cloudflare.accountId`/`zoneId` (mutually exclusive with them): a Cloudflare Quick Tunnel per `public: true` service, no account needed - see [ADR-0025](../decisions/0025-cloudflare-quick-tunnel.md) and its [known limitations](../known-limitations.md#public-endpoints-cloudflare). Doesn't apply to `frontend.type: web`. |
| `docker.registryMirrors` | none | Pull-through caches of Docker Hub, as Docker's `registry-mirrors` (`["http://192.168.1.50:5000"]`): every machine's Docker pulls Docker Hub's images through them, so a bootstrap or many deploys in an hour don't hit Docker Hub's anonymous limit (100 pulls an hour per address). An `http://` mirror is also trusted as an insecure registry. Applied by `urbex bootstrap` to the platform's machines and by `urbex apply` to an environment's. See [pull from Docker Hub through a cache](../cookbook.md#pull-from-docker-hub-through-a-cache). |
| `dns.zone` | `<cloudflare.name>.<domain>` | The zone Technitium serves the services' internal names in - `git.urbex.example.com`, `api.staging.acme-app.urbex.example.com` ([ADR-0027](../decisions/0027-service-conventions.md)). Technitium answers for the whole zone: keep nothing of yours under it on Cloudflare. |
| `dns.forwarders` | `proxmox.network.dnsServers`, or the gateway | IP addresses Technitium forwards every name outside `dns.zone` to. |
| `dns.technitiumUrl` | | ⚠️ Not used: `urbex` finds Technitium itself from the allocated LAN IP. |
| `keycloak.baseUrl`, `keycloak.platformRealm` (`platform`) | | ⚠️ Not used yet (SSO). |
| `komodo.buildCache.keepStorage` | `3GB` | The builds' cache on Komodo's LXC is pruned, least recently used first, down to this size (`500MB`, `3GB`...). |
| `komodo.buildCache.keepFor` | `168h` | ...and of what is older than this duration; so are the images no container uses, older than it. An hour or more. |
| `komodo.buildCache.every` | `24h` | How often (the first run 10 minutes after the Stack starts). An hour or more. Changed by `urbex bootstrap`. |
| `observability.alerts.telegram.chatId` | none | Send Urbex's alerts to this Telegram chat: a number, negative for a group, or a public channel's `@name`. Needs the credential `telegramBotToken`. See [get the alerts on Telegram or Discord](../cookbook.md#get-the-alerts-on-telegram-or-discord). |
| `observability.alerts.discord` | `false` | Send them to a Discord channel's webhook, the credential `discordWebhookUrl`. |
| `observability.alerts.webhook` | `false` | Post them as Grafana's JSON to the credential `alertsWebhookUrl`. Any of the three, or several; with none, the alerts stay in Grafana. Applied by `urbex bootstrap`; checked by `urbex doctor --test-alerts`. |
| `backups.schedule` | `03:00` | When the backups run, every day, `HH:MM` in `backups.timezone`. See [backups](#backups). |
| `backups.timezone` | `Etc/UTC` | The schedule's time zone, an IANA name such as `Europe/Rome` (Komodo runs in UTC). |
| `backups.proxmox.storage` | none | The Proxmox storage the machines are backed up to: a Proxmox Backup Server datastore added to the node, or any storage with the `backup` content (an NFS share, a directory). **No default**: without it the Proxmox layer is off and nothing is backed up. Needs `proxmox.pool` and the credential [`proxmoxBackupToken`](credentials.md#proxmox-backup-token). |
| `backups.proxmox.machines` | `[platform, projects]` | Which of the pool's machines: the platform's (Forgejo, Komodo, Keycloak, Technitium, observability, tunnel), the projects', or both. |
| `backups.proxmox.mode` | `snapshot` | vzdump's mode: `snapshot` (no downtime), `suspend` or `stop`. |
| `backups.proxmox.modes.<hostname>` | none | Another mode for one machine, e.g. `urbex-gitea: stop`. |
| `backups.proxmox.keep.daily`, `.weekly`, `.monthly` | `7`, `4`, `6` | How many backups of each machine are kept: after each run, the older ones of the backed-up machines are pruned, machine by machine. |
| `storage.shares.<name>.path` | none | A folder of the Proxmox node that applications mount by name: see [shares](#shares). An absolute path that isn't `/` and has no comma, space or tab. |

## Shares

A share is a folder of the Proxmox node that exists outside Urbex, such
as a NAS mounted on the node, which applications mount by its name
([ADR-0028](../decisions/0028-application-model.md)):

```yaml
storage:
  shares:
    media:
      path: /mnt/pve/nas/media    # where the NAS is mounted on the node
```

An application names it in its `volumes` (`{ share: media, path: /media }`,
see the [manifest reference](manifest.md#volumes)), and its LXC mounts
it at `/srv/shares/media`. Binding a folder of the node into an LXC needs
`root@pam`, so `urbex apply` prints the `pct set` command for each LXC
that lacks it and deploys the application once the command has been
run. Urbex never changes or deletes a share. The LXCs are unprivileged:
their root is user 100000 on the node, so the files must be readable,
or writable, by that user, as the NAS mounts them. The cookbook has the steps, for NFS and SMB:
[Mount a NAS share](../cookbook.md#mount-a-nas-share).

## Backups

Two layers ([ADR-0036](../decisions/0036-backups-and-restore.md)), each
off until you give it a target, and best used together on Proxmox:

- **the Proxmox layer**: the pool's machines, whole, with vzdump, to a
  storage of the node - for fast restores of a whole machine;
- **the file layer**: the forge's, Komodo's and Keycloak's data, with
  restic, to a bucket or a share - off the node, encrypted.

Both run every day at `backups.schedule`, in one Komodo Procedure,
`urbex-backup`: the databases' dumps first, then the Proxmox layer, then
the file layer. Without either, nothing is backed up, and `urbex status`
and `urbex doctor` say so.

### The Proxmox layer

Every day, the pool's machines are backed up whole, with vzdump, to a
storage you name, with a consistent dump of each database inside.

```yaml
proxmox:
  pool: urbex                 # required: only the pool's machines are backed up
backups:
  schedule: "03:00"
  timezone: Europe/Rome
  proxmox:
    storage: pbs              # a PBS datastore on another device, or a storage with the backup content
    # machines: [platform, projects]
    # mode: snapshot
    # modes: {urbex-gitea: stop}
    # keep: {daily: 7, weekly: 4, monthly: 6}
```

Add the storage to the node and create the
[backup token](credentials.md#proxmox-backup-token) first, then run
`urbex bootstrap`: it sets up the Komodo Procedure `urbex-backup`, which
runs the Action `urbex-backup` on the schedule. A run:

1. **dumps the databases into their volumes**: Komodo's own database
   (Komodo's backup, into `/etc/komodo/backups` on its LXC), a consistent
   copy of Forgejo's SQLite database (`/data/urbex-dumps/gitea.db`),
   `pg_dump` of Keycloak's PostgreSQL and of every project's PostgreSQL
   server (`provides: postgres`), in the custom format, one file per
   database, into `urbex-dumps` next to its data directory - on the
   server's volume. A snapshot of a running database is only
   crash-consistent; the dump next to it is consistent;
2. **backs the machines up** with vzdump through the Proxmox API, one
   task per mode, and waits for each. Only the pool's machines, never a
   template or another guest of the node. Another storage than a PBS
   gets `zstd` compression; a PBS compresses and deduplicates by itself.
3. **prunes** each backed-up machine's older backups to
   `backups.proxmox.keep`, through the storage's prune, one machine at a
   time: only those machines' backups, never another guest's or a file
   that isn't a backup.

A failed dump doesn't stop the backups: the machine is still saved,
with its previous dump. A failure fails the run in Komodo and is sent
to Loki (`{source="urbex-backup", level="error"}`). Run it now from
Komodo (Procedures > `urbex-backup` > Run), and check the setup with
`urbex doctor`. A changed schedule, storage or retention is applied by
`urbex bootstrap`. Whole-machine restore is
[urbforge/urbex-cli#121](https://github.com/urbforge/urbex-cli/issues/121)'s
next step; meanwhile, restore a machine from Proxmox's UI (the machine >
Backup > Restore).

### The file layer

restic copies the platform's data into **one repository per platform**,
off the node, encrypted with a password urbex generates:

- the forge's `/data` - its repositories, the container registry, its
  database - with the consistent copy of its SQLite the dumps take first;
- Komodo's database backups (`/etc/komodo/backups`);
- the dump of Keycloak's PostgreSQL;
- a copy of `credentials.yaml` **without `proxmoxToken` and
  `cloudflareToken`**, which never go onto the platform
  ([more](credentials.md#in-the-backups)).

```yaml
backups:
  files:
    target: s3:https://s3.eu-central-003.backblazeb2.com/my-bucket/urbex
    # target: share:nas/urbex-backups    # or a folder of one of storage.shares
    # keep: {daily: 7, weekly: 4, monthly: 6}
```

`target` is either:

- **a bucket** of an S3-compatible service - Backblaze B2, Hetzner Object
  Storage, Cloudflare R2, MinIO on a NAS - in restic's syntax,
  `s3:https://<endpoint>/<bucket>[/<prefix>]`. Create a key that may read
  and write that bucket, and store it as
  [`backupS3AccessKeyId` and `backupS3SecretAccessKey`](credentials.md#backup-bucket-key).
  The recommended target: off the node and off the house;
- **a share**, `share:<name>[/<folder>]`: a folder of one of
  [`storage.shares`](#shares), such as a NAS mounted on the node.
  restic runs on three LXCs - the forge's, Komodo's and Keycloak's - so
  the share is bound into each of them. That needs `root@pam`, so
  `urbex bootstrap` prints the commands and doesn't run the file layer
  until they have been run:

  ```
  pct set 9000 -mp0 /mnt/pve/nas,mp=/mnt/urbex-backup
  pct set 9001 -mp1 /mnt/pve/nas,mp=/mnt/urbex-backup
  pct set 9003 -mp0 /mnt/pve/nas,mp=/mnt/urbex-backup
  ```

  Run them on the node, as root, then `urbex bootstrap` again. The LXCs
  are unprivileged: the folder must be writable by user 100000 on the
  node ([how](../cookbook.md#mount-a-nas-share)).

**The backup password.** The first `urbex bootstrap` with a target
generates `backupPassword` into `credentials.yaml` and shows it once.
**Store it off the platform, in a password manager, with the age key**:
the backups can't be read without it, and nothing can recover it. `urbex doctor` warns until you have
said so, with `urbex-op set backupSecretsStored` and `yes`. A teardown
keeps it, so a new platform still reads the old backups.

`urbex bootstrap` puts restic in a Stack next to each machine's data
(`urbex-backup-gitea`, `-komodo`, `-keycloak`, each its own compose
project). The repository, the password, the bucket's key and the copy
of `credentials.yaml` are secret Komodo variables, never in the GitOps
repo; each `urbex bootstrap` refreshes the copy. Each run of `urbex-backup`,
after the dumps and the Proxmox layer:

1. backs up each machine's data with `restic backup`, one machine after
   another, as a snapshot tagged `platform` and named after the machine
   (`urbex-gitea`, ...); the first run creates the repository;
2. `restic forget` keeps, per machine, `backups.files.keep`: 7 daily, 4
   weekly, 6 monthly snapshots by default;
3. on Sundays, the forget also prunes - frees the data of the forgotten
   snapshots;
4. on the 1st of the month, `restic check` reads a tenth of the data, so
   the whole repository is read back over the months.

A machine that fails doesn't stop the others; a failure fails the run in
Komodo and goes to Loki, as the Proxmox layer's. Removing `target` and
running `urbex bootstrap` removes the Stacks and the variables; the
repository stays where it is. Restoring the platform from the file layer
(`urbex restore platform`) is the next step
([urbforge/urbex-cli#122](https://github.com/urbforge/urbex-cli/issues/122)):
until then, `restic restore` from a backup Stack restores files by hand.
The projects' databases and volumes come with
[urbforge/urbex-cli#123](https://github.com/urbforge/urbex-cli/issues/123).

## A VM image

An application with [`machine: vm`](manifest.md#machine) runs in a VM, a
linked clone of urbex's VM template. `urbex apply` builds the template
the first time it is needed, from the Debian 13 cloud image that
`proxmox.vmImage` names ([ADR-0033](../decisions/0033-vm-for-keyctl-mount-fuse.md)).
Putting that image on the node needs more than a pool-scoped token
(`Datastore.AllocateTemplate` on the storage), so you add it once, as
you added the LXC template.

The storage must have the `import` content type. In the web UI: the
storage, *Import*, *Download from URL*. Or as root on the node:

```sh
pvesh create /nodes/<node>/storage/local/download-url \
  --content import \
  --filename debian-13-genericcloud-amd64.qcow2 \
  --url https://cloud.debian.org/images/cloud/trixie/20261103-2651/debian-13-genericcloud-amd64-20261103-2651.qcow2
```

Take a dated build from <https://cloud.debian.org/images/cloud/trixie/>
rather than `latest/`, which returns 404 while a new build is being
published; its `SHA512SUMS` is next to it. Then name it in the config:

```yaml
proxmox:
  vmImage: local:import/debian-13-genericcloud-amd64.qcow2
```

Without it, `urbex apply` of an application with `machine: vm` stops and
says so. A different image makes a new template on the next `apply`;
the VMs that exist keep theirs.

## Public hostnames

With Cloudflare configured, Urbex publishes, under `domain`:

| | `flat` (default) | `nested` |
|---|---|---|
| Keycloak (`/admin` and the `master` realm behind Access) | `auth-urbex.<domain>` | `auth.urbex.<domain>` |
| Forgejo (behind Access) | `git-urbex.<domain>` | `git.urbex.<domain>` |
| Komodo (behind Access) | `komodo-urbex.<domain>` | `komodo.urbex.<domain>` |
| Komodo webhooks (`/listener/` only) | `hooks-urbex.<domain>` | `hooks.urbex.<domain>` |
| Technitium's console (behind Access) | `dns-urbex.<domain>` | `dns.urbex.<domain>` |
| Grafana (behind Access) | `grafana-urbex.<domain>` | `grafana.urbex.<domain>` |
| Prometheus (behind Access; remote write not published) | `prometheus-urbex.<domain>` | `prometheus.urbex.<domain>` |
| Loki (behind Access; push not published) | `loki-urbex.<domain>` | `loki.urbex.<domain>` |
| Web frontend, prod / staging | `<project>-urbex`, `staging-<project>-urbex` | `<project>.urbex`, `staging.<project>.urbex` |
| Public service, prod / staging | `<service>-<project>-urbex`, `<service>-staging-<project>-urbex` | `<service>.<project>.urbex`, `<service>.staging.<project>.urbex` |

`flat` names are one level below the zone, which Cloudflare's free
certificate covers. `nested` names are two or more levels deep and need
the zone's Advanced Certificate Manager (paid), enabled by you.

## Addresses

With the defaults and `cidr: 192.168.1.0/24`:

| | VMID | IP |
|---|---|---|
| `urbex-gitea` | 9000 | 192.168.1.200 (`:3000` web, git, registry) |
| `urbex-komodo` | 9001 | 192.168.1.201 (`:9120` web/API) |
| `urbex-technitium` | 9002 | 192.168.1.202 (`:5380`) |
| `urbex-keycloak` | 9003 | 192.168.1.203 (`:8080`) |
| `urbex-observability` | 9004 | 192.168.1.204 (Grafana `:3000`, Prometheus `:9090`, Loki `:3100`) |
| `urbex-tunnel` (with Cloudflare) | 9005 | 192.168.1.205 (`cloudflared`) |
| VM template `urbex-vm-template` (if an application has `machine: vm`) | 9080-9089 | 192.168.1.208 while it is built |
| LXC template `urbex-template` | 9090-9099 | 192.168.1.209 while it is built |
| first project LXC or VM | 9100 | 192.168.1.210 |

Project LXCs and VMs get a VMID and an IP when first planned, recorded
in `state/allocations.json` in the GitOps repo, and keep them. The IP is
the lowest free one from the first project address (`.210`), never the
network's, its broadcast or the gateway: `urbex destroy` gives a
destroyed LXC's IP back for the next one. VMIDs only go forwards. When
no address is left in `network.cidr`, `urbex apply` says so.

The IPs must be free on the LAN: Urbex doesn't check, and nothing else
(DHCP included) should hand them out.

## Changing it

Edit, commit, and run `urbex bootstrap` again. What changes on existing
LXCs is what Terraform plans: a different storage pool replaces them,
which `urbex apply` refuses for an LXC with named volumes. `network.cidr`, `baseHostOffset`, and `vmIdBase` should
not change once LXCs exist.

### keyctl on a platform created before it was off

`proxmox.keyctl` used to default to `true`. A platform created with a
`root@pam` token and no `keyctl` line has the feature on its LXCs, and
the next `urbex bootstrap` or `urbex apply` turns it off. The change is
made in place, with no new LXC, and takes effect when each LXC next
restarts. To keep it on, add the line before running either command:

```yaml
proxmox:
  keyctl: true
```

A platform created with a non-root token already had `keyctl: false`,
and nothing changes for it; the line can go.
