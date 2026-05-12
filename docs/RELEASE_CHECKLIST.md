# Release Checklist

Use this before tagging or announcing an `ofxGgmlSam` release. The goal is to
prove the addon boundary and example layout without relying on generated local
state.

## Fresh Clone Layout

From the openFrameworks `addons` folder:

```powershell
git clone https://github.com/Jonathhhan/ofxGgmlCore.git
git clone https://github.com/Jonathhhan/ofxGgmlSam.git
cd ofxGgmlSam
```

Expected layout:

```text
addons/
  ofxGgmlCore/
  ofxGgmlSam/
  ofxImGui/
```

## Local Validation

Run the full local validation suite:

```powershell
scripts\validate-local.bat
```

macOS/Linux:

```sh
./scripts/validate-local.sh
```

This checks addon layout, dependency layout, root-level example placement,
generated artifact hygiene, launch helper dry-run output, and headless C++
tests.

For a pre-tag release candidate gate, run:

```powershell
scripts\release-candidate.bat
```

macOS/Linux:

```sh
./scripts/release-candidate.sh
```

## Example Scope

`ofxGgmlSamPointExample` is intentionally narrow in this release:

- root-level openFrameworks example
- `ofxImGui` dependency declared in `addons.make`
- point-prompt UI skeleton
- clear future path for image/model selection and mask preview

This release does not promise a complete SAM/SAM2/SAM3 runtime adapter yet.

## Before Tagging

- `git status --short --ignored` shows no unexpected generated outputs
- no model files, masks, images, generated OF project files, or build outputs
  are staged
- `CHANGELOG.md` has an entry for the release
- `docs/releases/vX.Y.Z.md` matches the release scope
- `docs/ROADMAP.md` still separates done work from future adapter work
- `README.md` does not overpromise runtime SAM inference
