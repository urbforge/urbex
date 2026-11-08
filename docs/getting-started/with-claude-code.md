# Getting started with Claude Code

This repository is a [Claude Code](https://claude.com/claude-code)
plugin, `urbex`. With it, Claude Code sets up Urbex and runs it for you.
It finds your network and Proxmox settings by itself, proposes them, and
asks you to confirm. Before you start, read the
[prerequisites](../getting-started.md#prerequisites). You don't have to
prepare anything yet: the plugin gives you each command when it's needed.

## 1. Install the plugin

In Claude Code, run these two commands one at a time:

```
/plugin marketplace add urbforge/urbex
```

```
/plugin install urbex@urbex
```

From the `/plugin` menu instead, choose *Add Marketplace* and enter only
`urbforge/urbex`; then install `urbex` from the marketplace's list.

It also needs `python3`, 3.8 or later, on your machine, for the scripts
that find your settings. Until `urbex-cli` is public, you need access to
[`urbforge/urbex-cli`](https://github.com/urbforge/urbex-cli) to build
`urbex`.

## 2. Set up Urbex

Start Claude Code in an empty folder and run:

```
/urbex:setup
```

Or ask in plain words: "set up Urbex on my Proxmox node". What happens:

1. **It looks around**, without asking anything: the tools on your
   machine, your LAN's CIDR, gateway and DNS, the Proxmox nodes on the
   LAN, and a block of free addresses. To find the free addresses, it
   pings each address of the LAN once.
2. **It asks one question**: whether you use Cloudflare. The choices are
   none, a Quick Tunnel, or your own zone.
3. **It builds `urbex-op`** and creates the workspace in `~/urbex-work`.
4. **You prepare Proxmox**, choosing between two ways: a script, which
   it recommends, or the commands by hand. The script runs in your own
   terminal, not in the chat. It asks for the password of `root@pam` without showing it,
   and for a two-factor code if you have one. If the node's certificate
   is self-signed, it first shows you its fingerprint to check. Then it
   lists what it will create and waits for your yes. It picks the
   storage, the bridge and the template by itself, and stores the token
   in the workspace without showing it. The password is used only to log
   in. By hand, you run a block of root commands on the node, which
   gets no password, and store the token with
   `urbex-op set proxmoxToken`.

   With your own zone, it also tells you how to create the Cloudflare
   token, which you store in another terminal:
   ```sh
   export URBEX_WORKSPACE=~/urbex-work
   urbex-op set cloudflareToken
   ```
5. **It reads the rest from the APIs** with your tokens, without
   printing them: node, storage, bridge, template, pool, and your zone's
   IDs. Then it proposes the whole `urbex.platform.yaml`, saying where
   each value comes from. Check that the address block is outside your
   DHCP range: nothing else can check that.
6. **It asks before `urbex bootstrap`**, then follows it, for about
   twenty minutes, and gives you the platform's addresses.
7. **Your first app**: give it the repository's URL or path. It writes
   `urbex.yaml` from the code, shows it to you, and deploys the app to
   staging.

Back up `~/urbex-work/home/age.key`, and the workspace: the plugin
reminds you.

## 3. Every day

Ask in plain words, or call a skill directly:

| Skill | For | Examples |
|---|---|---|
| `/urbex:manifest` | Write and change `urbex.yaml`, then validate it | "add a PostgreSQL database", "make the API public", "give it more memory", "deploy this Docker image" |
| `/urbex:cli` | Every `urbex` command | "deploy to staging", "what runs in prod?", "release and promote", "roll back prod", "set the STRIPE_KEY secret" |

What it never does without asking you first:

- **Production and releases**: anything on prod, `urbex release`, and
  `urbex promote`.
- **Pushes**: a push to `main`, which deploys to staging.
- **Deleting**: `destroy`, `teardown`, and any `--delete-data`.

Secrets go through your terminal, never through the chat: when you ask
it to set one, it gives you the commands to type.

## Without the plugin

Any agent can do the same with one prompt: see
[With an AI agent](with-an-ai-agent.md). The commands it runs are in
[With the CLI](with-the-cli.md).
