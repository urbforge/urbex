# ADR-0023: Service logs shipped to Loki by an agent on each LXC

## Status

Accepted. Implements the logging half of
[ADR-0004](0004-gitops-gitea-komodo.md#logging-note) for project
services.

## Context

The observability LXC has run Prometheus, Loki and Grafana since the
first bootstrap, but nothing sent them anything: a service's logs were
only on its LXC (`docker logs`) and in Komodo's UI, one service at a
time. The roadmap asks for every service's logs to reach the
observability stack automatically, with no setup in the project.

Options considered for getting container logs to Loki:

- Docker's Loki logging driver: a plugin installed on every Docker
  host; a Loki outage can block the containers writing logs.
- Promtail: end of life (folded into Grafana Alloy).
- **Grafana Alloy**, reading containers' logs through the Docker API.

## Decision

- **An Alloy agent on every project LXC**, installed by `urbex apply`
  (Ansible role `logs`) next to Komodo's Periphery, as a container with
  the Docker socket read-only.
- **Only the service's containers**: those of the LXC's Komodo Stack,
  whose compose project is named like the LXC. Periphery's and the
  agent's own logs aren't shipped.
- **Labels**: `project`, `service`, `env`, `host`, and `container`. A
  query is `{project="acme-app", env="prod"}`; LogQL does the rest.
- **On by default**; `observability.logs: false` in `urbex.yaml` turns
  the agent off (and removes it) for the project's LXCs.
- **Grafana is provisioned** with Loki and Prometheus as data sources and
  an *Urbex logs* dashboard (folder *Urbex*): project, environment and
  service selectors, a search box, a volume graph and the log lines.
- Loki, Grafana and Alloy images are pinned (Loki 3.7.8, Grafana 13.2.3,
  Alloy v1.20.1).

## Rationale

- Reading through the Docker API needs nothing from the services: no
  logging driver, no change to the compose files, logs stay readable
  with `docker logs` and in Komodo.
- An agent per LXC keeps the labels exact: the LXC knows which project,
  service and environment it runs.
- If Loki is down, Alloy buffers and retries; the services are not
  affected.

## Consequences

- Every project LXC runs one more small container.
- Loki keeps logs with its default single-node configuration (local
  filesystem, no retention limit set): disk usage on the observability
  LXC grows with the logs. Retention is a follow-up.
- Not covered yet: the base services' own logs (Gitea, Komodo, ...), web
  frontends (Cloudflare Workers - their logs are on Cloudflare), and
  metrics (`observability.metrics`).
