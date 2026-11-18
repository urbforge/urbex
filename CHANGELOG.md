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

- **Changed**: getting started installs the plugin from the terminal too
  (`claude plugin ...`, then `/reload-plugins`), and gives the test
  node's durations; the default workspace is `~/urbex-work` everywhere.

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
