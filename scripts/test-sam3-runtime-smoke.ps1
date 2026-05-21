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
