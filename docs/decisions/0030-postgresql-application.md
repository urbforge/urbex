# ADR-0030: PostgreSQL - the application and its integration

## Status

Proposed. Part of [urbforge/redemptor#17](https://github.com/urbforge/redemptor/issues/17)
(E2 Databases), tracked by [urbforge/urbex#6](https://github.com/urbforge/urbex/issues/6);
implemented by [urbforge/urbex-cli#9](https://github.com/urbforge/urbex-cli/issues/9).
Builds on [ADR-0028](0028-application-model.md) (a database is an
application in a stack, `provides: postgres`) and replaces the draft
`databases` section of [urbforge/urbex#19](https://github.com/urbforge/urbex/pull/19).
Follows the service conventions of [ADR-0027](0027-service-conventions.md).

## Context

A project's services have nowhere to keep structured data. ADR-0028
settled the model: PostgreSQL is not a separate kind of component but an
application from a public image, in the stack that needs it, that
**provides** the `postgres` interface to the applications that **use**
it. It left to this ADR what is specific to PostgreSQL:

- what makes an application a valid `postgres` provider, and where it
  runs;
- what Urbex generates and passes, and where it keeps it;
- the details of PostgreSQL's image that the generic model doesn't
  cover: the credentials are only read on the first start, the data
  directory must start empty, a new major version can't open an old
  data directory, and the official image has no healthcheck;
- monitoring, access, destroy and backups for a database.

The Keycloak database of ADR-0029
([urbforge/urbex#33](https://github.com/urbforge/urbex/pull/33))
is the platform's own, inside Keycloak's Stack; it is not a project's
application and nothing here applies to it.

## Decision

### A PostgreSQL is an application that provides `postgres`

```yaml
apiVersion: urbex/v1
project: acme-app
services:
  - name: api
    runtime: go
    port: 8080
    healthcheck: /healthz
    uses: [db]                  # gets DATABASE_URL and PG*
  - name: db
    image: postgres
    version: "17"               # pinned by digest per environment
    provides: postgres
    volumes:
      - name: data
        path: /var/lib/postgresql
        size: 20Gi
    resources:
      memory: 2Gi
```

- **Any image that behaves like the official one** can provide
  `postgres`: it reads `POSTGRES_USER`, `POSTGRES_PASSWORD`,
  `POSTGRES_DB` and `PGDATA`, and listens on 5432 - `postgres`,
  `postgis/postgis`, `pgvector/pgvector`, `ghcr.io/immich-app/postgres`.
  Extensions come with the image; Urbex doesn't install them.
- **A provider must have a named volume.** `apply` refuses a `postgres`
  provider without one: its data would be lost the first time its
  container is re-created. The schema says so too.
- **Its endpoint is implicit**: port 5432, `tcp`, `internal`. It can't
  be `public` or `access` (ADR-0028: only `http` endpoints can), and it
  doesn't declare `endpoints` or `port`.
- **Where it runs** is the stack's placement (ADR-0028): with `app`, the
  default, its own LXC per environment, `<project>-<app>-<env>`
  (ADR-0009); with `stack`, the stack's LXC. Its resources are the
  application's (`resources`, defaults as a service's).
- **One server, one database, one user** per provider per environment.
  The applications that use the same provider share them; applications
  that must not share data declare two providers.

### What Urbex configures, and what a user gets

On the first `apply` of an environment, before the provider's first
start, Urbex generates:

| | Value | Kept in the GitOps repo |
|---|---|---|
| User and database | the project's name, `-` turned into `_` (`acme_app`) - no quoting needed in SQL | the provider's `config.env`: `POSTGRES_USER`, `POSTGRES_DB` |
| Password | 32 random letters and digits - nothing to escape in a URL | the provider's `secrets.sops.env`: `POSTGRES_PASSWORD` |
| Data directory | `<volume path>/pgdata` | the provider's `config.env`: `PGDATA` |

Every application that uses the provider gets, in its environment
(ADR-0028's table, made exact):

| Variable | Value | Kept in |
|---|---|---|
| `DATABASE_URL` | `postgres://<user>:<password>@<host>:5432/<database>` | `secrets.sops.env` |
| `PGHOST` | the provider's internal name: `db.acme-app.<zone>` in production, `db.staging.acme-app.<zone>` in staging (ADR-0027) | `config.env` |
| `PGPORT`, `PGDATABASE`, `PGUSER` | `5432`, the database, the user | `config.env` |
| `PGPASSWORD` | the password | `secrets.sops.env` |

- An application using two `postgres` providers gets each set prefixed
  with the provider's name in capitals: `ANALYTICS_DATABASE_URL`,
  `ANALYTICS_PGHOST`... (ADR-0028).
- An image that reads other names maps them with references -
  `${db.host}`, `${db.port}`, `${db.user}`, `${db.password}`,
  `${db.database}`, `${db.url}` - in `env`. Until ADR-0028's flat `env`
  lands in the schema, references go in today's per-environment values
  (`env.staging`, `env.prod`), and resolve to that environment's
  provider.
- The host is always the internal name, an A record in Technitium set by
  `apply` and removed by `destroy` (ADR-0026); in `stack` placement it
  points to the stack's LXC, like every name of the stack.
- **`PGDATA` is a folder inside the volume**, not the volume itself: a
  Proxmox mount point formatted ext4 has a `lost+found` at its root, and
  `initdb` refuses a folder that isn't empty. It also makes the volume's
  path the same for every major version - from 18 the official image
  moved its default data directory under `/var/lib/postgresql/<major>/`.
- **The healthcheck** defaults to
  `pg_isready -h 127.0.0.1 -U <user> -d <database>`, run in the
  container: the official image has none, and ADR-0028's fallback ("a
  running container counts") would let the applications that use it
  start while `initdb` is still running. A healthcheck the manifest
  declares replaces it.
- **No TLS** between applications and PostgreSQL: the traffic stays on
  the platform's network. The URL carries no `sslmode`, so libpq's
  default (`prefer`) connects without TLS, and adding a certificate
  later doesn't change it.

### Credentials live with the data

PostgreSQL's image reads `POSTGRES_USER`, `POSTGRES_PASSWORD` and
`POSTGRES_DB` only when it initialises an empty data directory. After
that the password lives in the database, not in the environment:

- **Generated once, reused forever.** Re-applies, redeploys, updates and
  promotions reuse the values in the GitOps repo, and never generate new
  ones while the provider's folder exists.
- **Not editable through Urbex.** Changing `POSTGRES_PASSWORD` in the
  GitOps repo would leave the server's password unchanged and break
  every application that uses it, so `urbex secret set` and `unset`
  refuse the generated keys (`POSTGRES_*` on the provider; `DATABASE_URL`
  and `PG*` on its users) and say why.
- **Rotation** (`ALTER ROLE` on the server and the secrets in one step)
  is out of scope; see *Later*.
- **Deleted with the data.** `destroy --delete-data` deletes the
  provider's folder with its volume; the next `apply` generates new
  credentials for the new, empty volume. If the GitOps repo loses them
  while the volume stays, Urbex can't recover them: the known
  limitations say so.

### Versions and upgrades

As for every application from an image (ADR-0028):

- `version` is a tag; each environment runs the digest its first `apply`
  resolved, written in the provider's `version.env`, until
  `urbex deploy <env> --app db --update` resolves it again, or
  `--version` changes it.
- **Minor versions** (`17.6` to `17.7`) are binary compatible: an update
  is a restart on the same data directory. `urbex promote` moves the
  digest staging runs to production, so a PostgreSQL update is tried on
  staging first.
- **The major version** is the tag's leading number (`17`, `17.6`,
  `17-alpine`; `14` for `14-vectorchord0.4.3-pgvectors0.2.0`). A new
  major can't open the old data directory, so for a `postgres` provider
  `--allow-major` isn't enough: `apply` and `deploy` read the data
  directory's `PG_VERSION` and refuse a major that differs from it,
  saying how to upgrade. The cookbook documents the manual path: dump
  with `pg_dumpall`, empty the volume, deploy the new major with
  `--allow-major`, restore. An automated upgrade (dump and restore, or
  `pg_upgrade`) comes later, with the dump tooling of E3.

### Komodo, monitoring, observability

A provider is an application like any other (ADR-0027, ADR-0028):

- kind **`app`**; its own Komodo Stack `<project>-<app>-<env>` from its
  folder in the GitOps repo (`compose.yaml`, `config.env`,
  `secrets.sops.env`, `version.env`); its container labelled
  `urbex.kind: app` and `urbex.service: <app>`;
- in `app` placement its LXC is a Komodo Server (Periphery), tagged
  `app`, the project and the environment;
- its logs and resources reach Loki and Prometheus through the LXC's
  telemetry agent, as every container's;
- in the service catalog, an `app` entry with one endpoint, 5432,
  `tcp`, **internal** - generated from the manifest, as a service's;
- `urbex status` lists it with its interface (`postgres`), tag and
  digest, internal name, volume and size, and health; for the
  applications that use it, the providers they use. Never the password.
- PostgreSQL's own metrics (`postgres_exporter`) come later, with the
  services' own metrics (`observability.metrics`, E4).

### Environments, destroy, removal

- Each environment has its own server, data and credentials: staging's
  database is never production's.
- `urbex destroy <env>` refuses without `--delete-data`, naming the
  provider's volume (ADR-0028, which replaces the draft's
  `--delete-databases`); with it, it removes the LXC, the volume, the
  Stack, the folder with its credentials, and the DNS record.
- Removing a provider from `urbex.yaml` is handled as removing any
  service today - not handled (`docs/status.md`): `destroy` and `apply`
  again. `apply` refuses a manifest where an application `uses` a
  provider that isn't declared.

### Access

The platform's network only - never on Cloudflare. Other applications
reach it by internal name. The official image accepts password logins
(`scram-sha-256`) from any address, so a developer reaches it from the
LAN at the same name (with the router forwarding the zone to Technitium,
ADR-0027) or at the LXC's address, with the credentials decrypted from
the GitOps repo (`sops -d environments/<env>/<project>/<app>/secrets.sops.env`;
`urbex secret list` shows only names). An admin UI is just another
application: pgAdmin from its image, with `exposure: access`.

### Backups

Out of scope: E3, Backups and restore
([redemptor#31](https://github.com/urbforge/redemptor/issues/31)).
Meanwhile:

- the provider's volume is a mount point with `backup=1`, so Proxmox's
  own backups (vzdump) include it; a snapshot of a running PostgreSQL
  is crash-consistent - it recovers like after a power loss, which
  PostgreSQL is built for, but it is not a dump;
- `pg_dump` over the LAN works, with the credentials above.

## Rationale

- **Nothing special about a database** (ADR-0028): what this ADR adds is
  the `postgres` interface's contract - what Urbex generates, passes and
  guards - not a second kind of component.
- **Credentials generated once and guarded** follow how PostgreSQL's
  image works: a value the server no longer reads must not look
  editable.
- **`PGDATA` in a subfolder and the default healthcheck** remove the two
  ways a first start fails on Urbex's storage and deploy order, without
  asking the user to know them.
- **Refusing a major version the data directory can't open** turns a
  container that crash-loops after an update into a message before it.
- **`DATABASE_URL` and `PG*`** are what frameworks and drivers read
  without configuration; references cover the images that don't.

## Out of scope, or later

- The `mysql` and `redis` interfaces' integrations - each its own
  decision on the same model.
- A platform-provided PostgreSQL shared by several stacks, and links
  between stacks (ADR-0028, *Later*).
- Credential rotation, TLS, connection pooling (PgBouncer), replicas
  and high availability, point-in-time recovery.
- Automated major upgrades.
- Schema migrations: the application's job.
- A `urbex` command to open `psql` on an environment's database.

## Consequences

- `schemas/urbex.schema.json` accepts an application from an image with
  `image`, `version`, `provides: postgres`, `uses` and named `volumes` -
  the part of ADR-0028's schema a PostgreSQL in a stack needs. The rest
  (`environments`, `placement`, `endpoints`, shares, `resources.gpu`,
  `auth.oidc`, the new healthcheck forms, the other interfaces) comes
  with ADR-0028's own schema work.
- [urbforge/urbex-cli#9](https://github.com/urbforge/urbex-cli/issues/9)
  becomes the `postgres` interface and its integration: credentials and
  variables, `PGDATA`, the default healthcheck, the major-version guard,
  the `secret` guard, `status`, the catalog entry, the e2e. It needs
  ADR-0028's follow-ups for applications from images, interfaces and
  links, and named volumes; those are opened in `urbex-cli` first.
- ADR-0027's table: the *project database* row becomes a PostgreSQL
  application, `app`, internal.
- The manifest reference, the cookbook (a database for a project; a
  major upgrade by hand), the known limitations (lost credentials, no
  rotation, no automated major upgrade) and `docs/status.md` follow the
  implementation.
- Each PostgreSQL costs an LXC per environment in `app` placement; a
  stack that wants fewer LXCs uses `placement: stack`.
