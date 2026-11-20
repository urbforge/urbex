# Changelog

What changed in each release of urbforge/urbex: the documentation and
the **Claude Code plugin** (`.claude-plugin`, `skills/`). The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), with
**Breaking** and **Upgrading** sections when a release needs them.

urbex is tagged together with urbex-cli (`v0.1.0` in both); the CLI, the
`urbex-op` script and its image have their own changelog, in
[urbforge/urbex-cli](https://github.com/urbforge/urbex-cli/blob/main/CHANGELOG.md).

**The plugin has its own version**, in `.claude-plugin/plugin.json`. It
works with any `urbex` of the same major version; while both are 0.x a
minor may still break, so each plugin version states the minimum `urbex`
it needs (see [Upgrading](docs/upgrading.md#plugin-and-cli-versions)).

A pull request that changes what users see adds a line under
*Unreleased*; a release moves them under its version - the release
workflow refuses a tag whose version has no entry here.

## [Unreleased]

### Plugin 0.2.3

Needs **urbex 0.1.0 or later, major 0**; works with urbex 0.2.0.

- **Changed**: the `cli` skill knows `urbex bootstrap`'s refusal on a
  platform created by 0.1.0 (its forge is Gitea): it explains it and
  points to the upgrading guide, and runs none of the destroying steps
  unless asked (urbforge/urbex-cli#134).

### Plugin 0.2.2

Needs **urbex 0.1.0 or later, major 0**.

- **Changed**: the `setup` skill goes on without Cloudflare and mentions
  the options, asking only when the user wants public addresses; the
  durations the skills give are the test node's (a first bootstrap about
  20 minutes, a first apply about 6); the default workspace is
  `~/urbex-work`, as `urbex-op`'s (urbforge/urbex#57).

### Plugin 0.2.1

Needs **urbex 0.1.0 or later, major 0**.

- **Changed**: the skills name the forge Forgejo, and its credentials
  `forgeToken` and `forgeAdminPassword`; the `cli` skill's token check
  accepts `giteaToken` too, for a workspace written by urbex 0.1.0.

### Docs

- **Added**: *From 0.1.0 to 0.2.0* in the upgrading guide - Forgejo in
  place of Gitea, why a 0.1.0 platform is started again rather than
  upgraded, the steps, and that 0.2.0 carries the Java4Shell mitigation.
- **Changed**: getting started installs the plugin from the terminal too
  (`claude plugin ...`, then `/reload-plugins`), and gives the test
  node's durations; the default workspace is `~/urbex-work` everywhere.
- **Added**: a home-lab path - recipes for an app from its image with its
  data (Vaultwarden), a stack of linked apps (Paperless-ngx with
  PostgreSQL and Redis), a distributed stack sharing a NAS (the *arr
  stack with Jellyfin); the limitations a home lab meets (non-HTTP
  healthchecks, PostgreSQL extensions, GPUs, app SSO).

- **Added**: `komodo.buildCache` in the platform config, the build cache's
  pruning in the platform resources, the cookbook and ADR-0027's table.
- **Added**: Java4Shell (CVE-2026-114938) in the known limitations - mitigated in Keycloak and the `runtime: java` images, until fixed images exist (urbforge/urbex-cli#130).
- **Added**: getting Urbex's alerts on Telegram, Discord or a webhook - the cookbook's steps (BotFather, the chat id, Discord's webhook), `observability.alerts` in the platform config, the three credentials, `urbex doctor --test-alerts` (urbforge/urbex-cli#95).
- **Changed**: the examples' images moved to current versions - nginx `1.31` (NGINX2Root, CVE-2026-123007, is fixed in 1.31.9), Caddy `2.11`, Vaultwarden `1.37.5`, Jellyfin `10.11.11`, rclone `1.76` - and a cookbook recipe on keeping applications from images up to date, with the HTTP/2 note for nginx (urbforge/urbex#99).

- **Added**: [ADR-0034](docs/decisions/0034-forgejo-lts-forge.md) -
  Forgejo LTS is the platform's forge, in place of Gitea; the known
  limitation for platforms installed with 0.1.0, which stay on Gitea
  1.24.
- **Changed**: Gitea is Forgejo throughout; the reference documents
  `forgeToken`, `forgeAdminPassword`, `URBEX_FORGE_*` and `git.forgeUrl`,
  the old names still read.

## [0.1.0] - 2026-11-17

The first preview release: the docs install urbex from the
[urbex-cli v0.1.0 release](https://github.com/urbforge/urbex-cli/releases/tag/v0.1.0)
instead of a clone.

### Plugin 0.2.0

Needs **urbex 0.1.0 or later, major 0**.

- **Added**: the plugin's own version, and its check of `urbex version`
  once per session: it says when urbex is older than it needs, or of
  another major.
- **Changed**: the `setup` skill downloads `urbex-op` from the newest
  release instead of cloning and building urbex-cli; its prerequisites
  check reads the image from `urbex-op version`.
- The `setup`, `cli` and `manifest` skills: setting up the platform from
  an empty Proxmox node, every `urbex` command with the ones that need
  your confirmation, and writing `urbex.yaml`.

### Docs

- **Added**: [Upgrading](docs/upgrading.md); `urbex version` in the CLI
  reference.
- **Changed**: getting started (with the CLI, Claude Code or another
  agent) and the cookbook install from the release; the README says
  *preview release* and links the known limitations.

### Known limitations

A preview: no backups of the platform yet, Proxmox only, a single
operator. See the [known limitations](docs/known-limitations.md).

[Unreleased]: https://github.com/urbforge/urbex/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/urbforge/urbex/releases/tag/v0.1.0
