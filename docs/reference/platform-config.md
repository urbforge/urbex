# Platform config reference (`urbex.platform.yaml`)

`urbex.platform.yaml` is at the root of the GitOps repo and describes the
platform: the Proxmox server, the network, the domain. `urbex bootstrap`
writes a starter one the first time; every command reads it. It holds no
secrets - those are [credentials](credentials.md).

## Example

```yaml
domain: acme.example

git:
  giteaUrl: https://git.acme.example
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
  keyctl: false
  network:
    cidr: 192.168.1.0/24
    gateway: 192.168.1.1
    baseHostOffset: 200
    bridge: vmbr0
    dnsServers: [192.168.1.1]
```

## Fields

| Field | Default | Meaning |
|---|---|---|
| `domain` | required | The platform's public domain. ⚠️ Today only used for the Gitea admin's e-mail address; DNS and ingress will use it. |
| `git.giteaUrl` | required | The public URL Gitea will have. ⚠️ Not used yet: Urbex reaches Gitea at `http://<its IP>:3000`. |
| `git.org` | `urbex` | Gitea organization holding the GitOps repo (`<org>/gitops`), every project repo (`<org>/<project>`), and their images (`<ip>:3000/<org>/<project>-<service>`). |
| `proxmox.apiUrl` | required | Proxmox API URL, ending in `/api2/json`. |
| `proxmox.insecure` | `false` | Skip TLS verification of the Proxmox API (its default certificate is self-signed). |
| `proxmox.node` | required | The node every LXC is created on. |
| `proxmox.storagePool` | `local-lvm` | Storage for the LXCs' root disks. |
| `proxmox.lxcTemplate` | required | The Debian 13 template volume, e.g. `local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst` (`pveam list local` shows yours). |
| `proxmox.sshPublicKey` | required | Public key installed for `root` on every LXC; Ansible connects with the matching private key, from your SSH agent. |
| `proxmox.vmIdBase` | `9000` | First VMID: base services get `vmIdBase` to `+4`, project LXCs `vmIdBase+100` onwards. |
| `proxmox.pool` | none | Resource pool every LXC goes in. Required when the API token's permissions are on a pool. |
| `proxmox.keyctl` | `true` | Enable the LXC `keyctl` feature Docker needs on most hosts. Only `root@pam` may set it: with any other token, set `false`. |
| `proxmox.network.cidr` | required | LAN the LXCs are on; their static IPs are taken from it. |
| `proxmox.network.gateway` | required | Default gateway of the LXCs. |
| `proxmox.network.baseHostOffset` | `200` | Host number of the first base service's IP (`.200` in a /24). Base services take 5 addresses from there; project LXCs start 10 after it (`.210`). |
| `proxmox.network.bridge` | `vmbr0` | Proxmox bridge the LXCs attach to. The API token needs `SDN.Use` on it (see [credentials](credentials.md#proxmox-api-token)). |
| `proxmox.network.dnsServers` | the host's | Nameservers of the LXCs. Unset, each LXC copies the Proxmox host's `resolv.conf` - which breaks when the host resolves through something the LXCs can't reach, such as Tailscale's MagicDNS (`100.100.100.100`): set your router or another LAN resolver. |
| `cloudflare.accountId`, `cloudflare.zoneId`, `cloudflare.tunnelName` | | ⚠️ Not used yet (ingress). |
| `dns.technitiumUrl` | | ⚠️ Not used yet (DNS records). |
| `keycloak.baseUrl`, `keycloak.platformRealm` (`platform`) | | ⚠️ Not used yet (SSO). |

## Addresses

With the defaults and `cidr: 192.168.1.0/24`:

| | VMID | IP |
|---|---|---|
| `urbex-gitea` | 9000 | 192.168.1.200 (`:3000` web, git, registry) |
| `urbex-komodo` | 9001 | 192.168.1.201 (`:9120` web/API) |
| `urbex-technitium` | 9002 | 192.168.1.202 (`:5380`) |
| `urbex-keycloak` | 9003 | 192.168.1.203 (`:8080`) |
| `urbex-observability` | 9004 | 192.168.1.204 (Grafana `:3000`, Prometheus `:9090`, Loki `:3100`) |
| first project LXC | 9100 | 192.168.1.210 |

Project LXCs get the next free VMID and IP when first planned, recorded
in `state/allocations.json` in the GitOps repo, and keep them. A
destroyed LXC's addresses are not reused.

The IPs must be free on the LAN: Urbex doesn't check, and nothing else
(DHCP included) should hand them out.

## Changing it

Edit, commit, and run `urbex bootstrap` again. What changes on existing
LXCs is what Terraform plans: a different template or storage pool
replaces them. `network.cidr`, `baseHostOffset`, and `vmIdBase` should
not change once LXCs exist.
