# Roadmap

## First Milestone

Done:

- public request/result types
- normalized point and request validation helpers
- bridge inference backend for future SAM adapters
- external SAM adapter boundary for local SAM/SAM2/SAM3 runner executables
- headless bridge API tests
- root-level point example skeleton
- independent addon version metadata

Next:

Build a focused root-level `ofxGgmlSamPointExample` on top of the external
adapter boundary:

- model path input
- image path input
- one positive point prompt
- mask overlay preview
- useful missing-model and missing-runtime states

## Rules

- `ofxGgmlSam` depends on `ofxGgmlCore`.
- `ofxGgmlCore` must not depend on `ofxGgmlSam`.
- Keep the first example narrow; do not recreate the old all-in-one GUI.
- Do not commit model binaries or generated native build outputs.
- Move code down into `ofxGgmlCore` only when it is domain-neutral and tested.
- Keep `scripts\validate-local.*` passing.

## Later

- box prompts
- multiple points
- mask refinement
- batch image workflows
- optional SAM2/SAM3-specific adapters
- sample image generation or redistributable test image
