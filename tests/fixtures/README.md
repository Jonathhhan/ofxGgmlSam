# SAM Fixture Images

These fixtures are tiny hand-authored RGB PPM files for segmentation smoke
planning and future fixture-backed output checks. They are intentionally model
free and may be committed because they contain no generated masks, model
weights, downloaded runtime data, or captured user media.

Use `sam-point-square.ppm` with the SAM3 runtime smoke when a deterministic
input image is useful:

```powershell
scripts\run-sam3-runtime-smoke.bat -DryRun -Image tests\fixtures\sam-point-square.ppm
```
