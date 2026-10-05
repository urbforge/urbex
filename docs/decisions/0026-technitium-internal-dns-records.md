# 0026. Technitium internal DNS records

## Status

Accepted. Replaces the hostname scheme sketched in
[ADR-0007](0007-technitium-configurable-domain.md) (Technitium itself
and the configurable domain stand).

## Context

[ADR-0007](0007-technitium-configurable-domain.md) put a dedicated
Technitium LXC on the platform, but nothing registered a name in it: a
service was only reachable by its LAN IP, which `urbex status`/`apply`
print but which changes if the service is destroyed and recreated.
Every other workflow - curling a staging API, pointing a test client at
a service, reaching one service from another on the LAN - meant looking
up that IP first.

## Decision

`urbex bootstrap` and `urbex apply`/`destroy` register internal DNS
records in Technitium, independently of whether Cloudflare is
configured:

- **One zone, the platform's own domain.** `urbex bootstrap` creates a
  Primary zone in Technitium named after `domain` in
  `urbex.platform.yaml` - the same domain Cloudflare publishes public
  hostnames under, not a separate `.internal` suffix. Technitium
  answers it on the LAN; Cloudflare answers it on the internet: the
  same FQDN resolves differently depending on who asks (split-horizon
  DNS), rather than inventing a second naming scheme to remember.
- **Hostnames are shared with the public ones.** A service's internal
  name is exactly what [`PublicHostname`](0022-cloudflare-tunnel-access-workers.md)
  would publish for it on Cloudflare (flat or nested, per
  `cloudflare.hostnames`) - `api-staging-acme-app-urbex.<domain>`, say -
  whether or not Cloudflare is actually configured. One name per
  service, same on both sides of the split horizon.
- **Credentials.** Bootstrap sets `DNS_SERVER_ADMIN_PASSWORD` on
  Technitium's container from a generated secret
  (`URBEX_TECHNITIUM_ADMIN_PASSWORD`), lets it answer non-interactively,
  then mints an API token (`URBEX_TECHNITIUM_TOKEN`) with it - the same
  pattern as Gitea's and Komodo's admin tokens. Technitium only honors
  that environment variable while it has no configuration yet (its own
  behavior, not urbex's): on a platform that already had Technitium
  configured before this feature existed, the stored admin password
  doesn't change by re-running bootstrap - see
  [known limitations](../known-limitations.md).
- **Record lifecycle.** `urbex apply <env>` sets an A record for every
  declared service pointing at its allocated LAN IP, after publishing
  on Cloudflare; `urbex destroy <env>` removes them, before the LXCs
  are destroyed. Both are idempotent: creating a zone or record that
  already exists, or deleting one that's already gone, isn't an error.
- **Independent of Cloudflare.** Registration doesn't depend on
  `cloudflare.accountId`/`zoneId` being set: a platform with no
  Cloudflare account still gets working internal names, which is the
  only way most LAN-only deployments will ever resolve a service by
  name rather than IP.

## Consequences

- Services are reachable by a stable name on the LAN, independently of
  which IP Terraform happened to allocate, and that name is the same
  one used publicly if the platform also has Cloudflare configured.
- Technitium needs to be reachable from wherever DNS lookups happen
  (the LAN, or a tunnel/VPN that proxies DNS traffic too - some
  userspace proxies only forward TCP, which breaks a plain UDP lookup
  without affecting Technitium itself).
- A platform bootstrapped before this ADR keeps its original
  Technitium admin password; the operator has to tell urbex what it is
  once (`urbex secret set technitiumAdminPassword` style seeding into
  `~/.urbex/credentials.yaml`) for token minting to succeed, since
  bootstrap can't rotate a password Technitium itself won't accept a
  new value for.

## Out of scope

- **Base-service LXCs** (`urbex-gitea`, `urbex-komodo`, etc.) don't get
  a record of their own - only project services, registered by
  `urbex apply`. Reach the base services by the LAN IPs `urbex status`
  prints, or by their public hostnames with Cloudflare configured.
- **No opt-out.** Unlike Cloudflare, there's no flag to disable
  internal DNS registration - Technitium is always part of the base
  platform ([ADR-0007](0007-technitium-configurable-domain.md)), so
  there's nothing to opt out of using.
- **DNSSEC, record TTL tuning, secondary zones**: the zone is a plain
  Primary zone, unsigned, with a fixed TTL - not configurable.
