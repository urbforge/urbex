# ADR-0007: Technitium for internal DNS, configurable domain

## Status

Accepted

## Context

A way is needed to register and resolve the services created on Proxmox
("DNS to register the various services"). In addition, Urbex must be
usable by anyone with their own Proxmox and their own domain, not just by
the original maintainer: the public domain cannot be hardcoded.

## Decision

- **Technitium DNS**, on a dedicated LXC, for internal name resolution
  between services on the Proxmox network (e.g.
  `api.staging.<project>.internal`).
- The **public domain** used for exposed endpoints (via Cloudflare
  Tunnel, see [ADR-0005](0005-cloudflare-tunnel-ingress.md)) is a
  **configuration parameter** of the platform (set once during `urbex
  bootstrap` or global configuration), never a value fixed in the code.

## Rationale

- Technitium exposes a REST API, automatable from Terraform/Ansible to
  register new records at every provisioning step, consistent with the
  GitOps approach.
- Making the domain configurable is an explicit requirement: "urbex must
  be usable by anyone, so the domain must be specifiable in the
  configuration".

## Consequences

- Urbex's global configuration (not the individual app's manifest) must
  include: base domain, Cloudflare zone/account, Proxmox credentials. A
  file/location for this platform configuration needs to be defined
  (e.g. `urbex platform.yaml`, to be refined during technical design).
- Project environments derive their hostnames from the configured domain:
  `<service>.<env>.<project>.<base-domain>`.
- In the absence of a real configured domain, Urbex must still be able to
  operate in a purely internal scope (Technitium only, no public tunnel)
  — useful for developing/testing the platform itself.
