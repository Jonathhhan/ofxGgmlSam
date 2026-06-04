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

## Features

- SAM/SAM2/SAM3 model discovery
- point-prompt segmentation
- mask generation and preview workflow
- CPU/CUDA/Metal runtime selection
- model-backed runtime smoke evidence
- mock-backed external batch workflow for local PPM image sets

The first public API is a small bridge backend:

- `ofxGgmlSamInference`
- `ofxGgmlSamBackend`
- `ofxGgmlSamBridgeBackend`
- `ofxGgmlSamExternalBackend`
- optional `ofxGgmlSamCppAdapters` and `ofxGgmlSam3Adapters`
- `ofxGgmlSamRequest` and `ofxGgmlSamResult`
- `segment`, `segmentPoint`, `segmentBox`, and sequential `segmentBatch`
- normalized point, box, and request validation helpers

Concrete SAM/SAM2/SAM3 adapters should plug into that bridge instead of
expanding core `ofxGgmlCore`.

`segmentBatch` preserves input order and runs each request through the same
validation and backend path as `segment`. It is intentionally sequential so
backend-specific batching, threading, or embedding reuse can be added later
without changing the first addon-level contract.

For segmentation-lane planning, prompt boundaries, and adapter artifact rules,
see [docs/SAM_WORKFLOWS.md](docs/SAM_WORKFLOWS.md).

`ofxGgmlSamExternalBackend` is the first concrete adapter boundary. It writes
the request image to a temporary PPM file, calls a user-provided local SAM
executable with model/image/point/output flags, and reads a returned PGM mask
into `ofxGgmlSamResult`. That keeps SAM, SAM2, and SAM3 runners opt-in while
making the addon-side contract explicit and testable.

The in-process `sam.cpp` and `sam3.cpp` adapter headers are also available for
local runtime experiments. They are disabled unless the consuming project
defines `OFXGGML_ENABLE_SAMCPP_ADAPTER` or `OFXGGML_ENABLE_SAM3_ADAPTER`,
adds the matching runtime headers to the include path, and links the matching
runtime libraries. When those headers are not available, the adapters still
compile and report a clear disabled-backend result.

The default `addon_config.mk` only lists `ofxGgmlSam` sources and does not use
source exclusions. Optional runtime packages use the same addon-library shape as
`libs/ofxTimecode`: `libs/sam.cpp/include`, `libs/sam.cpp/src`,
`libs/sam3.cpp/include`, and `libs/sam3.cpp/src`. The raw upstream git
checkout lives under each package's ignored `source` folder. Projects that
enable an in-process adapter should add the matching runtime include, source,
and library paths explicitly after local setup.

Fetch optional local runtime sources with:

```powershell
scripts\install-sam-cpp.bat
scripts\install-sam3-cpp.bat
scripts\build-sam3-cpp.bat -CpuOnly
```

Use `scripts\build-sam3-cpp.bat -Cuda` when CUDA Toolkit and Visual Studio CUDA
integration are installed. CUDA builds use the sibling
`ofxGgmlCore\libs\ggml\.source` checkout when it is available, and the build
script applies `patches\ggml-cuda-win-part-unpart.patch` if that ggml checkout
does not already expose SAM3's CUDA window partition ops. Override
`OFXGGML_SAM_CPP_DIR` or
`OFXGGML_SAM3_CPP_DIR` only when you want the raw upstream checkout somewhere
outside `libs/sam.cpp/source` or `libs/sam3.cpp/source`.

The `sam3.cpp` adapter caches encoded image state per loaded runtime. Changing
only point or box prompts reuses the cached image embedding and runs the prompt
decoder directly; changing the image invalidates the cache and triggers a fresh
encode. The in-process `sam3.cpp` PVS path supports points plus one positive
box prompt per request. The `sam.cpp` in-process path remains point-prompt-only;
use the external adapter for box prompts in that lane.

List local SAM model candidates before running the example or runtime smoke:

```powershell
scripts\list-models.bat -Json -SummaryOnly
```

The discovery script checks `OFXGGML_SAM_MODEL`, the point example's
`bin\data` model folders, the addon's local `models` folder, and the shared
addons-level `models` folder. It reports `.ggml` and `.gguf` SAM/SAM2/SAM3 or
EdgeTAM candidates, and marks the `.ggml` SAM3/SAM2/EdgeTAM file that the
runtime smoke can use automatically.

Verify the in-process SAM3 lane with the headless runtime smoke. The dry-run is
model-free and reports the selected executable, backend, and model discovery
state:

```powershell
scripts\run-sam3-runtime-smoke.bat -DryRun
```

When `OFXGGML_SAM_MODEL` is set, or a `.ggml` SAM3/SAM2/EdgeTAM model exists in
`ofxGgmlSamPointExample\bin\data\models`, the smoke builds a small console tool,
loads the model, encodes a synthetic RGB image, runs one point prompt, and
reports timings and first-mask shape statistics without writing masks or
generated media:

```powershell
scripts\run-sam3-runtime-smoke.bat -Backend cpu -Json -SummaryOnly
scripts\run-sam3-runtime-smoke.bat -Backend cuda -Json -SummaryOnly
```

Write a neutral Evidence Schema v1 wrapper from a captured smoke run with:

```powershell
scripts\run-sam3-runtime-smoke.bat -Backend cpu -Json -SummaryOnly -OutputPath .sam3-runtime-smoke.json
scripts\write-sam3-runtime-evidence.bat -SmokePath .sam3-runtime-smoke.json -OutputPath build\evidence\sam3-runtime-evidence.json
```

The wrapper keeps SAM-specific timing and mask summary fields nested while exposing the required reusable workflow fields such as `schema_version`, `commit_sha`, `backend`, `result`, and `artifact_path`.

Verify the SAM3 in-process box prompt path with:

```powershell
scripts\run-sam3-runtime-smoke.bat -Backend cpu -Json -SummaryOnly -BoxVerify
```

For deterministic fixture planning, pass the committed hand-authored PPM image:

```powershell
scripts\run-sam3-runtime-smoke.bat -DryRun -Image tests\fixtures\sam-point-square.ppm
```

Regenerate and verify the redistributable fixture source with:

```powershell
scripts\generate-sam-fixtures.bat -Clean -Verify
```

To turn that fixture into a model-backed output check, add `-FixtureVerify`.
The check uses the returned first-mask statistics to require a valid,
non-empty, non-saturated mask that covers the positive prompt/fixture center:

```powershell
scripts\run-sam3-runtime-smoke.bat -Backend cpu -Image tests\fixtures\sam-point-square.ppm -Json -SummaryOnly -FixtureVerify
```

Verify that contract without a real model by building the mock adapter:

```powershell
scripts\test-external-adapter-contract.bat
```

The mock executable accepts the same flags as the external backend and writes a
synthetic PGM mask. Real SAM runners should implement the same minimum CLI for
point prompts:

```text
sam-runner --model model.gguf --image input.ppm --output mask.pgm --point-x 0.5 --point-y 0.5 --point-label positive
```

Multiple point prompts are passed by repeating the three point flags in order:

```text
sam-runner --image input.ppm --output mask.pgm --point-x 0.5 --point-y 0.5 --point-label positive --point-x 0.0 --point-y 0.0 --point-label negative
```

Coordinates are normalized image coordinates in `[0, 1]`. The adapter must
write one grayscale PGM mask with the same width and height as the input image.
Box prompts use normalized corner coordinates and are passed by repeating the
five box flags in order:

```text
sam-runner --image input.ppm --output mask.pgm --box-x0 0.25 --box-y0 0.25 --box-x1 0.75 --box-y1 0.75 --box-label positive
```

Point and box prompts may be combined. Box coordinates must describe a
positive-area rectangle with `x0 < x1` and `y0 < y1`.
Mask refinement is supported at the external adapter boundary. When
`ofxGgmlSamRequest::refinementMask` is allocated, the backend writes it as a
temporary PGM and passes it with `--mask-input`:

```text
sam-runner --image input.ppm --mask-input prior-mask.pgm --output mask.pgm --point-x 0.5 --point-y 0.5 --point-label positive
```

The refinement mask must match the request image dimensions. In-process
`sam.cpp` and `sam3.cpp` refinement-mask wiring is intentionally left disabled
until their public runtime APIs expose a stable mask-input contract.

For file-list or directory batch smoke testing, use:

```powershell
scripts\test-external-batch.bat
```

That script builds `tools\ofxGgmlSamBatchExternal`, builds the mock external
adapter, copies the redistributable PPM fixture into a temporary input
directory, runs `segmentBatch`, and verifies that ordered output masks were
written. The batch tool accepts repeated `--input` paths or one `--input-dir`
of `.ppm`/`.pnm` files, plus `--adapter`, `--output-dir`, point flags, optional
box flags, and `--json`.

## Status

The point-prompt example now loads a user-provided image, lets the user place a
positive point, runs the selected in-process SAM backend, and previews returned
masks as an overlay. It defaults to `sam3.cpp`, can switch to `sam.cpp`, and
auto-detects compatible model files from `bin\data\models` before requiring
`OFXGGML_SAM_MODEL`.

## Dependencies

- openFrameworks
- `ofxGgmlCore`
- `ofxImGui` for examples

## Validate

From the addon root:

```powershell
scripts\doctor-sam.bat
scripts\list-models.bat -Json -SummaryOnly
scripts\run-sam3-runtime-smoke.bat -DryRun
scripts\write-sam3-runtime-evidence.bat -SmokePath .sam3-runtime-smoke.json -OutputPath build\evidence\sam3-runtime-evidence.json
scripts\test-addon.bat
scripts\validate-local.bat
```

On macOS/Linux:

```sh
./scripts/doctor-sam.sh
./scripts/list-models.sh -Json -SummaryOnly
./scripts/test-addon.sh
./scripts/validate-local.sh
```

## Point Example

`ofxGgmlSamPointExample`

- choose model path
- choose image path
- switch between `sam3.cpp` and `sam.cpp`
- place one positive point
- switch to a positive box prompt for `sam3.cpp`
- run segmentation
- preview mask overlay
- report clear missing-model or missing-backend states

Dry-run the launcher:

```powershell
scripts\run-point-example.bat -DryRun
```

At runtime, the example also reads optional defaults from:

- `OFXGGML_SAM_MODEL`
- `OFXGGML_SAM_IMAGE`
- `OFXGGML_SAM_BACKEND` (`sam3.cpp` or `sam.cpp`)

The default model search includes `ofxGgmlSamPointExample\bin\data\models`.

## Boundary

Keep generic runtime, tensor, model metadata, result types, and backend setup in
`ofxGgmlCore`. Move only stable, domain-neutral primitives down into `ofxGgmlCore` after
they have focused tests and no SAM-specific dependency.
