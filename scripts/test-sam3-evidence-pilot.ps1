param()

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$pilotScript = Join-Path $scriptRoot "run-sam3-evidence-pilot.ps1"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ofxGgmlSam-pilot-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
	$dryRunOutput = & $pilotScript -DryRun -Json *>&1 | ForEach-Object { $_.ToString() }
	if ($LASTEXITCODE -ne 0) { throw "run-sam3-evidence-pilot.ps1 -DryRun failed." }
	$plan = ($dryRunOutput -join "`n") | ConvertFrom-Json
	if ($plan.Name -ne "ofxGgmlSam SAM3 evidence pilot") { throw "Pilot dry-run did not include the expected name." }
	if ($plan.Validator -notmatch "validate-evidence\.py") { throw "Pilot dry-run did not point at the Workflows validator." }

	$smokePath = Join-Path $tempRoot "sam3-runtime-smoke.json"
	$evidencePath = Join-Path $tempRoot "sam3-runtime-evidence.json"
	$qualityPath = Join-Path $tempRoot "evidence-quality.md"
	$smoke = [ordered] @{
		SummaryOnly = $true
		Summary = [ordered] @{
			Passed = $true
			InferenceChecked = $true
			SmokeKind = "model-backed-sam3-point-segmentation"
			PromptKind = "point"
			Backend = "cpu"
			ModelPath = "models/sam3-q8_0.ggml"
			ImagePath = "tests/fixtures/sam-point-square.ppm"
			Threads = 4
			ImageSize = 256
			MaskCount = 1
			LoadMs = 1.0
			StateMs = 2.0
			EncodeMs = 3.0
			SegmentMs = 4.0
			TotalMs = 10.0
			Error = ""
		}
		FailureCategory = "none"
	}
	$smoke | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $smokePath

	$resultOutput = & $pilotScript -SkipSmoke -SmokePath $smokePath -EvidencePath $evidencePath -QualityReportPath $qualityPath -Backend cpu -Json *>&1 | ForEach-Object { $_.ToString() }
	if ($LASTEXITCODE -ne 0) { throw "run-sam3-evidence-pilot.ps1 -SkipSmoke failed: $($resultOutput -join "`n")" }
	$result = ($resultOutput -join "`n") | ConvertFrom-Json
	if ($result.status -ne "ready_for_advisory_caller") { throw "Pilot did not report ready_for_advisory_caller." }
	if (!(Test-Path -LiteralPath $evidencePath -PathType Leaf)) { throw "Pilot did not write evidence output." }
	if (!(Test-Path -LiteralPath $qualityPath -PathType Leaf)) { throw "Pilot did not write quality report." }
	$evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
	if ($evidence.result -ne "pass" -or $evidence.backend -ne "cpu") { throw "Pilot evidence did not preserve pass/cpu." }
	if ($evidence.certification_level -ne "runtime-certified") { throw "Pilot evidence did not preserve runtime certification." }
} finally {
	Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "SAM3 evidence pilot contract passed"