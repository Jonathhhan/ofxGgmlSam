# ofxGgmlSamPointExample

Focused point-prompt segmentation example for `ofxGgmlSam`.

Flow:

- choose a SAM model path
- choose an image path
- switch between `sam3.cpp` and `sam.cpp`
- place one positive point
- run segmentation
- preview mask overlay

The default backend is `sam3.cpp`. If no `OFXGGML_SAM_MODEL` is set, the
example searches `bin\data\models` for a compatible local model such as
`sam3-q8_0.ggml`.

Model discovery is backend-aware. `sam3.cpp` uses `.ggml` models; `sam.cpp`
uses classic `.bin` SAM models and is currently a planned in-process port lane,
not part of the repaired Visual Studio build.

For `sam3.cpp`, the first run on a newly loaded image encodes the image and
caches that state inside the loaded runtime. Later point changes on the same
image reuse the cached image state and only run `sam3_segment_pvs`, which keeps
interactive point refinement fast.

This example should stay narrow. It is not the place for a full segmentation
workbench.
