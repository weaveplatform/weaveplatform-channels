# weaveplatform-channels

The signed channel manifests for the Weave platform, and the public half of the
keys that sign them. Data, not code: nothing here is imported by anything, and
the only workflow opens promotion PRs.

Core trusts nothing it fetches until it verifies against the chain rooted here.

```mermaid
flowchart LR
    root["root key<br/>(offline; pub embedded in core)"] -->|endorses| signing["signing key<br/>(annual, in CI)"]
    signing -->|signs| ch["channel manifest<br/>stable / pinned"]
    ch -->|"fetched + chain-verified"| core["core on every device"]
    style root fill:#8957e5,color:#fff
```

## Layout

| Path | What |
|---|---|
| `channels/stable.json` (+ `.sig`) | The rolling channel: updated and re-signed by the promotion PR for every published module. SaaS agents follow it |
| `channels/pinned/<service-version>.json` | Immutable snapshots for self-hosted deployments; created once, never touched again, never automated |
| `keys/root.pub` | The offline root public key. The copy core trusts is embedded in the agent binary (`internal/core/keys/root.pub`); this one is for operators verifying by hand |
| `keys/signing-<year>.pub` (+ `.sig`) | Annual signing keys, endorsed by the root |
| `.github/workflows/promote.yml` | The receiver for `module-published` dispatches from the module release pipeline |

## How a module reaches the channel

The platform repository's reusable
[`module-release.yml`](https://github.com/weaveplatform/weaveplatform-agent-core/blob/main/.github/workflows/module-release.yml)
builds a module for every platform in its manifest, pushes the binaries to GHCR
with a digest-stamped sidecar, and dispatches `module-published` here with the
id and version. `promote.yml` pulls that sidecar, rewrites the module's entry in
`channels/stable.json`, bumps the sequence, signs when a signing key is
provisioned, and opens a PR. **Merging is the promotion act.**

## The tool

`weavemanifest` (`keygen | endorse | sign | verify`) ships with the agent
release — its `verify` *is* core's verifier, so a manifest it accepts is one
core accepts. This repository carries no copy.

```console
weavemanifest keygen root root                   # once, offline; root.key goes in the drawer
weavemanifest keygen signing-2026 signing-2026   # yearly
weavemanifest endorse root.key signing-2026.pub  # -> signing-2026.pub.sig
weavemanifest sign signing-2026.key channels/stable.json   # -> channels/stable.json.sig
weavemanifest verify keys/root.pub keys/signing-2026.pub channels/stable.json
```

## Trust model

Two-tier, detached Ed25519 signatures in small JSON envelopes beside each file
(`<name>.sig`). An offline root endorses annual signing keys; signing keys sign
channel manifests. Verification needs no infrastructure — an air-gapped
self-hosted deployment verifies with the root key baked into its core. Rolling
vs pinned is the same schema and the same verifier with a different mutation
policy. [`docs/trust-chain.md`](docs/trust-chain.md) has the full chain and what
each step defends against.

The document schema is
[`schema/channel-manifest.schema.json`](https://github.com/weaveplatform/weaveplatform-agent-core/blob/main/schema/channel-manifest.schema.json)
in the platform repository; the Go types are `sdk/manifest`; the verifier is
`internal/manifestverify`.

## Still to decide

Core fetches the channel bundle over HTTP (`--manifest-url`), and this
repository is private. Something has to *serve* `channels/` — make this
repository public (it holds only public keys and signed documents), publish to
GitHub Pages, or push the bundle to GHCR beside the modules. The same decision
covers the module binaries themselves, which today live only in the OCI store.
