# ADR-0036: Backups and restore of the platform and the projects' data

## Status

Proposed; amended by its first implementation task
(urbforge/urbex-cli#121): the Proxmox layer runs with a dedicated
backup token, not the platform's (point 3), and Komodo's database is
dumped with Komodo's own backup (point 1). The first task of E3, *Backups and restore*
(urbforge/redemptor#31); the implementation tasks follow it. Builds on
[ADR-0027](0027-service-conventions.md) (every service through Komodo,
monitored in Grafana), [ADR-0028](0028-application-model.md) (named
volumes), [ADR-0030](0030-postgresql-application.md) (a PostgreSQL
per project, a role and a schema per application) and
[ADR-0033](0033-vm-for-keyctl-mount-fuse.md) (VMs with the QEMU guest
agent). Two layers: Proxmox's vzdump, to Proxmox Backup Server or any
vzdump storage, for whole machines; restic for databases and volumes,
off-site, and on a VPS.

## Context

Nothing backs up a platform or its projects' data today. What exists:

- named volumes are Proxmox mount points with `backup=1`, so Proxmox's
  own backups (vzdump, or Proxmox Backup Server) include them - tested
  in urbforge/urbex-cli#49. That is a node-level restore: it isn't
  consistent for a running database, it doesn't leave the node unless
  the administrator set it up, and a VPS (E3-bis) has no vzdump;
- the GitOps repo is on the forge and in the operator's working copy;
  `credentials.yaml` and the age key only on the operator's machine.

What a platform holds that can't be recreated:

| Where | What | Today |
|---|---|---|
| Forgejo (`urbex-gitea`, volume `gitea-data`) | the GitOps repo, the projects' repos, the container registry, its SQLite database | none |
| Komodo (`urbex-komodo`) | its database: FerretDB on PostgreSQL (DocumentDB) - Builds, Stacks, Procedures, variables | none |
| Keycloak (`urbex-keycloak`) | its PostgreSQL: the projects' realms, users and roles | none |
| A project's PostgreSQL (ADR-0030) | the applications' data, a schema each | vzdump only |
| Named volumes | the applications' files | vzdump only |
| The operator | `credentials.yaml`, the age key | none |

What doesn't need backing up: Technitium's records (bootstrap and apply
write them again), Grafana's dashboards and alerts (provisioned from the
GitOps repo), the metrics and logs in Prometheus and Loki (they have a
retention of their own), the tunnel (Cloudflare's), the LXC template.

Homelab owners (selfh.st 2026, urbforge/redemptor#49): 10% have no
backup; 67% have a NAS; of those using cloud storage, Backblaze 30%,
Hetzner 19%, Cloudflare R2 5%.

## Decision

1. **What is backed up, made consistent before it is copied:**
   - **Forgejo**: its `/data` - repositories, registry and database -
     with a consistent copy of its SQLite database taken first (SQLite's
     backup command, or `forgejo dump`'s export). The registry is included: a release's images can't be
     rebuilt identically, and promote relies on them.
   - **Komodo**: its database, with Komodo's own backup
     (`BackupCoreDatabase`: compressed JSON lines in `/etc/komodo/backups`
     on its LXC, restored with Komodo's CLI), rather than a `pg_dump` of
     the DocumentDB database or a `mongodump` through FerretDB: it is
     the format Komodo supports restoring.
   - **Keycloak**: `pg_dump` of its PostgreSQL.
   - **A project's PostgreSQL**: `pg_dump` of each database, in the
     custom format, so one application's schema can be restored alone.
     Logical, not physical: it restores into a newer major too.
   - **Named volumes**: their files, as they are when copied
     (crash-consistent). An application whose files need a quiet moment
     declares a command to run before (`backup.before` in `urbex.yaml`,
     e.g. a flush); a volume can opt out (`backup: false`), e.g. a cache.
   - **For a rebuild**: the GitOps repo comes back with Forgejo, and a
     copy of `credentials.yaml` goes into the backups too. Both are
     encrypted (point 4).
2. **Two layers, each optional, configured apart** in
   `urbex.platform.yaml` (`backups.proxmox`, `backups.files`), and
   meant to be used together on Proxmox:

   | | **Proxmox layer**: vzdump, to PBS or any vzdump storage | **File layer**: restic |
   |---|---|---|
   | What | whole machines: urbex's LXCs and VMs, the OS, the mount points with `backup=1` | the dumps and the volumes of point 1, `credentials.yaml` |
   | Restores | a whole machine, as it was | a database, one application's schema, a volume, a file |
   | Where | a storage on the node the operator names | an S3-compatible bucket, or a path |
   | Off the node | if the storage is (a PBS elsewhere, an NFS share) | yes, by design |
   | On a VPS (E3-bis) | no: there is no Proxmox | yes, the only layer |

   Recommended on Proxmox: both - the Proxmox layer for fast whole-machine
   restores, the file layer for granular, off-site copies. On a VPS, the
   file layer.

3. **The Proxmox layer: vzdump through the Proxmox API**, with a
   **dedicated backup token** (`proxmoxBackupToken`, no `root@pam`):
   it is scheduled by Komodo, so a token must be kept on the platform,
   and the platform's token - which creates and destroys the pool's
   machines - never leaves the operator's workspace. The backup token
   may only see and back up the pool's machines and write to the named
   storage. A whole-machine restore, run by `urbex restore` from the
   workspace, uses the platform's token.
   - **What**: every machine of the platform's pool, or a subset
     (`backups.proxmox.machines`: `platform`, `projects`, or both).
     Never another guest: only the pool's VMIDs are passed to vzdump.
   - **Target**: `backups.proxmox.storage`, a storage the operator names -
     a Proxmox Backup Server datastore added to the node, or any storage
     whose content includes `backup` (an NFS share, a directory). **Never
     a default**: without it the Proxmox layer is off, and `doctor` says
     so. In a real setup **the PBS runs on a dedicated device or another
     host, never on the node it backs up**: a PBS on the same node is
     lost with it, and is only for testing.
   - **Adding the storage to Proxmox** (Datacenter > Storage) needs
     privileges the platform's pool-scoped token doesn't have
     (`Datastore.Allocate` on `/storage`, `Sys.Modify`). Two ways, both
     documented:
     - **by hand, once, by the operator** - the default, least
       privilege: add the PBS storage (address, datastore, the PBS
       user's token, the fingerprint), then grant the backup token
       `Datastore.AllocateSpace` and `Datastore.Audit` on it;
     - **with a separate, more privileged Proxmox token**, used only for
       that setup step (`urbex backup setup-proxmox` or its documented
       API calls) and **never stored on the platform** - passed in the
       environment for that one command.

     Either way, the backup token only ever needs `Pool.Audit`,
     `VM.Audit` and `VM.Backup` on the pool and `Datastore.AllocateSpace`/`Datastore.Audit`
     on that storage. The separate setup token is not implemented yet: the
     storage is added by hand.
   - **Mode**: `snapshot` by default (no downtime; on ZFS or LVM-thin a
     storage snapshot, on PBS its incremental, deduplicated format);
     `suspend` or `stop` per machine when asked (`backups.proxmox.mode`).
     A snapshot of a running database is only crash-consistent, so
     before each run **urbex dumps the databases into their volumes**
     (point 1's dumps, through Komodo), and the snapshot holds a
     consistent dump next to the live files. VMs (ADR-0033) have the
     QEMU guest agent: vzdump freezes their filesystems (fsfreeze) for
     the snapshot; Proxmox freezes an LXC's filesystem during its
     snapshot too. Per-guest hookscripts aren't used: setting one needs
     `root@pam`.
   - **Token permissions**: `Pool.Audit` and `VM.Audit` (to list the
     pool's machines: Proxmox names a machine's pool only with
     `Pool.Audit`) and `VM.Backup` on the pool, and `Datastore.AllocateSpace` (plus
     `Datastore.Audit`, to list the backups) on the named storage. `urbex doctor` checks them, and
     bootstrap's Proxmox preparation documents the one extra grant on
     the storage.
   - **Scheduling**: by Komodo, like every other platform job (point 6):
     a Procedure runs the dumps, then calls the API's `vzdump` for the
     pool's machines and waits for the task. A Proxmox backup job
     (Datacenter > Backup) is the alternative the operator may prefer,
     but creating one needs privileges on `/` that a pool-scoped token
     doesn't have: urbex documents it and doesn't create it.
   - **Retention**: `backups.proxmox.keep`, passed to vzdump's
     `prune-backups` (a PBS datastore may also prune on its own).
   - **Restore**: a whole machine, through the API (`restore` from the
     backup volume onto the same VMID, with `force`), by `urbex restore
     <env|platform> --machine <name> --from proxmox [--at <time>]`. The
     machine comes back as it was at the backup; the databases' dumps in
     it are there for a consistent restore of the data if the live files
     aren't. PBS's own file-level restore stays available in Proxmox's UI.

4. **The file layer: restic**, run by Komodo (ADR-0027). A `backup`
   Stack on each machine that holds data - the platform's forge, Komodo
   and Keycloak, a project's LXCs with a database or named volumes -
   runs the dumps, then `restic backup` of the dumps and the volumes. A
   Komodo Procedure runs them on a schedule, one machine after another.
   restic rather than borg or kopia: a single binary, S3 and local
   targets alike, deduplication, encryption by default, `restic check`
   to verify, and the widest use among self-hosters' tools. Its target,
   `backups.files.target`:
   - **an S3-compatible bucket** - Backblaze B2, Hetzner Object Storage,
     Cloudflare R2, MinIO on a NAS. The recommended target, off the
     node;
   - **a path** - a NAS share mounted on the Proxmox node and passed to
     the backup Stacks as a share (urbforge/urbex-cli#83), or a local
     disk.

   **No silent default here either**: with neither layer configured,
   nothing is backed up, and `urbex status` and `urbex doctor` say so.

5. **Encryption and keys**: the file layer has one restic repository per
   platform, with a random password generated by bootstrap into
   `credentials.yaml` (`backupPassword`); the Proxmox layer is encrypted
   if the PBS datastore is (its key is PBS's, managed in Proxmox). **Two
   secrets live outside the platform, kept by the operator** - in a
   password manager, not on the node: the age key and the backup
   password. With them, the file layer rebuilds everything,
   `credentials.yaml` included. Without the backup password the restic
   backups can't be read: bootstrap prints it once, `urbex doctor` warns
   until the operator confirms it is stored, and the docs say what is
   lost with it.

6. **Schedule and retention**, defaults in `urbex.platform.yaml`,
   overridable per application in `urbex.yaml`:
   - every day at 03:00, node time: first the dumps, then the Proxmox
     layer, then the file layer - one Komodo Procedure;
   - the file layer keeps 7 daily, 4 weekly and 6 monthly snapshots
     (`restic forget`), pruned once a week, `restic check` of a sample
     once a month; the Proxmox layer keeps the same counts by default
     (`prune-backups`).

7. **Restore** - restoring is never automatic:
   - `urbex restore <env> [--app <app>] [--at <time>]`: a project's
     data - its databases and volumes, or one application's - from the
     file layer, at or before `--at` (default the latest). It stops the
     application, restores, starts it again.
   - `urbex restore <env|platform> --machine <name> --from proxmox
     [--at <time>]`: a whole machine from the Proxmox layer (point 3).
   - `urbex restore platform [--at <time>]`: the forge, Komodo and
     Keycloak's data, into a running platform.
   - **A full-loss drill** - a new node, the two secrets and the bucket,
     nothing else:
     1. `urbex bootstrap --restore` creates the platform and restores the
        forge, which brings the GitOps repo back, then Komodo and
        Keycloak;
     2. `urbex apply <env>` for each environment of the restored GitOps
        repo;
     3. `urbex restore <env>` for each.

     If the node is lost but a PBS elsewhere survives, the machines can
     be restored from it instead, with the Proxmox layer. The drill is
     documented step by step and run on the test node before the E3 epic
     closes.

8. **Monitoring and `status`/`doctor`**: each run writes, per machine and
   per layer, the time of its last successful backup and its size, which
   the telemetry agent sends to Prometheus; the Proxmox layer's also
   comes from the storage's list of backups. A Grafana alert fires when a
   machine's last success in a configured layer is older than 36 hours,
   or a run failed, through the channels of urbforge/urbex-cli#95.
   `urbex status` shows each machine's last backup of each kind
   (`proxmox`, `files`); `urbex doctor` checks each configured layer: the
   storage exists and the token may write to it, the bucket or path
   answers, the password is set.

9. **VPS (E3-bis)**: the file layer depends on nothing of Proxmox -
   restic, Komodo, S3 or a path. On a VPS the Proxmox layer doesn't
   exist, and the file layer's copies are the only ones: its target must
   be off the host.

## Rationale

- Dumps where a database is involved, because a copy of a running
  database's files isn't one it can restore from; files where they
  aren't, because that is what the application wrote.
- Two layers because they restore different things: vzdump/PBS brings a
  whole machine back in minutes, the way Proxmox users already work, but
  only on Proxmox and only as far off the node as its storage is; restic
  restores one database or volume, goes off-site by design, and is the
  only option on a VPS. Neither alone covers both.
- The Proxmox layer through the API, scheduled by Komodo, because a
  pool-scoped token may back up and restore its own machines but may not
  create a cluster backup job; it also keeps urbex's machines, and only
  them, in the backup. A dedicated token, because the one kept on the
  platform should be able to back up and nothing more.
- Running restic through Komodo keeps backups like every other service:
  deployed from the GitOps repo, visible and scheduled in Komodo, logged
  in Loki - and the same on Proxmox and on a VPS.
- S3-compatible storage covers the cloud targets homelabs use and a NAS
  running MinIO; a path covers a NAS share directly.
- One restic repository per platform deduplicates across machines, and
  the two secrets kept outside are the minimum a rebuild from nothing
  needs.

## Consequences

- New: a `backup` Stack on the machines with data; `backups.proxmox`
  and `backups.files` in `urbex.platform.yaml`; `backup`/`backup.before`
  in `urbex.yaml`; `backupPassword` in the credentials; `urbex restore`
  (file layer, and `--machine ... --from proxmox`); the backup metrics,
  alert and status lines, per layer.
- The Proxmox layer needs one extra grant on the storage the operator
  names (`Datastore.AllocateSpace`, `Datastore.Audit`) besides
  `VM.Backup` on the pool; urbex never writes to a storage it wasn't
  given.
- The operator must store two secrets off the platform. The docs and
  `doctor` insist on it.
- A restore of a project's data stops its applications while it runs.
- Backups cost storage and the node's disk and network once a day;
  deduplication keeps the daily cost to what changed.
- Implementation tasks under E3, in this order:
  1. the dumps of the databases, and the Proxmox layer (vzdump to a named
     PBS or vzdump storage, via Komodo; whole-machine restore);
  2. the file layer for the platform (forge, Komodo, Keycloak,
     `credentials.yaml`), `backups.files.target`, the password;
  3. the file layer for the projects' data (PostgreSQL dumps, named
     volumes) and `urbex restore`;
  4. the full-loss drill;
  5. monitoring (metrics, alert, `status` and `doctor` per layer).
