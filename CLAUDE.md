# CLAUDE.md

`urbex` holds Urbex's documentation, its design decisions (ADRs) and the
manifest schema. The CLI is in [`urbforge/urbex-cli`](https://github.com/urbforge/urbex-cli).

## How we work

The team's rules - issues, branches, Conventional Commits, pull requests,
definitions of ready and done - are in `docs/development.md` of
[`urbforge/redemptor`](https://github.com/urbforge/redemptor/blob/main/docs/development.md)
(formerly `product-management`). **Read it before starting any work**: it
is the source of truth and wins over anything in this file. With the
repositories cloned side by side it is `../redemptor/docs/development.md`
(`../product-management/...` in older clones); otherwise:

```sh
gh api repos/urbforge/redemptor/contents/docs/development.md -H "Accept: application/vnd.github.raw"
```

What it means for an agent, in practice:

- Work from an issue, in the repository where the work happens; check it
  is assigned and in the *Product Team* project before starting. Propose
  new issues to the person you work with rather than filing them unasked.
- Branch from an up-to-date `main` as `<type>/<short-description>`; commit
  messages and PR titles follow Conventional Commits.
- Write everything that lands on GitHub or in the repositories in
  English.
- Open the PR as a **draft**, with `Fixes urbforge/<repo>#<n>`, and this
  description:
  - `## Summary` - what changes, file by file when that helps;
  - `## Why` - the problem, or the ADR it implements;
  - `## Tests I ran` - what you ran and what it showed, including runs
    against a real Proxmox node; say what you did not run;
  - `## Checklist before review` - the guidelines' checklist, ticked only
    where true;
  - `Depends on ...` for a companion PR in another repository.
- Don't mark a PR ready, request reviews, merge, or push to `main` unless
  the person you work with asks.
- Never commit secrets, tokens, keys or private addresses; credentials
  live in `~/.urbex/credentials.yaml`.

## This repository

- **ADRs** are `docs/decisions/NNNN-short-title.md`, numbered with the
  next free number, with the sections *Status*, *Context*, *Decision*,
  *Rationale* (or *Out of scope*) and *Consequences*. A decision that
  changes an earlier one updates the earlier ADR's *Status* to point to
  it. An ADR is agreed in its own PR before, or together with, the code
  that implements it.
- When behaviour changes, keep in step: `docs/status.md`,
  `docs/known-limitations.md`, `docs/roadmap.md`, the reference
  (`docs/reference/`), and the cookbook or getting started where they
  show it.
- Every service follows the conventions of
  [ADR-0027](docs/decisions/0027-service-conventions.md); a change that
  adds or changes one documents its kind, internal name and exposure
  (the table *Every current service* there, and the reference), matching
  its entry in `urbex-cli`'s service catalog.
- `schemas/urbex.schema.json` is the source of truth for the manifest;
  `urbex-cli` keeps a copy that must match it.
- Write for the reader who runs the commands: real commands and output,
  no secrets or private addresses (use `example.com`). Check that
  relative links and anchors resolve.
