# ADR-0032: A local setup UI, a console in the platform and an optional AI assistant, on one backend

## Status

Proposed. Tracked by [urbforge/urbex#60](https://github.com/urbforge/urbex/issues/60).
Part of [urbforge/redemptor#47](https://github.com/urbforge/redemptor/issues/47)
(E14 Web UI and AI assistant). Adds a base service under
[ADR-0027](0027-service-conventions.md)'s conventions.

## Context

Today there are two ways to install and run Urbex:

- **The CLI**, through `urbex-op`. It assumes the operator knows
  Proxmox, Komodo, Keycloak, Cloudflare and GitOps, or reads the docs
  until they do.
- **The Claude Code plugin** (`/urbex:setup`, `/urbex:manifest`,
  `/urbex:cli`). It explains each step, discovers the node, proposes
  `urbex.platform.yaml`, and when something fails it reads the error and
  proposes a fix. It needs Claude Code and a Claude subscription.

Urbex's first users are home lab owners
([E13](https://github.com/urbforge/redemptor/issues/38)). Many of them
have neither tool, or don't want an agent acting on their node. Once the
platform is up, nothing in one place shows what runs and how to reach
it, or explains monitoring, the pipeline from a push to production, or
the security model.

The plugin's guided steps live in its own scripts:
`check-prerequisites.sh`, `discover-platform.py`, `prepare-proxmox.py`,
`follow-progress.py`. The CLI doesn't have them. The end-to-end test of
[urbforge/redemptor#46](https://github.com/urbforge/redemptor/issues/46)
found the skills, the docs and the CLI out of step
([urbforge/urbex#57](https://github.com/urbforge/urbex/issues/57)). A
third front end built the same way would make that worse.

## Decision

### 1. The CLI is the only backend

Everything the plugin's scripts do moves into the CLI as commands with
machine-readable output
([urbforge/urbex-cli#74](https://github.com/urbforge/urbex-cli/issues/74)):

- `urbex doctor`: prerequisites and workspace.
- `urbex discover`: the node, free VMIDs and IPs, Cloudflare zones, and
  a proposed `urbex.platform.yaml`.
- `--events json` on `bootstrap`, `apply`, `destroy` and `teardown`.
  The run goes on in the background and can be followed again after a
  disconnect.
- `--output json` on `status` and `users`.

The plugin, the local UI, the console and the MCP server are front ends
on these commands. None of them implements a step of its own.

### 2. `urbex mcp`

`urbex mcp` serves the same commands as MCP tools
([urbforge/urbex-cli#75](https://github.com/urbforge/urbex-cli/issues/75)):
over stdio for a local client, over HTTP for the console.

- Read-only tools are open.
- Tools that change something (`apply`, `destroy`, writing `urbex.yaml`)
  are marked destructive, so the client asks before running them.
- No tool output contains a secret.

An operator who already uses an MCP client (Claude Code, Claude
Desktop, others) drives Urbex from it, on their own subscription, with
no key in Urbex. The Claude Code plugin moves onto it.

### 3. Setup in a local web UI

Before bootstrap there is no platform to serve a UI, so the first
install runs locally:
`urbex setup --web` ([urbforge/urbex-cli#77](https://github.com/urbforge/urbex-cli/issues/77)),
also inside `urbex-op` with the port published.

- **Locked to the operator's machine:** it listens on `127.0.0.1` only,
  with a one-time token in the URL, as Jupyter does, and CSRF
  protection.
- **Steps:** prerequisites; Proxmox, where the root commands are shown
  for the operator to copy, since nothing in Urbex runs as root on the
  host; the tokens, written to `credentials.yaml` and never shown
  again; the workspace; `urbex.platform.yaml` from `urbex discover`;
  and bootstrap, with live progress.
- **Plain-word explanations:** next to each step, what that step
  creates and why.
- **After bootstrap:** it hands over to the console.

### 4. After bootstrap, a console in the platform

A new base service, `urbex-console`
([urbforge/urbex-cli#76](https://github.com/urbforge/urbex-cli/issues/76)).

- **Where it runs:** its own LXC, created by bootstrap like the others:
  1 core, 512 MiB, 4 GB, to be confirmed by
  [urbforge/urbex-cli#64](https://github.com/urbforge/urbex-cli/issues/64).
  Running it on Komodo's LXC would save an LXC, but would tie the
  console's failures and upgrades to the deployer's.
- **Sign-in:** OIDC with Keycloak, in the `urbex` realm of the
  operators (urbforge/urbex-cli#16).
  - A *viewer* role reads.
  - An *operator* role may `apply`, `deploy` and `destroy`.
  - With Cloudflare it also sits behind Access, like Gitea and Komodo.
    With the Quick Tunnel it stays on the LAN.
- **What it shows:**
  - the platform's and the projects' status;
  - links to Gitea, Komodo, Grafana and Keycloak, each with a short
    explanation;
  - the logins, without the passwords;
  - the project templates.
- **What it calls:** the CLI's commands, through `urbex mcp` over HTTP
  or as a library. It holds the platform's credentials the way Komodo's
  Actions do: SOPS-encrypted, decrypted on its LXC.
- **Where to find it:** `urbex status` and the local UI print its LAN
  and public addresses, as they do for Grafana.
- **When it's down:** if the platform is broken, the console may be
  down too. The CLI and the local UI keep working on their own, and are
  how it is repaired.

### 5. An optional AI assistant

An assistant in the local UI and in the console
([urbforge/urbex-cli#78](https://github.com/urbforge/urbex-cli/issues/78)),
using the MCP tools. It covers setup, troubleshooting and writing
`urbex.yaml`.

- **Providers:** an API key for Anthropic, OpenAI or an
  OpenAI-compatible endpoint, or a local model (e.g. Ollama). The key
  is a secret like the others: in `credentials.yaml` locally, under
  SOPS in the platform.
- **No subscription login.** Anthropic does not allow third-party
  products to sign in with a Claude.ai account. OpenAI's
  "Sign in with ChatGPT" is for its own tools. Operators with a
  subscription use `urbex mcp` from their own client (§2). Check both
  providers' current terms when building.
- **Guardrails:**
  - Read-only tools run freely.
  - Any change is shown as a proposal with its diff, and runs only after
    the operator confirms it in the UI.
  - Secrets are removed from logs and configuration before anything is
    sent, and the UI says what is sent.
  - Logs, manifests and web content are data, never instructions.
- **Off by default:** with no provider configured, the UIs work fully
  without it.

### 6. Templates instead of YAML for common projects

`urbex init --template <name>` and the same templates in the UIs
([urbforge/urbex-cli#79](https://github.com/urbforge/urbex-cli/issues/79)):

- a backend and a frontend;
- a backend and PostgreSQL;
- a published image;
- later, the *arr stack
  ([urbforge/urbex-cli#63](https://github.com/urbforge/urbex-cli/issues/63)).

The result is an ordinary `urbex.yaml`, validated against the schema,
that can still be edited by hand.

## Rationale

- **One backend.** Each front end that implemented its own steps would
  drift, as the plugin's scripts already have. With the CLI as the only
  backend, a fix lands once, and the e2e test covers every front end.
- **A local UI for setup.** The platform can't serve the UI that
  creates it. A local UI is also where the Proxmox and Cloudflare tokens
  are entered, without passing through a browser on another machine or
  through an agent's chat.
- **A console in the platform after setup.** It is always there, behind
  the same SSO as the rest. It needs nothing installed on the
  operator's machine, so a second operator, or a phone, can reach it.
- **An API key, a local model or MCP.** These are the access paths the
  providers support. MCP keeps subscriptions usable without Urbex
  holding the operator's account. A local model keeps the assistant
  usable with no external service at all.
- **Assistant off by default and confirmation for changes.** Without an
  AI the guided path still works. When the AI is on, it can be wrong or
  be led astray by a log line, but never acts on the platform without
  the operator.

## Out of scope, or later

- A hosted Urbex service. Everything runs on the operator's machine or
  platform.
- A visual editor for every field of `urbex.yaml`. Templates cover the
  common cases; the rest is YAML, which the assistant can help write.
- Fine-grained permissions in the console beyond *viewer* and
  *operator*. They come with E7's roles.
- A platform with several nodes, and VPS hosts (E3-bis).

## Consequences

- **More code in the CLI.** `doctor`, `discover`, JSON output and
  events all join the CLI. The plugin gets thinner, and its scripts are
  removed once the CLI covers them.
- **A seventh base service.** Bootstrap, teardown, `urbex status`, the
  known limitations and the resource figures change with it.
- **The console holds the platform's tokens.** It is a high-value
  target: SSO is mandatory, roles are enforced on the server side, and
  it is never public without Access.
- **Front ends must stay compatible with the CLI.** The console is
  upgraded with the platform (`urbex upgrade`). The e2e test covers the
  local UI, the console and `urbex mcp`, with the assistant against a
  fake provider.
- **The assistant brings costs and privacy questions.** The docs say
  what is sent to a provider, what it costs, and how to use a local
  model instead.
