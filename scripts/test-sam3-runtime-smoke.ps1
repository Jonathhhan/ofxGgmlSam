param()

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$smokeScript = Join-Path $scriptRoot "run-sam3-runtime-smoke.ps1"

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

Write-Host "SAM3 runtime smoke contract passed"
