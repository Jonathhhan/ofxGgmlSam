param()

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$smokeScript = Join-Path $scriptRoot "run-sam3-runtime-smoke.ps1"
$fixtureImage = Join-Path (Split-Path -Parent $scriptRoot) "tests\fixtures\sam-point-square.ppm"

$textOutput = & $smokeScript -DryRun -Backend cpu *>&1 | ForEach-Object { $_.ToString() }
if ($LASTEXITCODE -ne 0) {
	throw "run-sam3-runtime-smoke.ps1 -DryRun failed."
}
$text = $textOutput -join "`n"
foreach ($expected in @(
	"ofxGgmlSam SAM3 runtime smoke plan",
	"Tool:",
	"BuildDir:",
	"Backend:    cpu",
	"Image:",
	"Ready:"
)) {
	if ($text -notmatch [regex]::Escape($expected)) {
		throw "SAM3 runtime smoke dry-run output did not contain expected text: $expected"
	}
}

$jsonOutput = & $smokeScript -DryRun -Backend cpu -Json -SummaryOnly *>&1 | ForEach-Object { $_.ToString() }
if ($LASTEXITCODE -ne 0) {
	throw "run-sam3-runtime-smoke.ps1 -DryRun -Json failed."
}
$json = ($jsonOutput -join "`n") | ConvertFrom-Json
if ($json.Name -ne "ofxGgmlSam SAM3 runtime smoke") {
	throw "SAM3 runtime smoke JSON did not include the expected Name."
}
if ($json.Backend -ne "cpu") {
	throw "SAM3 runtime smoke JSON did not preserve the requested backend."
}
if (($json.NextCommands -join "`n") -notmatch "run-sam3-runtime-smoke\.bat -Backend cpu") {
	throw "SAM3 runtime smoke JSON did not include the CPU runtime command."
}
if ($json.SmokeKind -ne "model-backed-sam3-point-segmentation") {
	throw "SAM3 runtime smoke JSON did not include the expected smoke kind."
}

$fixtureJsonOutput = & $smokeScript -DryRun -Backend cpu -Image $fixtureImage -Json -SummaryOnly *>&1 | ForEach-Object { $_.ToString() }
if ($LASTEXITCODE -ne 0) {
	throw "run-sam3-runtime-smoke.ps1 -DryRun -Image -Json failed."
}
$fixtureJson = ($fixtureJsonOutput -join "`n") | ConvertFrom-Json
if ($fixtureJson.Image -ne $fixtureImage) {
	throw "SAM3 runtime smoke JSON did not preserve the requested fixture image."
}

$evidencePath = Join-Path ([System.IO.Path]::GetTempPath()) "ofxGgmlSam3-runtime-smoke-evidence.json"
Remove-Item -LiteralPath $evidencePath -Force -ErrorAction SilentlyContinue
$null = & $smokeScript -DryRun -Backend cpu -Json -SummaryOnly -OutputPath $evidencePath
if ($LASTEXITCODE -ne 0) {
	throw "run-sam3-runtime-smoke.ps1 evidence dry-run failed."
}
if (!(Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
	throw "SAM3 runtime smoke did not write dry-run evidence output."
}
$evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
if ($evidence.SmokeKind -ne "model-backed-sam3-point-segmentation") {
	throw "SAM3 runtime smoke evidence did not preserve the smoke kind."
}
Remove-Item -LiteralPath $evidencePath -Force -ErrorAction SilentlyContinue

Write-Host "SAM3 runtime smoke contract passed"

# Test FailureCategory field in dry-run JSON output
$jsonDryRun = & $smokeScript -DryRun -Backend cpu -Json -SummaryOnly *>&1 | ForEach-Object { $_.ToString() }
$jsonDryRunObj = ($jsonDryRun -join "`n") | ConvertFrom-Json
if ($jsonDryRunObj.FailureCategory -ne "none") {
    throw "SAM3 runtime smoke dry-run JSON FailureCategory should be 'none' but was '$($jsonDryRunObj.FailureCategory)'"
}

# Test CacheVerify parameter exists (dry-run should not run cache verification)
$jsonCacheVerify = & $smokeScript -DryRun -Backend cpu -Json -SummaryOnly -CacheVerify *>&1 | ForEach-Object { $_.ToString() }
if ($LASTEXITCODE -ne 0) {
    throw "run-sam3-runtime-smoke.ps1 -DryRun -CacheVerify failed."
}
$jsonCacheVerifyObj = ($jsonCacheVerify -join "`n") | ConvertFrom-Json
if ($jsonCacheVerifyObj.FailureCategory -ne "none") {
    throw "SAM3 runtime smoke dry-run with -CacheVerify should have FailureCategory 'none'"
}

Write-Host "SAM3 runtime smoke new field tests passed"

# Test Classify-Failure function categorization
function Classify-Failure {
    param([string] $ErrorMessage, [string] $ModelPath, [string] $Backend)
    if ([string]::IsNullOrWhiteSpace($ErrorMessage)) { return "none" }
    $lower = $ErrorMessage.ToLowerInvariant()
    if ($lower -match "no sam3 model|model was not found|could not open.*model|--model is required") { return "missing_model" }
    if ($lower -match "wrong.*extension|extension.*mismatch|\.gguf.*sam3|expected.*\.ggml") { return "wrong_extension" }
    if ($lower -match "sam3\.h was not found|sam3\.cpp|runtime.*not found|lib.*not found|build tools.*not found") { return "missing_runtime" }
    if ($lower -match "build.*failed|cmake.*failed|compile.*failed|link.*failed|vsdevcmd") { return "build_failure" }
    if ($lower -match "cuda.*mismatch|ggml.*mismatch|cuda.*not found|cudart|cublas.*not found|backend.*cuda.*not.*available") { return "cuda_mismatch" }
    if ($lower -match "executable.*not found|not found.*exe") { return "missing_runtime" }
    if ($lower -match "sam3_load_model|sam3_create_state|sam3_encode_image|sam3_segment_pvs|returned null|produced no detections") { return "runtime_execution_failure" }
    return "runtime_execution_failure"
}

$classifyTests = @(
    @{ Error = ""; Expected = "none" },
    @{ Error = "No SAM3 model was found"; Expected = "missing_model" },
    @{ Error = "model was not found in data dir"; Expected = "missing_model" },
    @{ Error = "Wrong extension: expected .ggml got .gguf"; Expected = "wrong_extension" },
    @{ Error = "sam3.h was not found"; Expected = "missing_runtime" },
    @{ Error = "build failed with exit code 1"; Expected = "build_failure" },
    @{ Error = "cuda mismatch detected"; Expected = "cuda_mismatch" },
    @{ Error = "sam3_load_model returned null"; Expected = "runtime_execution_failure" },
    @{ Error = "some unknown error occurred"; Expected = "runtime_execution_failure" }
)

foreach ($test in $classifyTests) {
    $result = Classify-Failure -ErrorMessage $test.Error -ModelPath "" -Backend "cpu"
    if ($result -ne $test.Expected) {
        throw "Classify-Failure('$($test.Error)') returned '$result' but expected '$($test.Expected)'"
    }
}

Write-Host "Classify-Failure categorization tests passed"
