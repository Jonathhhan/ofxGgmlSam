# Contributing

`ofxGgmlSam` is a companion addon. Keep SAM-specific workflow code here and keep
generic ggml/runtime primitives in `ofxGgml`.

Before adding features:

- keep `ofxGgmlSam` depending on `ofxGgml`, never the reverse
- keep examples focused on one segmentation workflow at a time
- do not commit model binaries, generated projects, native build folders, or
  sample media without a clear license
- move code down into `ofxGgml` only when it is domain-neutral and tested
- update `docs/ROADMAP.md` when the planned workflow changes

Run this before pushing:

```powershell
scripts\validate-local.bat
```
