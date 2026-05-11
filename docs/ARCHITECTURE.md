# Architecture

`ofxGgmlSam` owns SAM-specific workflow code. It should use `ofxGgmlCore` for the
stable local inference foundation and keep segmentation UX out of the core
addon.

## Layers

| Layer | Scope |
| --- | --- |
| Public types | image, point, mask, request, result |
| Bridge layer | `ofxGgmlSamInference` and replaceable backends |
| Adapter layer | SAM/SAM2/SAM3 model-specific runtime integration |
| Example layer | openFrameworks UI, image loading, mask preview |

## Dependency Direction

```text
openFrameworks app
  -> ofxGgmlSam
      -> ofxGgmlCore
```

No dependency should point from `ofxGgmlCore` back to `ofxGgmlSam`.
