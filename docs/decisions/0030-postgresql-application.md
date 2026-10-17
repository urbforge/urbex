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
- how several applications share one server without sharing data or
  credentials;
- what Urbex generates and passes, and where it keeps it;
- the details of PostgreSQL's image that the generic model doesn't
  cover: the image's own initialisation runs only on an empty data
  directory, the data directory must start empty, a new major version
  can't open an old data directory, and the official image has no
  healthcheck;
- monitoring, access, removal, destroy and backups for a database.

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
    uses: [db]                  # its own role and schema on db
  - name: worker
    runtime: go
    port: 8081
    uses: [db]                  # another role and schema, same server
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
- **A provider has exactly one named volume**, which holds its data
  directory. `apply` and the schema refuse a `postgres` provider with
  none (its data would be lost the first time its container is
  re-created) or with more than one.
- **Its endpoint is implicit**: port 5432, `tcp`, `internal`. It can't
  be `public` or `access` (ADR-0028: only `http` endpoints can), and it
  doesn't declare `endpoints`, `port` or `healthcheck` (see below).
- **Where it runs** is the stack's placement (ADR-0028): with `app`, the
  default, its own LXC per environment, `<project>-<app>-<env>`
  (ADR-0009); with `stack`, the stack's LXC. Its resources are the
  application's (`resources`, defaults as a service's).

### One server, an own space per application

A provider is one PostgreSQL server with one database, per environment.
**Every application that lists it in `uses` gets its own role and its
own schema** on it, with its own generated password:

- the role and the schema are named after the application, `-` turned
  into `_` (`api`, `worker`, `admin_ui`); the schema belongs to the role;
- the role's `search_path` is its schema (`ALTER ROLE ... SET
  search_path`), so whatever the driver, the application reads and
  writes its own tables without naming the schema;
- a role has no rights on the other applications' schemas, nor on
  `public`: one server serves several applications without them sharing
  tables or credentials;
- the server's own user (`POSTGRES_USER`, `urbex`) is used by Urbex
  only, to manage the roles and schemas; no application gets it.

**A dedicated database means its own provider.** An application that
expects a database all to itself declares a `postgres` provider of its
own, used only by it. Urbex never creates further databases on a
shared server.

### What Urbex generates, and what an application gets

On the first `apply` of an environment, before the provider's first
start, Urbex generates the server's:

| | Value | Kept in the GitOps repo |
|---|---|---|
| Admin user | `urbex` | the provider's `config.env`: `POSTGRES_USER` |
| Database | the project's name, `-` turned into `_` (`acme_app`) | the provider's `config.env`: `POSTGRES_DB` |
| Admin password | 32 random letters and digits - nothing to escape in a URL | the provider's `secrets.sops.env`: `POSTGRES_PASSWORD` |
| Data directory | `<volume path>/pgdata` | the provider's `config.env`: `PGDATA` |

On every `apply`, once the provider is healthy and before the
applications that use it are deployed, Urbex makes sure each of them
has its role and schema, and generates a password for a role that has
none yet. Each application gets, in its environment:

| Variable | Value | Kept in |
|---|---|---|
| `DATABASE_URL` | `postgres://<role>:<password>@<host>:5432/<database>` | `secrets.sops.env` |
| `PGHOST` | the provider's internal name: `db.acme-app.<zone>` in production, `db.staging.acme-app.<zone>` in staging (ADR-0027) | `config.env` |
| `PGPORT`, `PGDATABASE`, `PGUSER` | `5432`, the database, its role | `config.env` |
| `PGPASSWORD` | its role's password | `secrets.sops.env` |

- An application using two `postgres` providers gets each set prefixed
  with the provider's name in capitals: `ANALYTICS_DATABASE_URL`,
  `ANALYTICS_PGHOST`... (ADR-0028).
- An image that reads other names maps them with references -
  `${db.host}`, `${db.port}`, `${db.user}`, `${db.password}`,
  `${db.database}`, `${db.url}` - in `env`. Until ADR-0028's flat `env`
  lands in the schema, references go in today's per-environment values
  (`env.staging`, `env.prod`), and resolve to that environment's
  provider and the application's own role.
- **A variable whose value references `password` or `url` is a
  secret**: it is written to the application's `secrets.sops.env`,
  encrypted like `DATABASE_URL`, never to `config.env`.
- The host is always the internal name, an A record in Technitium set by
  `apply` and removed by `destroy` (ADR-0026); in `stack` placement it
  points to the stack's LXC, like every name of the stack.
- **`PGDATA` is a folder inside the volume**, not the volume itself: a
  Proxmox mount point formatted ext4 has a `lost+found` at its root, and
  `initdb` refuses a folder that isn't empty. It also makes the volume's
  path the same for every major version - from 18 the official image
  moved its default data directory under `/var/lib/postgresql/<major>/`.
  Up to 17 the image declares `VOLUME /var/lib/postgresql/data`, so
  Docker adds an empty anonymous volume there: it holds nothing, lives
  on the LXC's root disk and goes with the LXC.
- **The healthcheck** is
  `pg_isready -h 127.0.0.1 -U urbex -d <database>`, run in the
  container: the official image has none, and ADR-0028's fallback ("a
  running container counts") would let the applications that use it
  start while `initdb` is still running - its temporary server listens
  only on the Unix socket, so the TCP probe fails until the real one
  starts. A provider can't declare its own healthcheck until
  ADR-0028's `tcp` and `command` forms are in the schema: today's form
  is an HTTP path probed on `port`, which a provider doesn't have.
- **No TLS** between applications and PostgreSQL: the traffic stays on
  the platform's network. The URL carries no `sslmode`, so libpq's
  default (`prefer`) connects without TLS, and adding a certificate
  later doesn't change it.

### How Urbex talks to the server

The image's own initialisation runs only on an empty data directory, so
the roles and schemas of applications added later must be created on
the running server. Urbex runs SQL there **through a Komodo exec in the
provider's container**, as the server's admin user over the local
socket:

- on every `apply`: `CREATE ROLE`, `CREATE SCHEMA ... AUTHORIZATION`,
  `ALTER ROLE ... SET search_path`, the grants and revokes - each one
  idempotent, so re-applying changes nothing that is already there;
- for `urbex status`: the roles and schemas the server has
  (`pg_roles`, `pg_namespace`), compared with the manifest's `uses`;
- for the major-version guard: the data directory's `PG_VERSION`.

No port is published for it, no SQL client is needed where `urbex`
runs, and no one-off container is left behind.

### Credentials

- **Generated once, reused forever.** Re-applies, redeploys, updates and
  promotions reuse the values in the GitOps repo. The server's
  `POSTGRES_*` are read by the image only when it initialises an empty
  data directory: changing them afterwards would change nothing on the
  server and break Urbex's access to it.
- **Not editable through Urbex.** `urbex secret set` and `unset` refuse
  the generated keys and say why: `POSTGRES_*` on the provider;
  `DATABASE_URL`, `PG*` and the variables mapped from references on each
  application. `urbex secret list` marks them as generated.
- **An application's password can be recovered**: if its secrets are
  lost while its role exists, the next `apply` generates a new password
  and sets it on the role. The server's own password can't: if the
  GitOps repo loses it while the volume stays, Urbex can no longer
  manage the server - the known limitations say so.
- **Rotation** of a role on demand is out of scope; see *Later*.

### Removing an application keeps its data

When an application stops using a provider, or is removed from the
manifest, its role and schema **stay, with their data**: nothing is
dropped implicitly. `apply` lists them as unused, and
`urbex apply <env> --delete-data` drops the roles and schemas no
application uses any more, naming them first - the same flag as
`destroy`'s. Adding the application back before that finds its data
where it was.

### Visible

`urbex status` shows, for each provider, its database, the schemas and
roles on it, and which application uses each; those of removed
applications show as unused, not hidden. It lists the provider itself
with its interface (`postgres`), tag and digest, internal name, volume
and size, and health. Never a password.

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
  `--allow-major` isn't enough: before deploying, `apply` and `deploy`
  read the data directory's `PG_VERSION` (through the Komodo exec
  above) and refuse a major that differs from it, saying how to
  upgrade. The cookbook documents the manual path: dump with
  `pg_dumpall`, empty the volume, deploy the new major with
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
- PostgreSQL's own metrics (`postgres_exporter`) come later, with the
  services' own metrics (`observability.metrics`, E4).

### Environments, destroy, removal of the provider

- Each environment has its own server, data and credentials: staging's
  database is never production's.
- `urbex destroy <env>` refuses without `--delete-data`, naming the
  provider's volume (ADR-0028, which replaces the draft's
  `--delete-databases`); with it, it removes the LXC, the volume, the
  Stack, the folder with its credentials, and the DNS record.
- Removing the provider itself from `urbex.yaml` is handled as removing
  any service today - not handled (`docs/status.md`): `destroy` and
  `apply` again. `apply` refuses a manifest where an application `uses`
  a provider that isn't declared.

### Access

The platform's network only - never on Cloudflare. Applications reach
it by internal name. The official image accepts password logins
(`scram-sha-256`) from any address, so a developer reaches it from the
LAN at the same name (with the router forwarding the zone to Technitium,
ADR-0027) or at the LXC's address, with an application's credentials
decrypted from the GitOps repo
(`sops -d environments/<env>/<project>/<app>/secrets.sops.env`;
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
- `pg_dump` over the LAN works, with an application's credentials for
  its schema.

## Rationale

- **Nothing special about a database** (ADR-0028): what this ADR adds is
  the `postgres` interface's contract - what Urbex generates, passes and
  guards - not a second kind of component.
- **A role and a schema per application** let one server serve a stack
  without its applications sharing tables or credentials, and keep the
  cost of a database at one LXC per stack-environment rather than per
  application. An application that wants more has its own provider.
- **Data kept until an explicit flag**, for an application as for an
  environment: losing a schema costs more than a word on the command
  line.
- **One channel, the Komodo exec**, for everything Urbex asks the
  server: no port, client or extra container, and the answers come from
  the server and its data directory, not from what the GitOps repo
  believes.
- **Credentials generated once and guarded** follow how PostgreSQL's
  image works: a value the server no longer reads must not look
  editable.
- **`PGDATA` in a subfolder and the healthcheck** remove the two ways a
  first start fails on Urbex's storage and deploy order, without asking
  the user to know them.
- **`DATABASE_URL` and `PG*`** are what frameworks and drivers read
  without configuration; references cover the images that don't.

## Out of scope, or later

- The `mysql` and `redis` interfaces' integrations - each its own
  decision on the same model.
- A platform-provided PostgreSQL shared by several stacks, and links
  between stacks (ADR-0028, *Later*).
- Credential rotation on demand; TLS, with the rest of the platform's
  internal traffic, in E5 Security and isolation
  ([redemptor#34](https://github.com/urbforge/redemptor/issues/34));
  connection pooling (PgBouncer); replicas and high availability;
  point-in-time recovery.
- Automated major upgrades.
- Schema migrations: the application's job.
- A `urbex` command to open `psql` on an environment's database.

## Consequences

- `schemas/urbex.schema.json` accepts an application from an image with
  `image`, `version`, `provides: postgres`, `uses` and named `volumes` -
  the part of ADR-0028's schema a PostgreSQL in a stack needs - and
  holds a `postgres` provider to exactly one volume and no `port`,
  `public` or `healthcheck`. `environments` comes with
  [urbforge/urbex-cli#42](https://github.com/urbforge/urbex-cli/issues/42);
  the rest (`placement`, `endpoints`, shares, `resources.gpu`,
  `auth.oidc`, the new healthcheck forms, the other interfaces) with
  ADR-0028's own schema work.
- [urbforge/urbex-cli#9](https://github.com/urbforge/urbex-cli/issues/9)
  becomes the `postgres` interface and its integration: the server's
  credentials and `PGDATA`, the healthcheck, roles and schemas per
  application through the Komodo exec, the variables, `apply
  --delete-data` for unused schemas, the major-version guard, the
  `secret` guard, `status`, the catalog entry, the e2e. It builds on
  [urbforge/urbex-cli#42](https://github.com/urbforge/urbex-cli/issues/42)
  (applications from images, which also vendors the schema),
  [#43](https://github.com/urbforge/urbex-cli/issues/43) (interfaces and
  links) and [#44](https://github.com/urbforge/urbex-cli/issues/44)
  (named volumes).
- ADR-0027's table: the *project database* row becomes a PostgreSQL
  application, `app`, internal.
- The manifest reference, the cookbook (a database for a project; a
  major upgrade by hand), the known limitations (the server's lost
  credentials, no rotation, no automated major upgrade) and
  `docs/status.md` follow the implementation.
- Each PostgreSQL costs an LXC per environment in `app` placement; a
  stack's applications share it, and a stack that wants fewer LXCs
  uses `placement: stack`.
