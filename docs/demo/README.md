# The README's demos

The two GIFs at the top of the [README](../../README.md) show the app side
of Urbex's flow on a platform that is already there. `readme.gif` types
the CLI: `urbex apply staging`, the app's public URL, `urbex release`,
`urbex promote`, `urbex status`. `claude.gif` asks the same of Claude
Code with Urbex's plugin: "deploy this app to staging", "release it and
promote it to production" (Claude asks first, the recording says yes),
"what runs where?". Each is recorded from a script, on a real platform, with the project in
[`examples/demo`](../../examples/demo): a web page and the small API it
calls, two Go services, `web` public and `api` reached by its internal
name.

| File | What it is |
|---|---|
| `readme.tape` | The recording, for [VHS](https://github.com/charmbracelet/vhs): the commands typed, and where the waits are cut. |
| `demo-env.sh` | Sourced, hidden, before the recording: the prompt, and the filter of urbex's output. |
| `Containerfile` | The operator image of `urbex-cli` (`tools/operator`) plus VHS, ttyd, Chromium and ffmpeg. |
| `record.sh` | Copies the demo into a repo of its own, applies production, records, and copies the GIF here. |
| `claude.tape` | The Claude Code recording: the requests typed, Claude's work cut. |
| `claude/` | Claude Code's settings for it (permissions, the hooks and the status line that say when Claude waits for the user). |
| `claude-env.sh` | Sourced, hidden, before Claude starts: its settings and login, and `bin/` first on the `PATH`. |
| `bin/` | The `urbex`, `curl` and `git` Claude runs: the real ones through `demo-env.sh`'s filter. |

## Record it again

You need a platform, an `urbex-op` workspace with its credentials, and
the operator image of `urbex-cli` (`mise run operator-image`). On the
platform, the project `demo` must not exist yet.

```sh
URBEX_OPERATOR_IMAGE=urbex-operator docs/demo/record.sh ~/urbex-workspace
```

It takes about 15 minutes, nearly all of it the first `apply` (the
LXCs, Komodo, the build of `main`). Then remove the project:

```sh
cd ~/urbex-workspace/demo/app && urbex destroy staging && urbex destroy prod
```

`claude.gif` the same way, on a fresh project again, with your Claude
Code login:

```sh
claude setup-token                  # once: a token for scripts, then
export CLAUDE_CODE_OAUTH_TOKEN=...  # (or nothing: a copy of ~/.claude/.credentials.json is used)
URBEX_OPERATOR_IMAGE=urbex-operator docs/demo/record.sh ~/urbex-workspace claude
```

The login goes into the workspace's `demo/claude-home` for the recording
only, and is deleted when it ends. Prefer the token: Claude Code in the
container may refresh a copied login, and the one on your machine then
has to log in again.

The GIFs show `example.com` in place of the platform's domain: the tape
types it, `demo-env.sh` replaces the domain in every output with it, and
its `curl` asks the real one, read from the workspace's
`gitops/urbex.platform.yaml`. The tape assumes flat hostnames
(`<name>-urbex.<domain>`). Keep the GIF under 5 MB.

## How the waits are cut, and what is hidden

- **Waits:** VHS records in real time, so each long command runs between
  `Hide` and `Show`: the GIF shows it typed and how it ends, not the
  minutes in between. VHS rather than asciinema because a recording
  from a script is reproducible, and because `apply` keeps printing
  while it works: an idle-time limit wouldn't cut anything.
- **Output:** Ansible's and Terraform's own lines are left out. `apply`
  runs both, and their lines scroll by while the wait is cut anyway.
- **Nothing private:** LAN addresses are replaced with `<lan>`. `urbex
  status` without an environment shows the platform's services with
  their public addresses only (its *Endpoints* section without the
  internal and LAN columns), then the demo's lines of *Projects*; the
  logins section isn't shown. No password, token or `credentials.yaml`
  is ever printed by these commands.
- **Each command on a clean screen:** the screen is cleared, hidden,
  before a command is typed, so the command and its output show
  together.

`demo-env.sh` does all of it, as a shell function `urbex` that calls the
real one.

## Claude Code's recording

- **Claude works hidden.** Each request is typed, then the recording
  hides until Claude waits for the user again, and shows its answer. The
  status line says when: `● ready`, set by a `Stop` hook, `○ working`
  from a `UserPromptSubmit` hook and while `bin/urbex` runs - also in
  the background, as the plugin follows `apply` - until Claude, told the
  command ended, stops (`claude/statusline.sh`, refreshed every second).
- **Each request on a clean screen:** `/clear`, hidden, before it.
- **What Claude may run:** the session is in `bypassPermissions`, in a
  container that holds only the demo and the workspace, with deny rules
  for the workspace's credentials, the GitOps repo and `git push`. The
  plugin's own rule still applies: Claude asks before `release` and
  `promote`, and the recording answers "yes".
- **Nothing private, for Claude either:** the `urbex`, `curl` and `git`
  Claude runs are those of `bin/`, which pass their output through the
  same filter as the CLI's recording, plain. Claude reads `<lan>` and
  `example.com`, so its answers show nothing else; `curl` and `bin/urbex`
  reach the real domain.
