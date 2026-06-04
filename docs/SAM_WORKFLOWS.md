# SAM Workflow Boundaries

`ofxGgmlSam` owns SAM, SAM2, and SAM3 segmentation workflows for the ofxGgml
ecosystem. This document is for Codex, GitHub Copilot, Hermes Agent, and human
contributors planning segmentation-lane work before changing runtime behavior.

This guide follows the split rule from the legacy/reference `ofxGgml` docs:
model-specific preprocessing, prompt UX, generated masks, sample image
workflows, and heavy optional runtimes belong in companion addons. Shared code
should move down only when it is stable, domain-neutral, dependency-light, and
covered by focused tests.

## Owned workflow surface

This addon may define:

- SAM/SAM2/SAM3 request/result shapes
- point, box, and mask prompt planning
- normalized image coordinate helpers
- image preprocessing and mask postprocessing rules
- external SAM runner contracts and mock adapter validation
- segmentation examples and mask overlay handoff paths
- sample image workflow docs when redistributable fixtures are chosen

## Not owned here

Keep these responsibilities out of `ofxGgmlSam`:

- ggml setup, backend selection, and runtime discovery owned by `ofxGgmlCore`
- generic image understanding, CLIP, captions, or VLM workflows owned by
  `ofxGgmlVision`
- image generation, inpainting, or diffusion-owned media synthesis
- committed SAM model files, generated masks, generated sample media, native
  build trees, or generated openFrameworks project files
- reusable GitHub Actions policy owned by `ofxGgmlWorkflows`

## Planning handoff

Before changing segmentation behavior, write down:

```text
Workflow:
Prompt type:
Input image:
Model or backend:
Generated local artifacts:
Mask output:
Out of scope:
Validation:
```

Runtime changes should name whether the path changes point prompts, box
prompts, mask refinement, backend execution, image preprocessing, mask
postprocessing, or example UI.

## Backend modes

The point example is focused on the in-process `sam3.cpp` and `sam.cpp` lanes.
The doctor script also recognizes the external adapter contract mode:

| Backend | Setup expectation |
| --- | --- |
| `external-sam` | Set `OFXGGML_SAM_EXECUTABLE` for doctor and external contract validation. This is not the point example's default UI path. |
| `sam.cpp` | Run `scripts\install-sam-cpp.bat` to stage the pinned source. The point example recognizes this lane and filters for `.bin` SAM models, but the in-process adapter is not auto-enabled because the pinned runtime still needs a Core ggml allocator port before it can be compiled safely beside the shared ggml lane. |
| `sam3.cpp` | Run `scripts\install-sam3-cpp.bat`, then `scripts\build-sam3-cpp.bat -CpuOnly` or `-Cuda`, define `OFXGGML_ENABLE_SAM3_ADAPTER`, and link the local runtime from `libs\sam3.cpp\include`, `libs\sam3.cpp\src`, and `libs\sam3.cpp\lib`. CUDA builds prefer the sibling Core ggml checkout and apply the local `ggml-cuda` window-op compatibility patch when needed. |

Set `OFXGGML_SAM_BACKEND` to one of those names to preselect the example or
doctor backend. The point example also searches `bin\data\models` for a model
when `OFXGGML_SAM_MODEL` is not set.

The public request type supports normalized point and box prompts. External
runner contracts forward box prompts with repeated `--box-x0`, `--box-y0`,
`--box-x1`, `--box-y1`, and `--box-label` flags. Box coordinates are normalized
image corners and must have positive area. The in-process `sam3.cpp` PVS path
supports points plus one positive box prompt per request and can be checked with
`scripts\run-sam3-runtime-smoke.bat -Backend cpu -Json -SummaryOnly -BoxVerify`.
The point example exposes point mode plus a `sam3.cpp` positive box mode. The
`sam.cpp` path remains point-prompt-first until its runtime-specific box path is
explicitly wired and validated.

Mask refinement is available through the external runner contract. If
`ofxGgmlSamRequest::refinementMask` is allocated, the external backend writes a
temporary PGM and forwards it with `--mask-input`. The mask must match the input
image dimensions. In-process refinement masks stay disabled until the relevant
runtime headers expose a stable public mask-input field.

For multi-image or multi-prompt callers, `ofxGgmlSamInference::segmentBatch`
is the first addon-level batch boundary. It preserves request/result order and
uses the same per-request validation path as `segment`; backend-specific
parallelism or embedding reuse should remain an adapter decision.
`tools\ofxGgmlSamBatchExternal` is the first file/directory workflow on top of
that boundary. It accepts repeated `.ppm`/`.pnm` inputs or an input directory,
uses the external adapter contract, and writes local PGM masks outside the repo
tree by default through `scripts\test-external-batch.bat`.

The `sam3.cpp` in-process adapter caches encoded image state by image
fingerprint inside the loaded runtime. The first run on a changed image performs
`sam3_encode_image`; repeated point prompts on the same image should only call
`sam3_segment_pvs`.

Model auto-detection is backend-aware: `sam3.cpp` selects `.ggml` models, while
`sam.cpp` selects `.bin` models. A SAM3 `.ggml` model is intentionally not sent
to the `sam.cpp` lane.

The lane-owned SAM3 runtime smoke is the first model-backed check that does not
depend on the openFrameworks example UI. It builds a small console tool, creates
a synthetic RGB image, loads a local SAM3/SAM2/EdgeTAM `.ggml` model, runs
`sam3_encode_image`, then runs one `sam3_segment_pvs` prompt. It reports timing,
mask-count, and first-mask shape statistics; masks and generated media stay
local.

Use `scripts\write-sam3-runtime-evidence.bat` to convert a captured smoke JSON
file into the neutral Evidence Schema v1 wrapper consumed by
`ofxGgmlWorkflows`. Keep SAM-specific metrics nested in the wrapper so Core can
read generic fields without taking a SAM dependency:

The smoke can also use a redistributable fixture image instead of the synthetic
input. The first committed fixture is `tests\fixtures\sam-point-square.ppm`, a
tiny hand-authored RGB PPM image with no model weights, generated masks, or user
media. Regenerate and compare the fixture source with
`scripts\generate-sam-fixtures.bat -Clean -Verify`. Use it when a deterministic
input path is needed:

```powershell
scripts\run-sam3-runtime-smoke.bat -Backend cpu -Json -SummaryOnly -OutputPath .sam3-runtime-smoke.json
scripts\write-sam3-runtime-evidence.bat -SmokePath .sam3-runtime-smoke.json -OutputPath build\evidence\sam3-runtime-evidence.json
```

```powershell
scripts\run-sam3-runtime-smoke.bat -DryRun -Image tests\fixtures\sam-point-square.ppm
```

When a local model/runtime is available, `-FixtureVerify` upgrades that fixture
run into an output check. It does not compare against a committed generated
mask; it checks invariants from the returned first-mask statistics so model
families can vary while still catching empty, saturated, or prompt-missing
outputs:

```powershell
scripts\run-sam3-runtime-smoke.bat -Backend cpu -Image tests\fixtures\sam-point-square.ppm -Json -SummaryOnly -FixtureVerify
```

## Validation ladder

Use the smallest command that proves the changed layer:

| Change type | Suggested validation |
| --- | --- |
| Docs or planning only | `scripts\validate-local.bat` |
| Fixture source changes | `scripts\generate-sam-fixtures.bat -Clean -Verify` |
| Local setup diagnosis | `scripts\doctor-sam.bat` |
| Backend-specific diagnosis | `scripts\doctor-sam.bat -Backend sam3.cpp` |
| SAM3 runtime smoke planning | `scripts\run-sam3-runtime-smoke.bat -DryRun` |
| SAM3 fixture smoke planning | `scripts\run-sam3-runtime-smoke.bat -DryRun -Image tests\fixtures\sam-point-square.ppm` |
| SAM3 evidence wrapper | `scripts\write-sam3-runtime-evidence.bat -SmokePath .sam3-runtime-smoke.json -OutputPath build\evidence\sam3-runtime-evidence.json` |
| SAM3 CPU runtime inference | `scripts\run-sam3-runtime-smoke.bat -Backend cpu -Json -SummaryOnly` |
| SAM3 CPU box-prompt inference | `scripts\run-sam3-runtime-smoke.bat -Backend cpu -Json -SummaryOnly -BoxVerify` |
| SAM3 fixture output check | `scripts\run-sam3-runtime-smoke.bat -Backend cpu -Image tests\fixtures\sam-point-square.ppm -Json -SummaryOnly -FixtureVerify` |
| SAM3 CUDA runtime inference | `scripts\run-sam3-runtime-smoke.bat -Backend cuda -Json -SummaryOnly` |
| Point example launch path | `scripts\run-point-example.bat -DryRun` |
| Generated VS addon wiring | `scripts\repair-point-example-vsproj.bat` |
| External adapter contract | `scripts\test-external-adapter-contract.bat -Clean` |
| External batch workflow | `scripts\test-external-batch.bat -Clean` |
| Request/result/helper changes | `scripts\test-addon.bat` |

## Safe first tasks

Good early SAM-lane tasks are:

- documenting adapter CLI expectations
- adding deterministic image or mask fixtures when licensing is clear
- improving prompt boundary docs for points, boxes, and masks
- extending batch workflows while keeping generated masks out of git
- clarifying which image-understanding work belongs in `ofxGgmlVision`
- keeping example UI narrow and focused on one segmentation workflow

Avoid broadening runtime behavior until input images, model or adapter
expectations, generated masks, and validation commands are explicit.
