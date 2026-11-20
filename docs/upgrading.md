# Upgrading

Urbex is released from [`urbforge/urbex-cli`](https://github.com/urbforge/urbex-cli/releases):
the `urbex` binaries, `urbex-op`, and its image
`ghcr.io/urbforge/urbex-op:<version>`. Moving to a new release changes
the tools on your machine. The workspace, the GitOps repo, the platform
and your projects stay as they are.

While Urbex is 0.x (a preview), a minor release may still change how
something works. **Read the release's notes first** - its GitHub release,
or the `CHANGELOG.md` of [urbex-cli](https://github.com/urbforge/urbex-cli/blob/main/CHANGELOG.md)
and of [this repository](../CHANGELOG.md): their *Breaking* and
*Upgrading* sections say when a command is needed after upgrading.

## From 0.1.0 to 0.2.0

0.2.0 brings the Java4Shell mitigation (CVE-2026-114938: Keycloak's JVM
and the `runtime: java` images run without the vulnerable Base64
intrinsic) and replaces the forge: **Forgejo 15 LTS instead of Gitea 1.24**
([ADR-0034](decisions/0034-forgejo-lts-forge.md)).

Forgejo can't open the database of Gitea 1.24, so a platform created by
0.1.0 can't be bootstrapped again in place: `urbex bootstrap` with 0.2.0
sees that its forge is Gitea and refuses, changing nothing. To get
0.2.0's platform, Java4Shell's mitigation included, start the platform
again:

1. Back up what you keep in the applications' named volumes ([back up
   and restore an application's data](cookbook.md#back-up-and-restore-an-applications-data)):
   they go with their LXCs.
2. `urbex destroy <env>` for each environment of each project.
3. `urbex teardown --yes`: the platform's LXCs go, Gitea's repositories
   and images with them.
4. Upgrade the tools (below), then `urbex bootstrap`.
5. Push each project's repository again from your clone, and `urbex
   apply` its environments; restore the volumes' data.

The workspace needs no change: the credentials and the platform config
that 0.1.0 wrote are read as they are (`giteaToken`, `git.giteaUrl`; the
new names `forgeToken`, `git.forgeUrl` win when both are set).

Staying on 0.1.0 is possible: keep its `urbex-op` and don't run 0.2.0
against that platform. Its Keycloak then keeps the Java4Shell exposure
on CPUs with AVX-512 VBMI (see the [known limitations](known-limitations.md#operations-and-security)).

## With urbex-op

Download the new release's `urbex-op` over the old one. Its next command
pulls the new image:

```sh
curl -fsSLo ~/bin/urbex-op https://github.com/urbforge/urbex-cli/releases/download/v0.2.0/urbex-op
urbex-op version                 # urbex-op 0.2.0, image ghcr.io/urbforge/urbex-op:0.2.0
urbex-op 'urbex version'         # pulls the image the first time
urbex-op 'urbex doctor'
```

Put the version you are moving to in the URL (`v0.2.0` above is an
example). The old image stays on your machine until you remove it, e.g.
`podman rmi ghcr.io/urbforge/urbex-op:0.1.0`. To go back, download the
old release's `urbex-op`.

### From a checkout of urbex-cli

If you ran Urbex before the first release, `urbex-op` is a link to a
checkout of `urbex-cli`, and its image is the one `urbex-op build` made.
Download the release's `urbex-op` in its place, as above. Unset
`URBEX_OPERATOR_IMAGE` if you set it: a release's `urbex-op` runs its own
image. The workspace stays the same.

To keep working from the checkout instead (to work on urbex), pull it
and run `tools/operator/urbex-op build` again.

## Native

Download the new archive and replace `urbex`, as in
[Native tools](getting-started/with-the-cli.md#native-tools). Also check
that Terraform, Ansible, sops and age are at the versions the release's
`mise.toml` pins: `urbex doctor` lists them.

## The Claude Code plugin

The plugin has its own version. It works with any `urbex` of the same
major version (0 today). While both are 0.x it also needs a minimum,
which its `cli` skill states: urbex 0.1.0 for plugin 0.2.3. urbex 0.2.0
needs no newer plugin.

### Plugin and CLI versions

| Plugin | urbex |
|---|---|
| 0.2.0 to 0.2.3 | 0.1.0 or later, major 0 |

The plugin checks `urbex version` once per session. When `urbex` is
older than it needs, it says so and points here. When the major versions
differ, update the plugin or use an `urbex` of the plugin's major.

To update the plugin, refresh its marketplace in Claude Code:

```text
/plugin marketplace update urbex
```

Then update `urbex` from the `/plugin` menu if it didn't update by
itself, and restart Claude Code.
