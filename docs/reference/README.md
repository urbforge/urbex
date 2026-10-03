# Reference

Complete, precise descriptions of everything Urbex reads, writes, and
creates. For walkthroughs, see [getting started](../getting-started.md)
and the [cookbook](../cookbook.md).

| Page | Covers |
|---|---|
| [CLI](cli.md) | Every `urbex` command: what it does step by step, its flags, what it needs. |
| [Manifest (`urbex.yaml`)](manifest.md) | Every field of a project's manifest, the runtimes, and how each change takes effect. |
| [Platform config (`urbex.platform.yaml`)](platform-config.md) | Every platform setting, its default, and how addresses are allocated. |
| [GitOps repo](gitops-repo.md) | The repo's layout; `version.env`, `config.env`, `secrets.sops.env`, `compose.yaml`; how a commit becomes a deploy. |
| [Credentials](credentials.md) | Every credential, where it's read from, and how to obtain it. |
| [Platform resources](platform-resources.md) | Everything created on Proxmox, Gitea, and Komodo, and what's safe to change by hand. |

The formal manifest schema is
[`schemas/urbex.schema.json`](../../schemas/urbex.schema.json); the
reasons behind the design are in the [decision records](../decisions/).
