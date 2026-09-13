# ADR-0009: One LXC per service per environment

## Status

Accepted

## Context

A default is needed for isolation granularity: a dedicated LXC for every
service in every environment (maximum isolation) versus sharing resources
by grouping multiple services in one LXC (more suited to constrained
home-lab hardware).

## Decision

v1 default: **one LXC per service per environment**. An "api" service of
a project will therefore have two LXCs (one for staging, one for prod),
each with its own `docker compose`.

## Rationale

- Consistent with the explicit requirement: "each LXC manages its own
  docker compose by cloning a git repo".
- Simpler isolation to reason about: updating, rolling back, or scaling a
  service does not impact others.
- Easier to automate with Terraform (one module = one LXC = one service)
  compared to a model with configurable shared topologies.

## Consequences

- On home-lab hardware with limited resources, a project with many
  services can generate many LXCs. A "lightweight" profile that groups
  multiple services into a shared LXC is a possible future extension (see
  [`roadmap.md`](../roadmap.md)), not part of v1 scope.
- Default sizing (CPU/RAM/disk) per LXC must have reasonable values for a
  personal app, overridable in the manifest (`urbex.yaml`).
