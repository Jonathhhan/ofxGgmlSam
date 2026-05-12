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
- external SAM executable input
- one positive point prompt
- mask overlay preview
- useful missing-model and missing-runtime states

Next:

- add a generated sample image path or fixture image workflow
- choose the first real SAM/SAM2/SAM3 runner and document setup/download notes

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
- optional SAM2/SAM3-specific adapters
- sample image generation or redistributable test image
