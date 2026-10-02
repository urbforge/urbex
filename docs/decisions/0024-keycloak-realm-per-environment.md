# ADR-0024: A Keycloak realm per project environment, clients per frontend, test users in staging

## Status

Accepted. Refines [ADR-0014](0014-keycloak-realm-per-project.md) (a
realm per project) into a realm per project **environment**, and
implements the Keycloak part of [ADR-0008](0008-keycloak-scope.md) for
projects.

## Context

Keycloak ran since the first bootstrap, but nothing was created in it:
a project's services and frontends had nowhere to authenticate users.
What a project needs:

- an identity realm, with the roles its services check;
- an OIDC client for each frontend, allowed to redirect to that
  frontend's addresses;
- in staging, users to try the roles with, without creating them by
  hand;
- the services must know how to validate the tokens.

A single realm per project would share users between staging and
production - and so the staging test users would work in production.

## Decision

- **A realm per project environment**, `<project>-<env>`
  (`hello-staging`, `hello-prod`), created by `urbex apply <env>` and
  deleted - users included - by `urbex destroy <env>`.
- **Roles**: the services' `auth.roles` (those with `auth.keycloak:
  true`) become realm roles.
- **A public OIDC client per frontend** (authorization code with PKCE,
  no secret): `web` for a web frontend, redirecting to its public
  hostname in that environment; `mobile` for a mobile app, redirecting to
  `<project>://...`.
- **Staging only**: a test user per role, `test-<role>`, with a
  generated password kept SOPS-encrypted in the GitOps repo
  (`environments/staging/<project>/keycloak-users.sops.env`) and reused
  on every apply; and a client `urbex-test` that allows password logins,
  to get tokens from the command line. `urbex users <env>` shows them.
- **Services with `auth.keycloak: true`** get `KEYCLOAK_REALM`,
  `KEYCLOAK_ISSUER` (the public issuer with Cloudflare) and
  `KEYCLOAK_JWKS_URL` (the realm's signing keys, on the LAN) in their
  environment, to validate tokens and check roles.

## Rationale

- Separate realms make the environments' users, sessions and roles
  independent: nothing done in staging reaches production.
- Public clients with PKCE are what browser and mobile frontends should
  use: they can't keep a secret.
- Generated, encrypted, reused test passwords: every staging environment
  is usable right after `apply`, and nothing secret lands in plaintext.

## Consequences

- `urbex apply staging` with roles needs `sops` (as `urbex secret`).
- Destroying an environment deletes its realm's users.
- Keycloak still runs in development mode (embedded database): realms
  survive restarts and upgrades, but production mode is still to do.
- Not yet: confidential clients for services calling each other, the
  realm's login theme and e-mail settings, social logins, several
  frontends per project.
