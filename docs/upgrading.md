# Upgrading

Urbex is released from [`urbforge/urbex-cli`](https://github.com/urbforge/urbex-cli/releases):
the `urbex` binaries, `urbex-op`, and its image
`ghcr.io/urbforge/urbex-op:<version>`. Moving to a new release changes
the tools on your machine. The workspace, the GitOps repo, the platform
and your projects stay as they are.

While Urbex is 0.x (a preview), a minor release may still change how
something works. **Read the release's notes first**: they say when a
command is needed after upgrading.

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
which its `cli` skill states: urbex 0.1.0 for plugin 0.2.1.

### Plugin and CLI versions

| Plugin | urbex |
|---|---|
| 0.2.0, 0.2.1 | 0.1.0 or later, major 0 |

The plugin checks `urbex version` once per session. When `urbex` is
older than it needs, it says so and points here. When the major versions
differ, update the plugin or use an `urbex` of the plugin's major.

To update the plugin, refresh its marketplace in Claude Code:

```text
/plugin marketplace update urbex
```

Then update `urbex` from the `/plugin` menu if it didn't update by
itself, and restart Claude Code.
