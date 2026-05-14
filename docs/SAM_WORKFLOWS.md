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
Model or external adapter:
Generated local artifacts:
Mask output:
Out of scope:
Validation:
```

Runtime changes should name whether the path changes point prompts, box
prompts, mask refinement, external adapter execution, image preprocessing, mask
postprocessing, or example UI.

## Validation ladder

Use the smallest command that proves the changed layer:

| Change type | Suggested validation |
| --- | --- |
| Docs or planning only | `scripts\validate-local.bat` |
| Local setup diagnosis | `scripts\doctor-sam.bat` |
| Point example launch path | `scripts\run-point-example.bat -DryRun` |
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
