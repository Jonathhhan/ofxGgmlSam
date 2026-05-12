# Release Policy

`ofxGgmlSam` releases are tagged independently from `ofxGgmlCore` and the other
companion addons.

## Tagging

Use per-addon semantic version tags:

```text
v1.0.0
v1.0.1
v1.1.0
```

Do not mirror tags across the whole addon family unless this addon changed and
passed its own release checklist.

## Compatibility

Document the minimum compatible `ofxGgmlCore` version in each release note.

For normal development:

- patch releases should not require Core API changes
- minor releases may require a newer Core minor version
- breaking API changes should use a major version bump

## Runtime Scope

SAM runtime integrations should be explicit about the backend they require.
Bridge API releases can ship before a full SAM/SAM2/SAM3 runtime adapter, but
the release notes must say that clearly.

## Pre-Release Gate

Before tagging:

1. Run `scripts\release-candidate.bat` on Windows.
2. Run `./scripts/release-candidate.sh` on macOS or Linux when available.
3. Complete `docs/RELEASE_CHECKLIST.md`.
4. Update `CHANGELOG.md`.
5. Confirm no generated artifacts, model binaries, or sample outputs are staged.
