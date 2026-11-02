# ADR-0031: Readiness between stacks, the wait and the reconciler

## Status

Accepted. Decided by Teg79 on
[urbforge/urbex-cli#43](https://github.com/urbforge/urbex-cli/issues/43)
on 2026-11-01 (option D, with the crash loop handled before the review).
Settles what [ADR-0028](0028-application-model.md), "Order between
stacks", left to that issue, and how [ADR-0030](0030-postgresql-application.md)'s
applications wait for their provider. Part of
[urbforge/redemptor#17](https://github.com/urbforge/redemptor/issues/17)
(E2 Databases).

## Context

ADR-0028 decided that an application which `uses` another does not
start until that application is healthy, and that a component of Urbex
in the Stack holds it back. Each application is its own Komodo Stack, on
its own LXC, so Docker Compose cannot order them; `depends_on` works only
inside one compose file.

Holding back the first start is not enough. A provider can come back
after the consumer's wait gave up, a change can be pushed while the
provider is down, the node can reboot, and a provider can fall into a
crash loop. Each of these needs the consumer to be deployed again later,
which a component that runs once at start cannot do.

Four designs were compared on a proof of concept (`e2e/poc-deps` in
`urbex-cli`) and on the end to end test, with Komodo 2.3.4.

| Option | How the consumer learns that the provider is healthy | Why it was not chosen |
|---|---|---|
| A | A container in the consumer's Stack asks Komodo (`InspectStackContainer`) | Every Stack needs a Komodo API key; the key travels in plain HTTP on the LAN; `InspectStackContainer` returns the provider's environment, passwords included |
| B | An agent in every Stack exposes its own state and reads the others' | A new service with the Docker socket that also listens on the network, equivalent to root on the LXC; an image to build, sign and maintain |
| C | The wait reads `container_health_state` from Prometheus | The scrape interval makes the data old; it reported a provider ready for about 9 s after it stopped and for 86 s out of 90 during a crash loop, and a deploy failed while Prometheus was down |
| D | The wait probes the provider directly, as the consumer will reach it | Chosen |

The proof of concept showed, first, that a probe of the TCP port is not
enough, since the order broke, with 34 restarts. A wait that probes the
provider's own answer, and a driver that asks Komodo, both kept the
order, and both held back only what used a broken provider. The measures
M1 to M4 were then taken on the first version of D, which accepted a
single good answer. After a restart or a recreation of the
provider, the probe reported it not ready within 1 s and ready 1 s after
it was back, with no false ready. On a first start of a three level
graph no application restarted. With the internal DNS down the deploy
already fails in Komodo, before the wait, so the probe adds no new
dependency. The only weakness was the crash loop, since a probe from outside
cannot see a restart that is shorter than the time between two probes.
With one good answer, or three, a provider that stayed up 10 s at a time
was declared ready every time. M1, M2 and M4 were not repeated on the
final version below; it is covered by the end to end test instead.

## Decision

### The wait

- Every application that `uses` another gets, in its compose file, a
  service `wait`, which the application `depends_on` with
  `condition: service_completed_successfully`. It holds for every way the
  Stack is deployed, a push to the GitOps repo included.
- The wait probes each provider as its consumer reaches it, by internal
  name. A `postgres` provider is probed with `pg_isready`; any other
  provider with its HTTP healthcheck. A provider with neither an
  interface nor a healthcheck is refused by `urbex apply`, since a port
  that answers does not tell that the application can take calls.
- A provider is healthy once it has answered every probe, a quarter of a
  second apart, for 20 seconds. A single failed answer starts the window
  again. The address is resolved when a window starts and probed as it is
  through the window, so a DNS failure does not reset it; the LXCs have
  fixed addresses. While the provider does not answer, the probes back
  off exponentially, with jitter, up to 8 s.
- The wait gives up after the longest chain of `ready_within` upstream of
  the application, plus 20 s per level. The image of the wait is
  `postgres:17-alpine`, which has `pg_isready` and `wget`; it receives no
  environment and so no secret.
- In the vocabulary of ADR-0028, the wait checks that the provider is
  healthy; the containers merely running is what ADR-0028 calls ready.

### The preflight

`urbex-compose`, which Komodo runs for every Stack, runs the wait alone
before `docker compose up`. If the providers are not healthy, the deploy
stops and the running version of the application stays up. Without it,
compose would replace the running container at once and leave the new
one waiting, an outage the change did not call for.

### The reconciler

- A Komodo Action, `urbex-reconcile`, run every minute, deploys again a
  consumer that is down, unhealthy, or has a version it could not deploy,
  once what it uses is healthy. `urbex apply` keeps the graph of each
  environment in a Komodo variable (`URBEX_GRAPH_*`); the Action keeps its
  state in `URBEX_RECONCILE_STATE`.
- It reads the containers only through `ListStackServices`, which returns
  their state and Docker's status line, with the health and the uptime.
  It never calls `InspectStackContainer`, which would hand it the
  containers' environment and their secrets.
- It only deploys; it never stops anything. A Stack it could not observe,
  one on a server that Komodo cannot reach, one being deployed, and one an
  operator stopped are left alone.
- A Stack counts as healthy after 2 runs seen healthy, and as
  down after 2 runs seen down.
- A provider whose container restarted since the previous
  run is unstable, and its consumers are not deployed until it stays up
  for 2 runs. A restart is told from the uptime in the status line.
  Only a second restart within 10 minutes is a crash loop; that run fails,
  so that Komodo shows it, and sends an alert. A single restart, a reboot
  of the node for instance, holds the consumers and alerts nobody.
- Failed deploys back off exponentially, with jitter, from 1 to 15
  minutes. After 5 failures in a row the circuit of that Stack opens for
  10 minutes; then one deploy is tried, which closes it or opens it
  again. A consumer that comes back by itself resets its failures.
- A run starts at most 5 deploys, and at most 1 per server, so that a
  reboot does not turn into a storm of deploys. A lease keeps two runs
  from deploying at once, and every call to Komodo has a deadline.
- Every run sends a line to Loki, and an error line for every alert.
  Grafana alerts on the error lines and, as a dead man's switch, on five
  minutes without a run. `urbex status` shows the last run and the Stacks
  held, unstable or in a crash loop.

### The permissions of the Action

The reconciler runs as Komodo runs every Action, as its system user
`Action`, an admin. An admin of Komodo is already root on every LXC,
since Periphery mounts the Docker socket, so the Action adds no
privilege. What the Action reads is kept to calls that carry no secret.

### After a reboot of the node

Proxmox starts the applications' LXCs after the platform's, ordered by
their depth in the graph of `uses`, and waits after each provider for its
`ready_within`, up to 5 minutes. The wait and the reconciler cover what
this order does not.

## Rationale

D needs no key, no new service listening on the network, and no new
image of ours; it checks the path the consumer will use, the internal DNS
and the network included. Its limit, a probe that cannot see restarts,
is covered by the stable window for short crash loops and by the
reconciler, which sees restarts, for the longer ones.

The window of 20 s was measured over 6 minutes per case on crash loops
whose provider stays up 3, 6 and 12 s (D3, D4 and D5), with caddy and
PostgreSQL. It gave no false ready in 36 tries, and a stable provider healthy in
20 s in 18 tries out of 18. A longer window would delay every level of
the graph by as much.

A reconciler is the only design that recovers from what happens after
the first start. As an Action it needs no new service and runs where the
deploys are; its logic is a separate module, tested without Komodo.

## Out of scope, or later

- Interfaces other than `postgres` (`mysql`, `redis` in ADR-0028) need a
  probe each.
- `uses` between stacks or projects is refused.
- An image of our own for the wait, smaller and pinned by digest.
- Alerts on restarts of every application, from cAdvisor's
  `container_start_time_seconds`, with severities and an inhibition
  during a reboot of the node, outside the reconciler.
- A health state at the level of the Stack in Komodo, which shows it only
  for each container.

## Consequences

- `urbex.yaml` gets `ready_within` per application. `uses` no longer means
  that the provider is deployed first.
- An application used by others must have a healthcheck or a known
  interface.
- Every level of the graph starts at least 20 s after the previous one.
- A crash loop whose provider stays up longer than 20 s passes the wait;
  the consumer starts, and the reconciler holds further deploys and
  alerts within about two runs of the second restart.
- The reconciler acts once a minute, and Komodo refreshes its view of the
  containers about every 15 s, so a recovery takes a few minutes.
- `bootstrap` installs the Action and the Grafana alerts; `urbex status`
  gains the reconciler's section.
