# Roadmap

## First Milestone

Done:

- public request/result types
- bridge inference backend for future SAM adapters
- headless bridge API tests
- root-level point example skeleton

Next:

Build a focused root-level `ofxGgmlSamPointExample`:

- model path input
- image path input
- one positive point prompt
- mask overlay preview
- useful missing-model and missing-runtime states

## Rules

- `ofxGgmlSam` depends on `ofxGgml`.
- `ofxGgml` must not depend on `ofxGgmlSam`.
- Keep the first example narrow; do not recreate the old all-in-one GUI.
- Do not commit model binaries or generated native build outputs.
- Move code down into `ofxGgml` only when it is domain-neutral and tested.
- Keep `scripts\validate-local.*` passing.

## Later

- box prompts
- multiple points
- mask refinement
- batch image workflows
- optional SAM2/SAM3-specific adapters
- sample image generation or redistributable test image
