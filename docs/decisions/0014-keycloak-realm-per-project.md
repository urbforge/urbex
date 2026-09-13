# ADR-0014: One Keycloak realm per project

## Status

Accepted

## Context

[ADR-0008](0008-keycloak-scope.md) established that Keycloak serves both
platform admin SSO and per-app OIDC/RBAC, but left open whether each
project gets its own realm or whether projects share clients within one
realm.

## Decision

- A dedicated **`platform`** realm hosts SSO for the admin UIs (Komodo,
  Grafana, Gitea, Technitium).
- Every project gets its **own Keycloak realm**, named after the project
  (`project: my-app` in `urbex.yaml` → realm `my-app`), containing the
  OIDC clients and roles declared under each service's `auth` section in
  the manifest (see [`manifest-spec.md`](../manifest-spec.md)).

## Rationale

- Clean lifecycle: destroying a project (`urbex destroy`) can delete its
  entire realm in one step, with no risk of leaking roles/clients that
  belonged to a decommissioned project into a shared realm.
- No naming collisions between projects that happen to declare the same
  role name (e.g. two unrelated apps both using an `admin` role).
- Matches the "one LXC per service per environment" isolation philosophy
  already adopted in [ADR-0009](0009-one-lxc-per-service-per-env.md):
  project-level blast radius stays contained to the project.

## Consequences

- Provisioning a new project must create its Keycloak realm as part of
  `urbex apply` (or on first `urbex init`), before any service that
  declares `auth.keycloak: true` can be deployed.
- Cross-project SSO (a user logging into two different personal apps with
  one account) is not free with this model — if ever needed, it would
  require federating project realms against a shared identity realm
  rather than relying on a single shared realm. Out of scope for v1;
  personal apps are not expected to need shared end-user accounts across
  projects.
- Realm-per-project adds a small amount of Keycloak admin API overhead
  per project (vs. reusing one realm), acceptable given the isolation
  benefits.
