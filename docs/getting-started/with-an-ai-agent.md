# Getting started with an AI agent

Before you start, check the [prerequisites](../getting-started.md#prerequisites).

An agent like Claude Code or Codex can do the setup for you, following
the [CLI guide](with-the-cli.md). Two things stay yours:

1. **The Proxmox prerequisites**: they need root on the node. The agent
   gives you the commands, from [prerequisites](../getting-started.md#prerequisites).
2. **The tokens**: give them to Urbex yourself, so they never go through
   the chat. After the agent has run `urbex-op init`, run
   `urbex-op set proxmoxToken` (and `cloudflareToken`) in your own
   terminal.

Start the agent in an empty folder and give it this prompt, adapted to
your app:

```text
Set up Urbex for me and deploy my app with it.

1. Clone https://github.com/urbforge/urbex and https://github.com/urbforge/urbex-cli
   side by side, then read urbex/docs/getting-started.md and
   urbex/docs/getting-started/with-the-cli.md, and follow the latter
   with the container (urbex-op).
2. Find every value yourself, don't ask me for what you can discover:
   from this machine the LAN's CIDR, gateway and DNS, the Proxmox node
   (port 8006 on the LAN) and a free block of addresses; once my tokens
   are stored, from the Proxmox API the node, storage, bridge, template
   and pool, and from the Cloudflare API my zone and its IDs. Never print
   a token. Ask me only whether I use Cloudflare (none, Quick Tunnel or
   my zone).
3. Give me what I have to do myself: the commands of "Prerequisites" in
   getting-started.md to run as root on Proxmox, and, with my zone, how to create the
   Cloudflare token (urbex/docs/reference/credentials.md). After
   `urbex-op init`, ask me to run `urbex-op set proxmoxToken` (and
   `cloudflareToken`) in my terminal. Never ask me for a token in the
   chat, and never print the credentials file or the age key.
4. Propose the whole urbex.platform.yaml, saying where each value comes
   from, and ask me to confirm it once.
5. My app is <git URL or path>. Write its urbex.yaml from its code, show
   it to me, then deploy it to staging and give me its address.
6. Ask me before `urbex bootstrap`, `urbex apply prod`, `urbex release`
   and `urbex promote`.
```

From then on, ask in plain words: "deploy to staging", "what runs in
prod?", "set the STRIPE_KEY secret in prod", "release and promote". The
agent finds the commands in the [CLI reference](../reference/cli.md).
