# ofxGgmlSam

`ofxGgmlSam` is the companion addon for SAM/SAM2/SAM3 segmentation workflows on
top of `ofxGgmlCore`.

This addon should hold the domain-specific pieces that do not belong in core:

- SAM model integration
- image preprocessing and mask postprocessing
- prompt helpers for points, boxes, and masks
- segmentation examples and UI
- sample image workflows

`ofxGgmlCore` remains the dependency. This addon must not be required by
`ofxGgmlCore`.

Current addon API version: `1.0.1`.

Family map: https://jonathhhan.github.io/ofxGgmlCore/

The first public API is a small bridge backend:

- `ofxGgmlSamInference`
- `ofxGgmlSamBackend`
- `ofxGgmlSamBridgeBackend`
- `ofxGgmlSamRequest` and `ofxGgmlSamResult`
- normalized point and request validation helpers

Concrete SAM/SAM2/SAM3 adapters should plug into that bridge instead of
expanding core `ofxGgmlCore`.

## Status

Initial skeleton. The first useful milestone is a focused point-prompt example
that loads a user-provided image and model path, then previews returned masks.

## Dependencies

- openFrameworks
- `ofxGgmlCore`
- `ofxImGui` for examples

## Validate

From the addon root:

```powershell
scripts\test-addon.bat
scripts\validate-local.bat
```

On macOS/Linux:

```sh
./scripts/test-addon.sh
./scripts/validate-local.sh
```

## Planned First Example

`ofxGgmlSamPointExample`

- choose model path
- choose image path
- place one positive point
- run segmentation
- preview mask overlay
- report clear missing-model or missing-backend states

Dry-run the current skeleton launcher:

```powershell
scripts\run-point-example.bat -DryRun
```

## Boundary

Keep generic runtime, tensor, model metadata, result types, and backend setup in
`ofxGgmlCore`. Move only stable, domain-neutral primitives down into `ofxGgmlCore` after
they have focused tests and no SAM-specific dependency.
