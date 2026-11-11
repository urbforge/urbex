# ADR-0033: A VM for workloads that need keyctl, mount or fuse

## Status

Accepted. Decided by Teg79 on
[urbforge/urbex#66](https://github.com/urbforge/urbex/pull/66) on
2026-11-11, after Stefano's review. Drafted for
[urbforge/urbex#65](https://github.com/urbforge/urbex/issues/65), split
from [urbforge/urbex-cli#40](https://github.com/urbforge/urbex-cli/issues/40),
where a VM was agreed as the answer. It adds a second kind of machine
next to the LXC of [ADR-0009](0009-one-lxc-per-service-per-env.md) and
[ADR-0028](0028-application-model.md). Part of
[urbforge/redemptor#34](https://github.com/urbforge/redemptor/issues/34)
(E5 Security and isolation). Implemented by
[urbforge/urbex-cli#82](https://github.com/urbforge/urbex-cli/issues/82)
(VMs) and [#83](https://github.com/urbforge/urbex-cli/issues/83) (NAS
shares in a VM).

## Context

Every machine Urbex creates is an unprivileged LXC with `nesting`, which
is enough for Docker. Some workloads need more:

- the LXC features `keyctl`, `mount` (NFS or CIFS from inside the
  machine) or `fuse` (rclone, sshfs, some backup tools);
- a NAS share without an operator step. Today a share is a folder of
  the node bound into the LXC, which needs a `pct set` command run as
  root (ADR-0028, *Out of scope*).

Proxmox lets only `root@pam` set LXC features other than `nesting`, and
only root can bind a folder of the node. Urbex works with an API token
limited to its pool, and the home lab rule for Docker (2026-10-16) is
that LXCs are unprivileged, with only the features a non-root user can
set. There are no privileged LXCs, and no routine root steps on the
host. A VM in the pool has its own kernel: it mounts what it likes,
runs FUSE and has keyrings, with nothing asked of the node beyond what
a pool-scoped token may do.

The cost is memory and start time. The test node has 16 GB in total, and
the platform uses about 2.7 GB. An application's LXC takes about 200 MB
plus the application; a VM adds a kernel and its page cache, about
300-400 MB more, and boots in tens of seconds rather than a few.

## Decision

### How an application asks for a VM

An application declares the machine it runs on:

```yaml
services:
  - name: backup
    image: rclone/rclone
    version: "1.71"
    machine: vm          # lxc (default) | vm
```

- **`machine: vm`** is explicit. It doesn't come from a list of features
  such as `needs: [fuse]`. The reasons for a VM are open-ended: FUSE,
  a kernel module, a WireGuard interface, a share the machine mounts
  itself. A feature list would have to name each of them, and would
  hide a choice that costs memory. `apply` says when an application
  runs in a VM.
- **With `placement: stack`**, the stack shares one machine. It is a VM
  if any of its applications asks for one, and `apply` names the
  application that made it one.
- **Switching** an application between `lxc` and `vm` replaces its
  machine. Like any replacement, `apply` refuses it for a machine with
  named volumes, even with `--delete-data`. Moving the data is out of
  scope.
- **Base services** get the same choice in the service catalog
  (`internal/platform/catalog.go`), not in a config file. None needs a
  VM today.

### The image and the template

- **The operator provides the image once**, as they provide
  `proxmox.lxcTemplate` today. That image is the Debian 13 cloud image
  (`debian-13-genericcloud-amd64.qcow2`), on a storage with the
  `import` content type. They add it with *Download from URL* on the
  storage, which needs more than a pool-scoped token. A new field names
  it:
  ```yaml
  proxmox:
    vmImage: local:import/debian-13-genericcloud-amd64.qcow2
  ```
  The field is required only once an application asks for a VM.
  Without it, `apply` stops and says how to add the image.
- **`urbex bootstrap` builds the VM template** the first time an
  application needs one, as it builds the LXC template:
  - a VM in the pool, `urbex-vm-template`, whose disk is imported from
    `vmImage`;
  - cloud-init for the network and the platform's SSH key;
  - then the same Ansible roles: Docker, sops, the compose wrapper, the
    Periphery and Alloy images, and the QEMU guest agent.
  - It is turned into a template. Every new VM is a linked clone of it.
- **VMIDs** for the VM template are `vmIdBase+80` to `+89`, next to the
  LXC templates' `+90` to `+99`, with the same rule: a rebuild takes
  the next VMID, and the old template is removed once no VM is a clone
  of it. VMs for applications take their VMID and IP from
  `state/allocations.json`, like LXCs.
- **Before #82 starts**, the lab must show that a pool-scoped token can
  create a VM from that image. That means `import-from` a storage
  volume of content type `import`, with `PVEVMAdmin` and
  `PVEDatastoreUser`. If it can't, the operator converts the image into
  the template once, with a documented command, and the rest stays as
  decided.

### Sizing

A VM is sized by the application's `resources`, as an LXC is, with
defaults that suit a 16 GB node:

| | LXC (today) | VM |
|---|---|---|
| `cpu` | 1 | 1 |
| `memory` | `1Gi` | `1Gi`, and at least `1Gi`. Ballooning is on, down to half, so an idle VM gives memory back. |
| `disk` | `5Gi` | `8Gi`: the cloud image's root plus Docker's images |

The disks are virtio-scsi on `proxmox.storagePool`, with `discard` on so
that a thin pool gets freed space back. The CPU type is Proxmox's
default (`x86-64-v2-AES`) so that the VM can move to another node.

### How a VM follows ADR-0027

A VM is the same "Debian host with Docker and Komodo Periphery" as an
LXC, so every convention holds unchanged:

- **Deploy:** Periphery comes from the template, connects out to Komodo
  and is registered like an LXC's. Its Komodo server carries the
  application's kind tag (`app`, or `platform` for a base service).
- **Names:** cloud-init gives the VM its static IP from the allocation
  ledger and Technitium as its resolver. Urbex writes its record in the
  internal zone as for an LXC (`<service>.<project>.<zone>`).
- **Logs and resources:** Alloy from the template ships to Loki and
  Prometheus with the same labels (`kind`, the host name). The *Urbex
  resources* dashboard needs no change. In a VM the CPU idle counter is
  reliable, where in an LXC it isn't, and the busy-time formula gives
  the same answer either way.
- **Exposure:** the tunnel's routes and Access applications go to the
  internal name, so a VM is public, behind Access or internal exactly
  as an LXC is.
- **Access:** Ansible connects as `root` with the platform's SSH key,
  which cloud-init installs, as on an LXC.

### Storage

- **Named volumes are disks of the VM.** Each volume is one extra disk
  on `proxmox.storagePool`, with the disk's serial set to
  `<application>-<name>`, so it is found at
  `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_<serial>` whatever its
  order. Ansible formats a new one ext4 and mounts it with a systemd
  mount unit at `/srv/volumes/<application>/<name>`, the path an LXC
  uses. The rest of ADR-0028 holds:
  - the Docker named volume on that folder;
  - `lost+found` removed;
  - no start until the folder is a mount point;
  - grow only: Proxmox resizes the disk, and Ansible grows the
    filesystem online;
  - in Proxmox's backups: a VM's disks are included by default;
  - Terraform ignores the disks Urbex adds, as it ignores an LXC's
    mount points;
  - `--delete-data` for a delete, and a replacement refused.
- **Shares are mounted by the VM itself**, over NFS or SMB, with no
  `pct set`. A share gets a source for the VMs next to the node's
  path:
  ```yaml
  storage:
    shares:
      media:
        path: /mnt/pve/nas/media          # for LXCs: where the node mounts it
        nfs: nas.example.com:/export/media # for VMs, or:
        # smb: //nas.example.com/media
        # credentials: media              # SMB user and password, in SOPS
  ```
  - A share used by an LXC needs `path`; a share used by a VM needs
    `nfs` or `smb`, and `apply` says which one is missing.
  - The VM mounts it with a systemd mount unit at `/srv/shares/<name>`,
    read-only when the manifest says `readOnly`. It is remounted at
    every boot, and the application starts only once it is mounted, as
    with a bind mount today.
  - **SMB credentials** go in the GitOps repo's SOPS-encrypted secrets,
    under the platform, by the name `credentials` gives. Ansible writes
    them on the VM in a root-only file the mount reads. NFS uses the
    NAS's export rules; Kerberos is out of scope.
  - Urbex never changes or deletes what is on a share.

### E3-bis and other hosts

[urbforge/urbex#24](https://github.com/urbforge/urbex/issues/24) and
epic [urbforge/redemptor#32](https://github.com/urbforge/redemptor/issues/32)
make the host "a Debian machine with Docker and Periphery": an LXC on
Proxmox, a VM on a cloud provider, or a server reached over SSH. A
Proxmox VM is the first non-LXC host, and it is built so that the
others reuse it:

- the Ansible that provisions a VM assumes a whole Debian machine
  rather than an LXC. That is what a cloud VM and an SSH server are, so
  the same roles serve them;
- named volumes as disks map to a cloud provider's block volumes (a
  Hetzner Volume), and shares mounted by the machine work the same on a
  VPS;
- `machine` is a Proxmox choice. On other hosts every machine is a VM
  or a server, and `machine: lxc` is refused there.

## Rationale

- **A VM rather than a privileged LXC or root steps.** A privileged LXC
  runs as root on the host. Setting `keyctl`, `mount` or `fuse`, or
  binding a folder, needs `root@pam`. Both break the rule that Urbex
  works with a pool-scoped token and that the home lab has no routine
  root steps. A VM needs neither.
- **The LXC stays the default.** It starts in seconds, costs about
  200 MB, and covers almost every application, so the VM is opt-in and
  says what it costs.
- **An explicit field rather than features** (see above), for an open
  list of reasons and a visible cost.
- **The operator provides the image**, as with the LXC template: getting
  files onto the node is the one thing the token can't do, and it
  happens once.
- **The same paths and the same rules for volumes and shares** on an LXC
  and a VM. Applications, the compose files and the docs don't need to
  know which one they run on.

## Out of scope

- **Privileged LXCs**, and LXC features or bind mounts set as root, as
  a routine. A one-off `pct set` by an administrator stays a workaround
  (known limitations).
- **Passing a GPU or a device to a VM.** That is PCI passthrough, which
  needs root on the node (a resource mapping), as it does for an LXC.
- **Another OS** than Debian 13, and Windows.
- **Moving an application's data** between an LXC and a VM.
- **Live migration and HA** of VMs: one node (known limitations).
- **Kerberos** for NFS, and SMB credentials outside SOPS.

## Consequences

- `urbex.yaml` gets `machine` (`lxc` by default, or `vm`), and the
  schema with it. `urbex.platform.yaml` gets `proxmox.vmImage` and, per
  share, `nfs`, `smb` and `credentials`. Every current file stays
  valid.
- **urbforge/urbex-cli#82** builds the VM template and the VMs, with
  their volumes as disks and their place in Komodo, Technitium and
  Grafana, and `status`, `destroy` and `teardown` for them. Its first
  step is the lab check of `import-from` with the pool-scoped token.
- **urbforge/urbex-cli#83** adds the shares' `nfs` and `smb` sources,
  the SOPS credentials and the mount units, with no `pct set` for a VM.
- The docs follow those PRs: the manifest and platform config
  references, platform resources (the VM template), the cookbook (an
  application in a VM, a share over NFS or SMB), status and known
  limitations.
- A VM costs about 300-400 MB more than an LXC and boots slower. On a
  16 GB node that limits it to the applications that need it.
