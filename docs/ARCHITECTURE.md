# Architecture

`ofxGgmlSam` owns SAM-specific workflow code. It should use `ofxGgmlCore` for the
stable local inference foundation and keep segmentation UX out of the core
addon.

## Layers

| Layer | Scope |
| --- | --- |
| Public types | image, point, mask, request, result |
| Bridge layer | `ofxGgmlSamInference` and replaceable backends |
| Adapter layer | `ofxGgmlSamExternalBackend`, optional `sam.cpp` / `sam3.cpp` adapter headers, and the mock contract adapter |
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

## In-Process Adapters

`ofxGgmlSamCppAdapters` and `ofxGgmlSam3Adapters` expose optional in-process
adapter hooks inspired by the legacy `ofxGgml` implementation. They compile as
disabled stubs unless the consuming project defines the matching adapter macro
and links the runtime:

```text
OFXGGML_ENABLE_SAMCPP_ADAPTER
OFXGGML_ENABLE_SAM3_ADAPTER
```

Local runtime packages live under `libs/sam.cpp` and `libs/sam3.cpp` using
the same `include` / `src` shape as small openFrameworks addon libraries such
as `libs/ofxTimecode`. The raw upstream git checkout is kept in each package's
ignored `source` folder, and local build products stay under ignored `lib` or
build directories. A project that enables an in-process adapter should add the
matching runtime include, source, and library paths explicitly.

SAM3 CUDA builds prefer the shared ggml checkout from
`ofxGgmlCore\libs\ggml\.source` so the adapter lane stays aligned with the
broader ecosystem runtime. `scripts\build-sam3-cpp.ps1` applies the local
`patches\ggml-cuda-win-part-unpart.patch` compatibility patch when the selected
ggml source does not yet implement `GGML_OP_WIN_PART` and
`GGML_OP_WIN_UNPART` on CUDA.

See `docs/SAM_WORKFLOWS.md` before expanding this lane. It defines the planning
handoff, generated-mask boundaries, prompt-type split, external adapter
expectations, and validation ladder for SAM, SAM2, and SAM3 segmentation work.
