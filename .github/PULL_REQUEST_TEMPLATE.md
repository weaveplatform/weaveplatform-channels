# Pull Request Description

## Summary
[Provide a brief description of the changes in this PR]

### Issue Reference
Fixes #[Issue Number]

### Motivation and Context
- Why is this change needed?
- What problem does it solve?

## Type of Change
Please mark the relevant option with an `x`:
- [ ] 📦 Channel change (`channels/stable.json` by hand, outside `promote.yml`)
- [ ] 📌 New pinned snapshot (`channels/pinned/<service-version>.json`)
- [ ] 🔑 Key change (new or rotated `keys/*.pub` and its endorsement)
- [ ] 🔧 Workflow or script change (`.github/`, `scripts/`)
- [ ] 📝 Documentation update

## Channel Checklist
- [ ] `channels/stable.json`'s `sequence` is higher than main's if the document changed
- [ ] No existing file under `channels/pinned/` is modified or deleted
- [ ] Every changed channel document is re-signed, or left unsigned on purpose (no stale `.sig`)
- [ ] `scripts/check-channels.sh parse` and the schema check pass locally

## Quality Checklist
- [ ] I have reviewed my own change before requesting review
- [ ] I have verified there are no other open Pull Requests for the same update/change
- [ ] The quality gate passes
- [ ] I have made corresponding changes to the README, CONTRIBUTING and `docs/` where behaviour changed

## Additional Notes
[Add any additional information that might be helpful for reviewers]
