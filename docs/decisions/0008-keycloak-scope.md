# ADR-0008: Keycloak scope in v1

## Status

Accepted

## Context

Keycloak is required as the base identity provider. It needs to be
clarified which uses it covers in v1: admin SSO only, application
authentication only, or both, and at what granularity.

## Decision

A single Keycloak (dedicated LXC) covers three uses starting from v1:

1. **SSO for admin UIs**: Komodo, Grafana, Gitea, Technitium are
   protected by a single login via Keycloak instead of separate
   credentials per tool.
2. **OIDC provider for dev apps**: apps created in projects can register
   as OIDC clients on Keycloak to delegate end-user authentication to it.
3. **Role-based authorization**: service APIs are protected by roles
   defined in Keycloak (not just authentication, but also RBAC
   authorization).

## Rationale

Explicit user request to cover all three uses starting from v1, not just
admin SSO.

## Consequences

- Provisioning a new project must include creating a dedicated Keycloak
  realm or client (to be decided during technical design: one realm per
  project vs multiple clients in a shared realm) and the application
  roles declared in the manifest (`urbex.yaml`).
- The app manifest schema must include a section to declare the roles
  required by a service (see [`manifest-spec.md`](../manifest-spec.md)).
- Bootstrap must create a working administrative Keycloak with at least
  one "platform" realm for the SSO of base tools, separate from the
  application realms/clients of individual projects.
