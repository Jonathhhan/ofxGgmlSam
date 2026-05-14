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

The `sam3.cpp` in-process adapter caches encoded image state by image
fingerprint inside the loaded runtime. The first run on a changed image performs
`sam3_encode_image`; repeated point prompts on the same image should only call
`sam3_segment_pvs`.

Model auto-detection is backend-aware: `sam3.cpp` selects `.ggml` models, while
`sam.cpp` selects `.bin` models. A SAM3 `.ggml` model is intentionally not sent
to the `sam.cpp` lane.

## Validation ladder

Use the smallest command that proves the changed layer:

| Change type | Suggested validation |
| --- | --- |
| Docs or planning only | `scripts\validate-local.bat` |
| Local setup diagnosis | `scripts\doctor-sam.bat` |
| Backend-specific diagnosis | `scripts\doctor-sam.bat -Backend sam3.cpp` |
| Point example launch path | `scripts\run-point-example.bat -DryRun` |
| Generated VS addon wiring | `scripts\repair-point-example-vsproj.bat` |
| External adapter contract | `scripts\test-external-adapter-contract.bat -Clean` |
| Request/result/helper changes | `scripts\test-addon.bat` |

## Safe first tasks

Good early SAM-lane tasks are:

- documenting adapter CLI expectations
- adding deterministic image or mask fixtures when licensing is clear
- improving prompt boundary docs for points, boxes, and masks
- clarifying which image-understanding work belongs in `ofxGgmlVision`
- keeping example UI narrow and focused on one segmentation workflow

Avoid broadening runtime behavior until input images, model or adapter
expectations, generated masks, and validation commands are explicit.
