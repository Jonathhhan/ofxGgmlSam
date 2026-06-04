param()

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$evidenceScript = Join-Path $scriptRoot "write-sam3-runtime-evidence.ps1"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ofxGgmlSam-evidence-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
	$smokePath = Join-Path $tempRoot "sam3-runtime-smoke.json"
	$outputPath = Join-Path $tempRoot "sam3-runtime-evidence.json"
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

	$jsonOutput = & $evidenceScript -SmokePath $smokePath -OutputPath $outputPath -CommitSha "0123456789abcdef" -RunnerOs "Windows" -PassThru *>&1 | ForEach-Object { $_.ToString() }
	if ($LASTEXITCODE -ne 0) { throw "write-sam3-runtime-evidence.ps1 failed." }
	if (!(Test-Path -LiteralPath $outputPath -PathType Leaf)) { throw "Evidence wrapper was not written." }

	$evidence = (Get-Content -LiteralPath $outputPath -Raw) | ConvertFrom-Json
	foreach ($field in @("schema_version", "repo", "lane", "commit_sha", "workflow_name", "runner_os", "backend", "result", "timestamp", "artifact_path")) {
		if ($null -eq $evidence.PSObject.Properties[$field] -or [string]::IsNullOrWhiteSpace([string]$evidence.$field)) {
			throw "Evidence wrapper missing required field: $field"
		}
	}
	if ($evidence.schema_version -ne "1") { throw "Unexpected schema_version: $($evidence.schema_version)" }
	if ($evidence.repo -ne "ofxGgmlSam") { throw "Unexpected repo: $($evidence.repo)" }
	if ($evidence.lane -ne "segmentation") { throw "Unexpected lane: $($evidence.lane)" }
	if ($evidence.backend -ne "cpu") { throw "Unexpected backend: $($evidence.backend)" }
	if ($evidence.result -ne "pass") { throw "Unexpected result: $($evidence.result)" }
	if ($evidence.certification_level -ne "runtime-certified") { throw "Unexpected certification level: $($evidence.certification_level)" }
	if ($evidence.producer -ne "write-sam3-runtime-evidence.ps1") { throw "Unexpected producer: $($evidence.producer)" }
	if ($evidence.smoke_kind -ne "model-backed-sam3-point-segmentation") { throw "Smoke kind was not preserved." }
	if ($evidence.smoke_summary.MaskCount -ne 1) { throw "Smoke summary was not preserved." }
	if (($evidence.subject_paths -join "`n") -notmatch "run-sam3-runtime-smoke\.ps1") { throw "Evidence subject paths did not include the smoke script." }

	$failedSmokePath = Join-Path $tempRoot "sam3-runtime-smoke-fail.json"
	$failedOutputPath = Join-Path $tempRoot "sam3-runtime-evidence-fail.json"
	$failedSmoke = [ordered] @{
		SummaryOnly = $true
		Summary = [ordered] @{
			Passed = $false
			InferenceChecked = $false
			SmokeKind = "model-backed-sam3-point-segmentation"
			PromptKind = "point"
			Backend = "cuda"
			ModelPath = ""
			ImagePath = ""
			Threads = 0
			ImageSize = 256
			MaskCount = 0
			TotalMs = 0
			Error = "No SAM3 model was found"
		}
		FailureCategory = "missing_model"
	}
	$failedSmoke | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $failedSmokePath
	$null = & $evidenceScript -SmokePath $failedSmokePath -OutputPath $failedOutputPath -CommitSha "0123456789abcdef" -RunnerOs "Windows" -PassThru
	if ($LASTEXITCODE -ne 0) { throw "write-sam3-runtime-evidence.ps1 failed for failed smoke." }
	$failedEvidence = (Get-Content -LiteralPath $failedOutputPath -Raw) | ConvertFrom-Json
	if ($failedEvidence.result -ne "fail") { throw "Failed smoke should write result=fail." }
	if ($failedEvidence.reason_code -ne "missing_model") { throw "Failed smoke should preserve FailureCategory." }
	if ($failedEvidence.command_exit_code -ne 1) { throw "Failed smoke should write command_exit_code=1." }
} finally {
	Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "SAM3 runtime evidence wrapper contract passed"