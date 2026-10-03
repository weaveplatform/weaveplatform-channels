# Contributing

This repository holds data, not code: the signed channel manifests and the
public keys that verify them. Most changes arrive through automation; the
rules below are what keep a hand-made change from breaking every device that
follows the channel.

## How promotion works

1. A release pipeline (agent-core's `module-release.yml` for modules,
   weaveplatform-oci's publish workflow for guest images) dispatches
   `module-published` or `image-published` here.
2. [`promote.yml`](.github/workflows/promote.yml) validates the payload,
   re-resolves it from the registry, and adds it to `channels/stable.json` on
   the branch `promote/stable`, bumping `sequence` and re-signing when a
   signing key is provisioned. Concurrent dispatches all land on that one
   branch; a run that loses a push race retries on the new tip.
3. One PR, `chore(promote): promote to stable`, carries every pending item,
   one line each.
4. **Merging that PR is the promotion act.** Nothing reaches a device before
   it is merged; review it as a release.

A manual promotion is the same workflow run with `workflow_dispatch`.

## Rules the quality gate enforces

- Every channel document validates against agent-core's
  `schema/channel-manifest.schema.json` at the release pinned in
  `.github/agent-core-version`, and against core's ParseChannel rules. Every
  module's `protocol` must sit inside the channel's `protocol` window: core would
  accept the document and then refuse to run that module on every device.
- A `.sig` must verify with `weavemanifest verify` under `keys/root.pub`.
  An unsigned document is reported, not failed, until a signing key is
  provisioned.
- `channels/stable.json`'s `sequence` never goes down, and goes up whenever
  the document changes: core refuses a lower sequence than it has seen.
- `channels/pinned/` is add-only. A pinned snapshot is referenced by URL and
  digest from deployed configuration; once merged it is never modified,
  renamed or deleted. A new service version gets a new file.

Run the same checks locally from the repository root:

```console
scripts/check-channels.sh parse
scripts/check-channels.sh history origin/main
scripts/fetch-weavemanifest.sh darwin_arm64 /tmp/wm && scripts/check-channels.sh signatures /tmp/wm/weavemanifest
```

## Pull requests

- Titles follow [Conventional Commits](https://www.conventionalcommits.org/)
  (`feat:`, `fix:`, `docs:`, `chore:`, `ci:`, …); `pr-title-validation.yml`
  enforces it.
- Actions are pinned by commit SHA with the version in a comment, and every
  job starts with `step-security/harden-runner`. Dependabot keeps the pins
  current and `auto-merge.yml` merges its PRs once the gate passes.
- The `Quality gate` check is the one required status.

## Issues

File bugs and requests in the
[GitHub issues](https://github.com/weaveplatform/weaveplatform-release-channels/issues)
page using the templates. Report security issues as described in
[SECURITY.md](SECURITY.md), not in a public issue.
