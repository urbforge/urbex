# ADR-0001: Urbex is a CLI, not (only) an MCP server

## Status

Accepted

## Context

Urbex must be usable by an LLM (Claude Code, Codex) to automatically
create infrastructure, as well as by a human. Options considered:

- CLI tool invoked via shell.
- MCP server with structured tools.
- A Claude Code-specific skill/plugin wrapping scripts.
- A combination of the above.

## Decision

Urbex is, first and foremost, a **CLI** (`urbex`). Any agent with shell
access (Claude Code, Codex, or a human) can drive it. An additional layer
(a Claude Code skill, or an MCP server) may be built on top of the CLI in
the future for a better UX in specific contexts, but it does not replace
it.

## Rationale

- Portability: works with both Claude Code and Codex from day one, without
  depending on the host's MCP support.
- Debuggability: text/JSON output that a human can inspect, easy to log
  and test in CI.
- No lock-in to a specific protocol/host.

## Consequences

- Command design must be readable both by an LLM (optional
  structured/JSON output) and by a human (human-readable output by
  default).
- Any future MCP server will be a thin wrapper over the CLI commands, not
  a parallel implementation.
