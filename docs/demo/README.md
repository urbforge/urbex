# The README's demo

The GIF at the top of the [README](../../README.md) shows the app side of
Urbex's flow on a platform that is already there: `urbex apply staging`,
the app's public URL, `urbex release`, `urbex promote`, `urbex status`.
It is recorded from a script, on a real platform, with the project in
[`examples/demo`](../../examples/demo): a web page and the small API it
calls, two Go services, `web` public and `api` reached by its internal
name.

| File | What it is |
|---|---|
| `readme.tape` | The recording, for [VHS](https://github.com/charmbracelet/vhs): the commands typed, and where the waits are cut. |
| `demo-env.sh` | Sourced, hidden, before the recording: the prompt, and the filter of urbex's output. |
| `Containerfile` | The operator image of `urbex-cli` (`tools/operator`) plus VHS, ttyd, Chromium and ffmpeg. |
| `record.sh` | Copies the demo into a repo of its own, applies production, records, and copies the GIF here. |

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

The tape names the Cubotto lab platform's public addresses (zone
`urbex.cubotto.net`, flat hostnames): change them in `readme.tape` for
another platform. Keep the GIF under 5 MB.

## How the waits are cut, and what is hidden

- **Waits:** VHS records in real time, so each long command runs between
  `Hide` and `Show`: the GIF shows it typed and how it ends, not the
  minutes in between. VHS rather than asciinema because a recording
  from a script is reproducible, and because `apply` keeps printing
  while it works: an idle-time limit wouldn't cut anything.
- **Output:** Ansible's and Terraform's own lines are left out. `apply`
  runs both, and their lines scroll by while the wait is cut anyway.
- **Nothing private:** LAN addresses are replaced with `<lan>`. `urbex
  status` without an environment is cut to its *Projects* section,
  each line to the terminal's width: the platform's endpoints and logins
  aren't shown. No password, token or `credentials.yaml` is ever printed
  by these commands.

`demo-env.sh` does all of it, as a shell function `urbex` that calls the
real one.
