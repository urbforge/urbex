# ADR-0029: Keycloak in production mode, on its own PostgreSQL

## Status

Accepted. Changes how Keycloak runs, from
[ADR-0008](0008-keycloak-scope.md) and
[ADR-0024](0024-keycloak-realm-per-environment.md) (what it covers, and
the realms urbex creates in it, stand).

## Context

Keycloak ran `start-dev`, the development mode, with its embedded
database in the container's volume:

- **It built at every start.** Keycloak "builds" itself for its
  configuration (database, features) before starting. In development
  mode that happens at every start: on the test Proxmox node (2 cores,
  2 GB) the build alone took 6 minutes, and a first start after a
  bootstrap from scratch 5-10 minutes. Bootstrap and apply now wait for
  it (urbforge/urbex-cli#32), but the wait stayed the slowest step of a
  bootstrap.
- **Development mode isn't meant for production**, nor is its embedded
  database, as Keycloak's documentation says.

## Decision

- **Production mode**: Keycloak runs `start --optimized` on an image
  built once for PostgreSQL (`kc.sh build`, from a Dockerfile in the
  Stack's folder of the GitOps repo, `platform/keycloak/`). The image is
  built on Keycloak's LXC the first time Komodo deploys the Stack, and
  is in Docker's cache after that: a new container starts without
  building.
- **Its own PostgreSQL**, in the same Stack (`urbex-keycloak`, on
  Keycloak's LXC): the data on a persistent volume, reachable only on
  the Stack's network - no port published. It is part of the
  `keycloak` service (`urbex.service: keycloak`, kind `platform`), as
  Komodo's database is part of Komodo's: its logs and resources are in
  Grafana with Keycloak's, and the service catalog has no new entry.
  It is the platform's own database, not an application's
  ([ADR-0028](0028-application-model.md)).
- **Credentials**: bootstrap generates the database password once
  (`keycloakDbPassword` in `~/.urbex/credentials.yaml`) and writes it
  SOPS-encrypted in the Stack's secrets (`platform/keycloak/secrets.sops.env`),
  as Keycloak's admin password.
- **Hostname**: production mode wants a hostname and HTTPS. TLS ends
  before Keycloak - at Cloudflare, or nowhere on the LAN - so HTTP is
  enabled. With Cloudflare the hostname is the public one, as before;
  without, the hostname isn't fixed (`KC_HOSTNAME_STRICT=false`): the
  issuer is the address each request reaches Keycloak at, as in
  development mode.

## Consequences

- A first start still builds the image once: on the test node about 7
  minutes, now in Komodo's deploy of the Stack. Every later start,
  restart or new container is under a minute (23 s measured).
- Keycloak's upgrade path is PostgreSQL's and Keycloak's own: a new
  Keycloak version rebuilds the image and migrates the schema at its
  first start.
- Not yet: backups of the database (as for the other base services),
  Keycloak's own TLS, a database outside the LXC.
