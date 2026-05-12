# Changelog

## Unreleased

- Added `ofxGgmlSamExternalBackend` as the first concrete adapter boundary for
  local SAM/SAM2/SAM3 runner executables.
- Added a mock external adapter and contract test for the file-based
  model/image/point/mask protocol.
- Upgraded the point example from a skeleton to an image-loading point prompt
  UI that can call the external adapter and preview returned masks.
- Forwarded all request points to the external adapter as repeated point flags,
  with contract coverage for positive and negative prompts.

## 1.0.1 - 2026-05-12

- Added independent SAM addon version metadata.
- Exposed version metadata through the public umbrella header.
- Added validation coverage for version metadata and the root-level point
  example layout.
- Kept the first release scope narrow: public SAM request/result types,
  validation helpers, a bridge backend, headless tests, and a point example
  skeleton.

## 1.0.0

- Started `ofxGgmlSam` as the companion addon for SAM/SAM2/SAM3 segmentation
  workflows on top of `ofxGgmlCore`.
- Added the initial bridge API, prompt utility helpers, local validation
  scripts, and root-level point example skeleton.
