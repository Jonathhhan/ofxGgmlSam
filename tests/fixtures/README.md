# SAM Fixture Images

These fixtures are tiny hand-authored RGB PPM files for segmentation smoke
planning and future fixture-backed output checks. They are intentionally model
free and may be committed because they contain no generated masks, model
weights, downloaded runtime data, or captured user media.

Regenerate the fixture set into a temporary directory and verify it against the
committed copy with:

```powershell
scripts\generate-sam-fixtures.bat -Clean -Verify
```

Use `sam-point-square.ppm` with the SAM3 runtime smoke when a deterministic
input image is useful:

```powershell
scripts\run-sam3-runtime-smoke.bat -DryRun -Image tests\fixtures\sam-point-square.ppm
```

With a local SAM3/SAM2/EdgeTAM `.ggml` model and built runtime, the same image
can drive the fixture output check:

```powershell
scripts\run-sam3-runtime-smoke.bat -Backend cpu -Image tests\fixtures\sam-point-square.ppm -Json -SummaryOnly -FixtureVerify
```
