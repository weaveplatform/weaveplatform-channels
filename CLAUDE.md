# weaveplatform-channels — engineering conventions

This repo holds the signed channel manifests and the keys that sign them; the
tool that mints and verifies the chain lives in weaveplatform-agent-core. Comments about a security
decision — what is checked, what is deliberately not, and what an attacker would
gain from getting it wrong — are the ones worth the space here.

## Workflows and scripts

- `promote.yml` has no concurrency group on purpose (GitHub would cancel all
  but one pending run). Race safety lives in `scripts/promote.sh land`: apply
  on a fresh base, `--force-with-lease` push, retry. Keep the merge rules in
  that script only.
- Pushes and PRs use the org App token (`vars.RP_APP_ID`,
  `secrets.RP_APP_PRIVATE_KEY`), falling back to `RELEASE_PLEASE_PAT` with a
  warning. Never `GITHUB_TOKEN`: its pushes trigger no checks.
- `.github/agent-core-version` pins the schema and `weavemanifest` together;
  move it, don't vendor either.
- The `Quality gate` job is the one required check. `channels/pinned/` is
  add-only; `sequence` never goes down.
- Actions pinned by SHA with a version comment, `harden-runner` first in every
  job; `actionlint` and `shellcheck` must stay clean.

## Comments: what and why, sparse and deep

Comment the **reasoning a reader cannot recover from the code**. Delete anything
that restates it.

```go
// BAD — the signature already says this
// SetTime sets the time. t is the time to set.

// GOOD — says what the code cannot
// A step, not a slew: a guest resuming from a snapshot can be days out, and
// adjtime would take longer to converge than the guest is likely to run.
```

**Sparse, not uniform.** Most code carries no comment at all. Effort concentrates
at the few places where a decision was made and the alternative was plausible —
an ordering that must not be reversed, a fallback that must not fail open, a
number that must match something elsewhere. A file where every function has a
paragraph is not thorough, it is undifferentiated: the reader has no way to tell
the load-bearing note from the throat-clearing.

**Length is not the metric.** A comment earns its lines by carrying content, and
some genuinely need twenty. Never pad one to look thorough, and never cut one
that is doing real work to hit a length. If it took an afternoon to learn, write
it down in full.

What is worth the space:

- **Why this and not the obvious alternative.** "PDH means opening a query,
  adding counters by localised path string, and collecting twice before the
  first number appears — three FILETIME counters do it here."
- **What a failure would look like**, especially the silent ones. "A truncated
  count silently gives an available-memory reading of zero, which reads as a
  quiet guest rather than a broken call."
- **Orderings and invariants** whose violation is not a compile error. "The
  acknowledgement must be on the wire before the command that kills the OS."
- **What was deliberately NOT done**, when a reader would otherwise add it.
  "Sizes the ABI passes by reference stay skipped rather than being passed
  truncated for the callee to read as garbage."
- **Facts learned the hard way** — an API that reports success while doing
  nothing, a field the kernel validates strictly, a service that silently
  reverses your change.

What is not:

- Restating a name, signature, or the line below it.
- Narrating structure: `// loop over the items`, `// error handling`.
- Marking sections: `// --- helpers ---`.
- Changelog or attribution. That is what git is for.
- Apologising for code. Fix it, or write down why it stays.

**Exported identifiers** get the standard Go doc comment, starting with the
name, and usually one sentence. Add paragraphs below it only when the caller
needs the reasoning to use the thing correctly.

**Prefer one home for a rationale.** When the same "why" applies in several
places, write it once where the decision lives and point at it from the others,
rather than restating it in each.

## Documentation

Docs describe what the code does **now**. A feature that changes behaviour,
adds a wire operation, or moves a boundary is not finished until the docs that
describe that area say so — in the same change, not a follow-up.

- **README** is the entry point: what this repo is, what it is for, how to build
  and test it. Not a feature list.
- **`docs/`** covers the things a reader cannot get from the code: architecture,
  protocols and their compatibility rules, trust chains, release pipelines.
- **Handoff documents** (work another person or machine must finish) state what
  to run, what a pass looks like, and **what each failure would mean** — the
  last one matters most where a call can fail by returning a plausible zero.
- Say plainly what is unverified. "Compiles but has never run on Windows" is
  more useful than silence, and far more useful than implied confidence.
