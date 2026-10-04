# ADR-0025: Cloudflare Quick Tunnel as a no-account alternative

## Status

Accepted. Complements [ADR-0022](0022-cloudflare-tunnel-access-workers.md)
(public endpoints on Cloudflare); does not alter it.

## Context

Public reachability, as specified in [ADR-0022](0022-cloudflare-tunnel-access-workers.md),
presupposes `cloudflare.accountId` and `cloudflare.zoneId`: a domain
registered on a Cloudflare account. This precondition was tested
end-to-end on a Proxmox node, reproducing the CLI user journey from an
unprivileged client machine, absent any existing Cloudflare account or
domain.

Findings:

1. `urbex bootstrap` and `urbex apply` complete successfully, and the
   project's service is reachable on its LAN address.
2. Public reachability of a `public: true` service, from outside the
   LAN, cannot be obtained without first acquiring a domain, creating a
   Cloudflare account, and provisioning a scoped API token (see
   [credentials](../reference/credentials.md#cloudflare-api-token)).

This dependency is orthogonal to the correctness of Urbex itself; it
concerns exclusively the acquisition of Cloudflare infrastructure. An
alternative requiring neither, [Cloudflare Quick
Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/do-more-with-tunnels/trycloudflare/)
(`cloudflared tunnel --url`), was evaluated against the same deployed
service (a Go API) and found functional: it yields a
`https://*.trycloudflare.com` hostname reachable from any browser,
without Cloudflare account involvement.

This ADR does not propose Quick Tunnel as a substitute for ADR-0022 in
production (see [Consequences](#consequences)). Its purpose is to
remove the Cloudflare-account precondition for evaluation, demonstration,
and local development.

## Decision

### Scope

Quick Tunnel applies exclusively to `public: true` **services** (one
LXC, one port). `frontend.type: web` is out of scope: it is deployed as
a Cloudflare Worker (ADR-0022), a construct meaningless absent a
Cloudflare account. A web frontend therefore continues to require
`cloudflare.accountId`/`zoneId` irrespective of this ADR.

### Configuration

A platform setting is introduced, mutually exclusive with the
account/zone pair:

```yaml
cloudflare:
  quickTunnel: true   # alternative to accountId/zoneId, not both
```

`platform.Config.Validate` rejects a configuration setting both.

### One sidecar per public service

ADR-0022's named tunnel is a single connector with remotely configured
routes, able to front multiple hostnames. A Quick Tunnel is anonymous
and corresponds to exactly one local origin; it cannot multiplex
hostnames behind one connector. Consequently, each `public: true`
service is assigned its own `cloudflared` container, on its own service
LXC, managed by a new Ansible role (`quicktunnel`) alongside the
existing `periphery` and `telemetry` roles. Komodo's management of the
application's own compose stack, deployed from the GitOps repo, is
unaffected.

- `urbex apply` places the LXCs of newly public services into a
  `public_service` inventory group, empty (and therefore a no-op play)
  when `cloudflare.quickTunnel` is unset or Cloudflare is configured.
- The role runs `cloudflared tunnel --url http://localhost:$PORT
  --metrics 0.0.0.0:49399 --no-autoupdate`, with `network_mode: host`,
  so that `localhost` resolves to the port published on the LXC by
  Komodo's compose file.

### Retrieval of the generated hostname

cloudflared's metrics server exposes `GET /quicktunnel`, returning the
hostname assigned to the tunnel. This is the documented, scriptable
means of retrieval, there being no account against which to query the
tunnel. The hostname is read live and never persisted to the GitOps
repo or the allocation ledger: a Quick Tunnel is assigned a new
hostname on every container restart, rendering any stored value
unreliable.

- `urbex apply` queries the endpoint immediately after the role starts,
  with bounded retry.
- `urbex status` queries it again, with a short timeout, alongside the
  LAN address. A failed query, indicating the absence of a sidecar on
  that LXC, is treated as absence of data, not as an error.

### Presentation

Every output that prints a Quick Tunnel URL, in `apply`'s summary and
in `status`, states its limitations inline, rather than deferring to
documentation.

## Rationale

- Excluding the sidecar from Komodo's management preserves the
  invariant that enabling `cloudflare.quickTunnel` on a `public: true`
  service alters only its reachability, not how it is built, deployed,
  or rolled back.
- A dedicated `cloudflared` process per public service, rather than one
  shared connector, reflects the absence of an ingress or routing layer
  in the Quick Tunnel mechanism, unlike ADR-0022's named tunnel.
- Live retrieval, rather than persistence, is the only approach
  consistent with a hostname that is not guaranteed stable across
  restarts.

## Consequences

- **The hostname is not stable.** It changes whenever the sidecar
  container is recreated: an LXC reboot, a manual restart, or a
  redeployment that alters the compose file `quicktunnel` renders (for
  instance a different port). A plain `urbex apply` re-application was
  verified not to trigger this: `docker compose up -d` is idempotent, so
  re-running it against an unchanged compose file leaves the sidecar
  untouched and the hostname unchanged. No external reference to the
  hostname can be relied upon regardless, since the operator does not
  control when a recreation of some kind occurs.
- **Recovery after disruption is not guaranteed.** A Quick Tunnel that
  loses its connection to Cloudflare's edge, observed following a
  client-side network interruption during testing, does not reliably
  reconnect and may require the container to be restarted.
- **No authentication is provided.** Unlike Access in front of Gitea
  and Komodo (ADR-0022), any party possessing the URL can reach the
  service. This is acceptable for demonstration purposes and
  unacceptable for any deployment handling real data or users.
- One additional container per public service's LXC; resource
  consumption is negligible.
- The mechanism must never constitute the sole means of reaching a
  production environment; the CLI's own output asserts this on every
  invocation that prints a Quick Tunnel URL.
