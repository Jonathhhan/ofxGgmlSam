# Architecture

`ofxGgmlSam` owns SAM-specific workflow code. It should use `ofxGgmlCore` for the
stable local inference foundation and keep segmentation UX out of the core
addon.

## Layers

| Layer | Scope |
| --- | --- |
| Public types | image, point, mask, request, result |
| Bridge layer | `ofxGgmlSamInference` and replaceable backends |
| Adapter layer | `ofxGgmlSamExternalBackend`, mock contract adapter, and future SAM/SAM2/SAM3 model-specific runtime integration |
| Example layer | openFrameworks UI, image loading, mask preview |

## Dependency Direction

```text
openFrameworks app
  -> ofxGgmlSam
      -> ofxGgmlCore
```

No dependency should point from `ofxGgmlCore` back to `ofxGgmlSam`.

## External Adapter Contract

The external adapter contract is intentionally file based:

```text
sam-runner --model model.gguf --image input.ppm --output mask.pgm --point-x 0.5 --point-y 0.5 --point-label positive
```

Additional points are represented by repeating `--point-x`, `--point-y`, and
`--point-label` in the same order. Coordinates are normalized image coordinates
in `[0, 1]`; labels are `positive` or `negative`.

`ofxGgmlSamExternalBackend` writes `input.ppm`, runs the configured executable,
then reads `mask.pgm`. The committed `tools/ofxGgmlSamMockAdapter` implements
this minimum contract with a synthetic mask so examples and validation can test
positive and negative point prompts before a real SAM runtime is selected.

See `docs/SAM_WORKFLOWS.md` before expanding this lane. It defines the planning
handoff, generated-mask boundaries, prompt-type split, external adapter
expectations, and validation ladder for SAM, SAM2, and SAM3 segmentation work.
