# Roadmap

## First Milestone

Done:

- public request/result types
- normalized point and request validation helpers
- bridge inference backend for future SAM adapters
- external SAM adapter boundary for local SAM/SAM2/SAM3 runner executables
- mock adapter and contract test for the external executable protocol
- repeated external point flags for multi-point positive/negative prompts
- headless bridge API tests
- root-level point example skeleton
- independent addon version metadata

Next:

Done:

- model path input
- image path input
- in-process backend switch for `sam3.cpp` and `sam.cpp`
- one positive point prompt
- mask overlay preview
- useful missing-model, missing-backend, and disabled-adapter states
- local SAM3 model auto-detection from example `bin\data\models`
- lane-owned SAM3 runtime smoke for load, encode, point segmentation, and timing

Next:

- add a redistributable fixture image workflow
- expand runtime verification from the SAM3 smoke to fixture-backed output checks

## Rules

- `ofxGgmlSam` depends on `ofxGgmlCore`.
- `ofxGgmlCore` must not depend on `ofxGgmlSam`.
- Keep the first example narrow; do not recreate the old all-in-one GUI.
- Do not commit model binaries or generated native build outputs.
- Move code down into `ofxGgmlCore` only when it is domain-neutral and tested.
- Keep `scripts\validate-local.*` passing.

## Later

- box prompts
- mask refinement
- batch image workflows
- broader SAM2/SAM3-specific adapter coverage
- sample image generation or redistributable test image
