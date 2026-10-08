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
| `domain` | required | The platform's domain: the Cloudflare zone public hostnames are created in, and the Gitea admin's e-mail domain. |
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
| `proxmox.network.dnsServers` | the gateway | Your LAN's resolvers. Every LXC resolves through Technitium first, then these; they are also Technitium's default forwarders (`dns.forwarders`). Unset, the gateway. Don't use a resolver the LXCs can't reach, such as Tailscale's MagicDNS (`100.100.100.100`). |
| `cloudflare.accountId`, `cloudflare.zoneId` | none | The Cloudflare account and the zone of `domain`. Set both to publish endpoints on Cloudflare ([ADR-0022](../decisions/0022-cloudflare-tunnel-access-workers.md)); leave both empty to keep everything on the LAN. Needs `URBEX_CLOUDFLARE_TOKEN`. |
| `cloudflare.name` | `urbex` | Last label of every public hostname, telling Urbex's apart from the zone's others. |
| `cloudflare.hostnames` | `flat` | How labels are joined - see [public hostnames](#public-hostnames). |
| `cloudflare.tunnelName` | `<name>-platform` | The Cloudflare Tunnel Urbex creates and routes through. |
| `cloudflare.access.emails` | required with Cloudflare | Who may open Gitea and Komodo through Cloudflare Access (one-time PIN sent to the address). |
| `cloudflare.quickTunnel` | `false` | Alternative to `cloudflare.accountId`/`zoneId` (mutually exclusive with them): a Cloudflare Quick Tunnel per `public: true` service, no account needed - see [ADR-0025](../decisions/0025-cloudflare-quick-tunnel.md) and its [known limitations](../known-limitations.md#public-endpoints-cloudflare). Doesn't apply to `frontend.type: web`. |
| `dns.zone` | `<cloudflare.name>.<domain>` | The zone Technitium serves the services' internal names in - `git.urbex.example.com`, `api.staging.acme-app.urbex.example.com` ([ADR-0027](../decisions/0027-service-conventions.md)). Technitium answers for the whole zone: keep nothing of yours under it on Cloudflare. |
| `dns.forwarders` | `proxmox.network.dnsServers`, or the gateway | IP addresses Technitium forwards every name outside `dns.zone` to. |
| `dns.technitiumUrl` | | ⚠️ Not used: `urbex` finds Technitium itself from the allocated LAN IP. |
| `keycloak.baseUrl`, `keycloak.platformRealm` (`platform`) | | ⚠️ Not used yet (SSO). |

## Public hostnames

With Cloudflare configured, Urbex publishes, under `domain`:

| | `flat` (default) | `nested` |
|---|---|---|
| Keycloak | `auth-urbex.<domain>` | `auth.urbex.<domain>` |
| Gitea (behind Access) | `git-urbex.<domain>` | `git.urbex.<domain>` |
| Komodo (behind Access) | `komodo-urbex.<domain>` | `komodo.urbex.<domain>` |
| Komodo webhooks (`/listener/` only) | `hooks-urbex.<domain>` | `hooks.urbex.<domain>` |
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
