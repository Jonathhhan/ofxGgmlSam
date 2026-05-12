# AGENTS.md

This repository is `ofxGgmlSam`, the segmentation companion addon for the ofxGgml family.

Codex should treat `ofxGgmlCore` as the backend-neutral foundation. This repo owns SAM/SAM2/SAM3 segmentation workflows, point prompts, segmentation examples, and segmentation-specific runtime integration.

## Addon contract

Do:

- keep segmentation-specific workflows in this addon
- depend on shared primitives from `ofxGgmlCore`
- preserve openFrameworks addon layout and `addon_config.mk`
- keep examples projectGenerator-friendly
- document model/runtime requirements clearly

Do not:

- move backend-neutral Core primitives into this repo
- commit models, generated masks/images, binaries, or caches
- hardcode local absolute paths

## Codex workflow

1. Inspect existing files first.
2. Keep changes small and focused.
3. Preserve addon boundaries.
4. Update docs/examples/scripts with code changes.
5. Summarize validation honestly.
