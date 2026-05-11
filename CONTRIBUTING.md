# Contributing

`ofxGgmlSam` is a companion addon. Keep SAM-specific workflow code here and keep
generic ggml/runtime primitives in `ofxGgmlCore`.

Before adding features:

- keep `ofxGgmlSam` depending on `ofxGgmlCore`, never the reverse
- keep examples focused on one segmentation workflow at a time
- do not commit model binaries, generated projects, native build folders, or
  sample media without a clear license
- move code down into `ofxGgmlCore` only when it is domain-neutral and tested
- update `docs/ROADMAP.md` when the planned workflow changes

Run this before pushing:

```powershell
scripts\test-addon.bat
scripts\validate-local.bat
```

For the example launcher path:

```powershell
scripts\run-point-example.bat -DryRun
```
