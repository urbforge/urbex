# ADR-0028: The application model - from source or image, linked into stacks, with declared requirements

## Status

Proposed. Tracked by [urbforge/urbex#26](https://github.com/urbforge/urbex/issues/26).
Refines [ADR-0002](0002-app-manifest-in-app-repo.md) (a manifest
without code, several stacks in one repository), [ADR-0009](0009-one-lxc-per-service-per-env.md) (one LXC
per stack as a choice), [ADR-0020](0020-trunk-releases-gitops-environments.md)
(versions of public images, single-environment stacks) and
[ADR-0027](0027-service-conventions.md) (what a project's application is,
exposure behind Access for applications). The PostgreSQL decision of
[urbforge/urbex#6](https://github.com/urbforge/urbex/issues/6) is
rewritten on this model.

## Context

Urbex deploys services that a project builds from its own repository -
an image per commit, staging that follows `main`, releases promoted to
production. Its first users are home lab owners
([E13 First users](https://github.com/urbforge/redemptor/pull/24)).
What they run first is mostly not their own code:

- **applications published as images**: PostgreSQL, MySQL, Redis,
  Vaultwarden, Jellyfin, Radarr, Immich;
- **stacks of applications linked together**: Immich is a server, a
  machine-learning worker, a PostgreSQL and a Redis; the *arr stack is
  Radarr and Sonarr, a download client and Jellyfin, sharing a media
  folder that lives on a NAS.

Urbex has no way to say any of that. `urbex.yaml` lists services that
are always built (`runtime`), each with one HTTP port, public or not;
nothing declares storage that must survive, a link between two services,
a database's credentials, an OIDC client for an application that isn't
the user's, a GPU, or an application that only needs one environment.
The draft PostgreSQL ADR ([urbforge/urbex#19](https://github.com/urbforge/urbex/pull/19))
added a `databases` section of its own: a second kind of component, with
its own rules, for what is just another image.

## Decision

### Everything is an application

An **application** is one container Urbex runs: the user's own code,
built from source, or an image someone else publishes - PostgreSQL,
Redis and Immich alike. A **stack** is the applications deployed and
versioned together, linked to each other; an `urbex.yaml` describes
one stack.

- In the manifest the applications stay the entries of `services` - as
  in a compose file, where a service is one container. Today's project
  is a stack: `project` keeps naming it (see *Many stacks*).
- Every application is of kind **`app`** (ADR-0027) on Komodo and in
  Grafana, whatever its image: PostgreSQL in a stack is an `app`, like
  the API that uses it. `platform` stays for the services Urbex itself
  runs, `agent` for Periphery, Alloy and the Quick Tunnel sidecar.
- **A database is an application in a stack**, not a separate section:
  the stack that needs it runs it, with the stack's environments,
  lifecycle and backups. A platform-provided database, shared by
  several stacks, isn't decided here; the links below make it possible
  later without changing the applications that use one (see *Later*).

### Where an application's image comes from

Each application has exactly one source:

| | **From source** - `runtime` (as today) | **From an image** - `image` and `version` |
|---|---|---|
| Image | Built by Komodo from the project's repository into Gitea's registry, one per commit of `main` ([ADR-0018](0018-image-build-komodo-gitea-registry.md), [ADR-0021](0021-staging-follows-main.md)) | Pulled as it is from its registry (`postgres`, `ghcr.io/immich-app/immich-server`) |
| What the manifest says | how to build it | the image and the tag wanted: `version: "17"` or `"17.6"` |
| What an environment runs | `version.env`: a commit or a release | `version.env`: the tag **and the digest** it resolved to, `VERSION=17.6@sha256:...` |
| A new version | a push to `main` (staging), `urbex release`, `urbex promote` | `urbex deploy <env> --app <name> --update` resolves the tag again; `--version 17.7` changes it |

- **Pinned by digest.** The first `apply` of an environment resolves the
  tag to its digest and writes both to the application's `version.env`;
  the environment runs that exact image until its version is changed,
  even if the tag moves upstream. A floating tag (`"17"`) only says
  which updates `--update` takes.
- **Major versions are explicit.** Changing the major version of an
  application that has volumes (`17` to `18`) is refused without
  `--allow-major`: for a database it usually needs a dump and restore
  that Urbex doesn't automate.
- **Update pull requests** - Renovate opening one on the GitOps repo
  when a new image is published - fit this layout (a version per file),
  but aren't part of this decision: see *Later*.

### Stacks: how applications find each other

- **By name only** (ADR-0027): an application is
  `<app>.<project>.<zone>` in production and
  `<app>.staging.<project>.<zone>` in staging, wherever it runs.
- **`uses`** lists the applications of the stack an application needs.
  Urbex deploys those first and waits for them to be healthy, and passes
  their connection settings.
- **`provides`** says which **interface** an application implements, so
  that Urbex knows how to configure it and what to pass to the
  applications that use it. Urbex knows a few interfaces:

  | Interface | Urbex configures the provider with | A user gets |
  |---|---|---|
  | `postgres` | a generated user, password and database (`POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`) | `DATABASE_URL` and `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD` |
  | `mysql` | the same, with `MYSQL_*` / `MARIADB_*` | `DATABASE_URL` and `MYSQL_HOST`, `MYSQL_PORT`, `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD` |
  | `redis` | a generated password | `REDIS_URL`, `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD` |
  | none (any other application) | nothing | `<APP>_HOST`, `<APP>_PORT`, `<APP>_URL` for its first endpoint |

  An application using more than one provider of an interface gets the
  variables prefixed with the provider's name (`ANALYTICS_DATABASE_URL`).
- **An application that wants other names maps them** in `env`, with
  references to the values of what it uses: `DB_HOSTNAME:
  ${db.host}`, `DB_PASSWORD: ${db.password}`. The values an interface
  exports are `host`, `port`, `url`, and for the credentialed ones
  `user`, `password`, `database`. This is how a published image, which
  reads its own variable names, is wired without changing it.
- **Generated credentials are secrets** (ADR-0011): created by the first
  `apply` of an environment, SOPS-encrypted in the GitOps repo - in the
  provider's folder and in each user's - and reused on every re-apply.

### Where a stack runs: one LXC per application, or per stack

A stack chooses its **placement**:

- **`app`** (the default, today's): one LXC per application per
  environment, as ADR-0009 decided;
- **`stack`**: one LXC per environment for the whole stack,
  `<project>-<env>` - what a home lab expects for Immich, and what its
  own compose file does.

Either way each application keeps its own folder in the GitOps repo and
its own Komodo Stack, its own internal name (in `stack` placement every
name points to the same LXC) and its own healthcheck; the LXC's
resources are the sum of its applications'. Two applications on one LXC
may not publish the same port. The hosts of
[urbforge/urbex#24](https://github.com/urbforge/urbex/issues/24) (VPS,
servers over SSH) will reuse the same choice.

### What an application declares

```yaml
services:
  - name: server
    image: ghcr.io/immich-app/immich-server   # or runtime: go | java | python | docker
    version: v3
    endpoints:                     # what it serves
      - port: 2283
        protocol: http             # http (default) | tcp | udp
        exposure: public           # public | access | internal (default)
    uses: [db, redis]              # what it needs, in the stack
    env:
      DB_HOSTNAME: ${db.host}
    volumes:                       # what it keeps
      - name: library
        path: /data
        size: 200Gi
      - share: media               # a folder the operator provides
        path: /media
        readOnly: true
    resources:
      cpu: 4
      memory: 4Gi
      gpu: true
    auth:
      oidc: true                   # an OIDC client in the environment's realm
    healthcheck:
      http: /api/server/ping       # or tcp: 2283, or command: [...]
```

- **Endpoints and exposure** (ADR-0022, ADR-0027):
  - `public`: through the platform's tunnel, at the hostname a public
    service gets today;
  - `access`: through the tunnel, behind Cloudflare Access - for the
    many home lab applications whose own login is weak or absent
    (Radarr, a download client's web UI); new for applications, as the
    platform's admin UIs already are;
  - `internal`: by internal name only, never on Cloudflare - which on a
    home lab still means reachable from the LAN, at the LXC's address or
    the internal name (with the router forwarding the zone, ADR-0027).
  - Only `http` endpoints can be `public` or `access`, at most one per
    application (the tunnel carries HTTP); `tcp` and `udp` endpoints are
    internal. Today's `port` and `public: true` stay, as the short form
    of one `http` endpoint.
- **Volumes** keep data across redeploys, updates and the LXC being
  changed in place:
  - a **named volume** (`name`, `path`, `size`) is a mount point of the
    application's LXC on the platform's Proxmox storage, sized on its
    own, grown in place, included in the LXC's backups, and mounted into
    the container at `path`;
  - a **share** (`share`, `path`, `readOnly`) is a folder that exists
    outside Urbex - a NAS's media library - declared once by the
    operator in `urbex.platform.yaml` (`storage.shares.<name>`: the path
    on the Proxmox node where it is mounted) and mounted into every LXC
    and container that names it. Several applications, on one LXC or
    several, can share it.
  - **Deleting data is explicit**: `urbex destroy <env>` of an
    environment whose applications have named volumes refuses without
    `--delete-data`, naming them, in every environment. Shares are
    never touched.
- **Resources**: `cpu`, `memory`, `disk` as today; `gpu: true` asks for
  the node's GPU (hardware transcoding, machine learning). The
  application only runs on a node the operator prepared for it (see
  *Out of scope*); without one, `apply` stops and says what is missing.
- **SSO**: `auth.keycloak` stays for the user's own code (it validates
  tokens). `auth.oidc: true` creates a confidential OIDC client for the
  application in its environment's realm
  ([ADR-0024](0024-keycloak-realm-per-environment.md)), redirecting to
  its public hostname, and exports `${auth.issuer}`, `${auth.clientId}`
  and `${auth.clientSecret}` to map in `env` - or, for an application
  configured from its own UI, `urbex status` prints them. An application
  without OIDC is gated by `access` instead.
- **Healthchecks**: `http` (a path, probed as today), `tcp` (a port is
  listening) or `command` (run in the container). An application from
  an image without one uses the image's own `HEALTHCHECK`, if it has
  one; otherwise a running container counts.

### Environments

A stack declares its environments:

- `environments: [staging, prod]`, the default: every application, from
  source or from an image, has both, and **`urbex promote` moves the
  whole stack**: prod gets the release staging runs for the applications
  built from source, as today, and the same image digests staging runs
  for the others - so a PostgreSQL update is tried on staging first.
  Each environment has its own data: staging's database is not prod's.
- `environments: [prod]`: one environment, for what a home lab runs for
  itself - its Immich, its media stack. `release` and `promote` don't
  apply and say so; versions change with `urbex deploy prod`.

### Many stacks: on a platform, and in a repository

**A platform runs many stacks**, as it runs many projects today: a home
lab's `photos`, `media` and `vault`, next to the `acme-app` its owner
develops. Each stack is independent:

- its **name** (`project`) is unique on the platform and names its
  LXCs, images, internal names (`<app>.<stack>.<zone>`), Komodo tags and
  GitOps folders (`environments/<env>/<stack>/<app>/`), as a project's
  do today;
- it has **its own environments, versions and lifecycle**: applying,
  updating, promoting or destroying one stack never touches another;
  `urbex status` lists them all, each with its environments.

**A repository holds one stack or several** (refining ADR-0002: the
manifest lives in a repository on Gitea, versioned, but no longer one
per stack):

- **One stack**: `urbex.yaml` at the root, as today - the usual case
  for an application someone develops.
- **Several stacks**: one folder per stack, each with its `urbex.yaml`,
  and at the root an `urbex.yaml` that lists them - the usual case for
  a home lab that keeps all its stacks in one `homelab` repository:

  ```
  homelab/
  ├── urbex.yaml           apiVersion: urbex/v1
  │                        stacks: [photos, media, vault]
  ├── photos/urbex.yaml    the Immich stack
  ├── media/urbex.yaml     the *arr stack
  └── vault/urbex.yaml     Vaultwarden
  ```

  The list is explicit - Urbex doesn't scan the repository - and a
  folder's name is the stack's path, not its name: each manifest still
  says its `project`. Paths in a stack's manifest (`dockerfile`,
  configuration files) are relative to its folder.
- **Commands** act on the stack of the folder they run in; at the root
  of a repository with several stacks, on all of them in the listed
  order, or on one with `--stack <name>`: `urbex apply prod --stack
  media`. A push builds the applications built from source of every
  stack in the repository.
- The Gitea repository's name is its own (given by `urbex init`), no
  longer necessarily a stack's.
- A stack of published images has nothing to build: its folder holds
  `urbex.yaml` and whatever configuration files its applications need.

## Examples

**An application from a public image, with a volume** - Vaultwarden, in
one environment, public (it has its own login):

```yaml
apiVersion: urbex/v1
project: vault
environments: [prod]
services:
  - name: vaultwarden
    image: vaultwarden/server
    version: "1.34.3"
    endpoints:
      - port: 80
        exposure: public
    volumes:
      - name: data
        path: /data
        size: 5Gi
```

**A stack of linked applications** - Immich, its PostgreSQL and its
Redis, on one LXC:

```yaml
apiVersion: urbex/v1
project: photos
environments: [prod]
placement: stack
services:
  - name: server
    image: ghcr.io/immich-app/immich-server
    version: v3                        # Immich's major: --update takes v3.x
    endpoints:
      - port: 2283
        exposure: public
    uses: [db, redis, ml]
    env:                               # Immich's own variable names
      DB_HOSTNAME: ${db.host}
      DB_USERNAME: ${db.user}
      DB_PASSWORD: ${db.password}
      DB_DATABASE_NAME: ${db.database}
      REDIS_HOSTNAME: ${redis.host}
      IMMICH_MACHINE_LEARNING_URL: ${ml.url}
    volumes:
      - name: library
        path: /data
        size: 500Gi
    auth:
      oidc: true                       # issuer and client printed by urbex status
  - name: ml
    image: ghcr.io/immich-app/immich-machine-learning
    version: v3
    endpoints:
      - port: 3003                     # internal
    volumes:
      - name: model-cache
        path: /cache
        size: 10Gi
  - name: db
    image: ghcr.io/immich-app/postgres
    version: 14-vectorchord0.4.3-pgvectors0.2.0
    provides: postgres
    volumes:
      - name: data
        path: /var/lib/postgresql/data
        size: 20Gi
  - name: redis
    image: docker.io/valkey/valkey
    version: "9"
    provides: redis
```

**A distributed stack** - the *arr applications, a download client and
Jellyfin, one LXC each (the default placement), sharing the NAS's media
folder:

```yaml
# urbex.platform.yaml, written once by the operator
storage:
  shares:
    media:
      path: /mnt/pve/nas/media         # where the NAS is mounted on the Proxmox node
```

```yaml
apiVersion: urbex/v1
project: media
environments: [prod]
services:
  - name: qbittorrent
    image: lscr.io/linuxserver/qbittorrent
    version: "5.1.2"
    endpoints:
      - port: 8080
        exposure: access               # its web UI, behind Cloudflare Access
      - port: 6881
        protocol: tcp                  # peers, internal
    volumes:
      - { name: config, path: /config, size: 1Gi }
      - { share: media, path: /media }
  - name: radarr
    image: lscr.io/linuxserver/radarr
    version: "5.26.2"
    endpoints:
      - { port: 7878, exposure: access }
    uses: [qbittorrent]                # its name, for Radarr's download client setting
    volumes:
      - { name: config, path: /config, size: 1Gi }
      - { share: media, path: /media }
  - name: sonarr
    image: lscr.io/linuxserver/sonarr
    version: "4.0.15"
    endpoints:
      - { port: 8989, exposure: access }
    uses: [qbittorrent]
    volumes:
      - { name: config, path: /config, size: 1Gi }
      - { share: media, path: /media }
  - name: jellyfin
    image: jellyfin/jellyfin
    version: "10.10.7"
    endpoints:
      - { port: 8096, exposure: public }   # its own login; also on the LAN
    volumes:
      - { name: config, path: /config, size: 5Gi }
      - { share: media, path: /media, readOnly: true }
    resources:
      gpu: true                        # hardware transcoding
```

**An application built from source that uses a PostgreSQL from its
stack** - staging and production, each with its own database:

```yaml
apiVersion: urbex/v1
project: acme-app
services:
  - name: api
    runtime: go
    port: 8080
    healthcheck: /healthz
    uses: [db]                         # DATABASE_URL and PG*
    auth:
      keycloak: true
  - name: db
    image: postgres
    version: "17"                      # pinned by digest per environment; --update takes 17.x
    provides: postgres
    volumes:
      - name: data
        path: /var/lib/postgresql/data
        size: 20Gi
```

The Immich stack follows Immich's own compose file (images, ports,
paths, variable names; healthchecks are the images' own). Versions in
these examples are illustrative.

## Rationale

- **One model**: a database, a published application and the user's
  own code are deployed, named, monitored, exposed and backed up the
  same way; nothing is special because of where its image comes from.
  The draft `databases` section would have been the first of many
  (`caches`, `queues`, ...).
- **Interfaces, not products**: Urbex knows how to configure a handful
  of protocols (PostgreSQL, MySQL, Redis), and `env` references wire
  any published image without a per-application integration. A curated
  catalog can be built on top of the model later; the model doesn't
  need one.
- **Digests in the GitOps repo** keep ADR-0020's promise - the repo says
  exactly what runs - for images Urbex didn't build.
- **Many stacks per repository** lets a home lab keep its whole setup
  in one versioned place, as it would keep its compose files, while each
  stack keeps its own lifecycle; the explicit list keeps commands
  predictable.
- **Placement as a choice** keeps ADR-0009's isolation where it matters
  (a project's API and its database in production) and gives home labs
  the one-LXC stack they expect, without a second deploy model.
- **`access` exposure** puts the home lab's weakest logins behind the
  platform's SSO instead of on the internet.
- **Refusing to delete data or skip a major version without a flag**
  costs a word on the command line; losing a photo library costs more.

## Out of scope, or later

- **A curated catalog of applications** (`urbex app add immich`):
  manifests prepared for common applications, on top of this model.
  Later: the model must be settled and used first.
- **Backups** of volumes and databases: epic E3. Meanwhile named
  volumes are mount points of the LXC, included in Proxmox's own
  backups (vzdump).
- **GPUs and shares on Proxmox need the operator.** Passing a device
  (`/dev/dri`, a GPU) or binding a host folder into an LXC needs
  `root@pam` on Proxmox - the API refuses both to a token, whatever its
  role - and Urbex works with an API token limited to its pool, never
  as root. `apply` prints
  the one-time `pct set` commands for the operator to run on the node,
  and checks they were applied. Automating them is out of scope.
- **Links between stacks** (an application of one stack using another
  stack's PostgreSQL) and **platform-provided services** satisfying
  `uses` (a shared PostgreSQL): the interfaces make both possible;
  neither is needed by the first users.
- **Update pull requests** (Renovate on the GitOps repo), a
  **pull-through cache** for public registries, and **importing a
  compose file** (`urbex import compose.yaml`).
- **More than two environments**, or names other than `staging` and
  `prod`.
- **Moving a stack between repositories** without recreating it, and a
  stack whose manifest lives in more than one repository.

## Consequences

- `urbex.yaml` grows - all optional, today's manifests stay valid:
  `environments`, `placement`; per application `image` and `version`
  (exclusive with `runtime`), `endpoints`, `uses`, `provides`, `env`
  references, `volumes`, `resources.gpu`, `auth.oidc`, the new
  `healthcheck` forms. `urbex.platform.yaml` gets `storage.shares`.
- Follow-up issues in `urbex-cli`, to open once this is accepted:
  1. the manifest schema and its validation (references, ports per LXC,
     one public endpoint per application), and repositories with
     several stacks (the root `stacks` list, `--stack`, paths relative
     to a stack's folder, builds of every stack on a push);
  2. applications from images: no Build, `version.env` with tag and
     digest, `deploy --update` / `--version` / `--allow-major`, `promote`
     of a whole stack, single-environment stacks;
  3. interfaces and links: generated credentials, injected variables,
     `env` references, deploy order by `uses`;
  4. volumes and shares: Proxmox mount points, `storage.shares`, the
     operator's `pct set` commands, `destroy --delete-data`;
  5. `placement: stack`: one LXC per stack-environment, several Stacks
     on one Server, names to the same address;
  6. endpoints and exposure: several ports, `tcp`/`udp`, `access` for
     applications (tunnel route plus Access application);
  7. `auth.oidc` clients in the environment's realm;
  8. healthchecks (`tcp`, `command`, the image's own);
  9. the e2e, with a stack from images.
- The PostgreSQL work ([urbforge/urbex#6](https://github.com/urbforge/urbex/issues/6),
  [urbforge/urbex-cli#9](https://github.com/urbforge/urbex-cli/issues/9))
  becomes the `postgres` interface plus its integration (version guard,
  data, Grafana), and its draft ADR is rewritten on this model.
- ADR-0027's table changes: the *project database* row becomes an
  application in a stack, `app`, internal; project applications can be
  `access`.
- The manifest and GitOps references, the getting started and the
  cookbook gain stacks from images (urbforge/urbex#25 reviews them for
  home lab owners).
- More of what runs comes from public registries: their availability
  and rate limits (Docker Hub's) affect deploys until a pull-through
  cache exists.
