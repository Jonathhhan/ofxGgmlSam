param(
	[string] $SmokePath = ".sam3-runtime-smoke.json",
	[string] $OutputPath = "build\evidence\sam3-runtime-evidence.json",
	[string] $Repo = "ofxGgmlSam",
	[string] $Lane = "segmentation",
	[string] $CommitSha = "",
	[string] $WorkflowName = "sam3-runtime-smoke",
	[string] $RunnerOs = "",
	[string] $Backend = "",
	[string] $ArtifactPath = "",
	[string] $Command = "",
	[string] $QualityReportPath = "build/evidence/evidence-quality.md",
	[switch] $PassThru
)

$ErrorActionPreference = "Stop"

function Resolve-AddonPath {
	param([string] $Path)
	if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
	return Join-Path $addonRoot $Path
}

function ConvertTo-RepoRelativePath {
	param([string] $Path)
	$resolved = Resolve-AddonPath -Path $Path
	$root = $addonRoot.Path.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
	if ($resolved.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
		$relative = $resolved.Substring($root.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
		return ($relative -replace '\\', '/')
	}
	return ($Path -replace '\\', '/')
}

function Get-GitValue {
	param([string[]] $Args)
	try {
		$value = & git -C $addonRoot @Args 2>$null
		if ($LASTEXITCODE -eq 0 -and $value) { return ($value | Select-Object -First 1).ToString().Trim() }
	} catch {}
	return ""
}

function Get-RunnerOs {
	if (-not [string]::IsNullOrWhiteSpace($RunnerOs)) { return $RunnerOs }
	if (-not [string]::IsNullOrWhiteSpace($env:RUNNER_OS)) { return $env:RUNNER_OS }
	if ($IsLinux) { return "Linux" }
	if ($IsMacOS) { return "macOS" }
	return "Windows"
}

function Get-TreeState {
	$status = Get-GitValue -Args @("status", "--porcelain")
	if ([string]::IsNullOrWhiteSpace($status)) { return "clean" }
	return "dirty"
}

function Get-UntrackedCount {
	$status = Get-GitValue -Args @("status", "--porcelain")
	if ([string]::IsNullOrWhiteSpace($status)) { return 0 }
	$count = 0
	foreach ($line in @($status -split "`r?`n")) {
		if ($line.StartsWith("??")) { $count++ }
	}
	return $count
}

function Get-IsoTimestamp {
	return (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonRoot = Resolve-Path (Join-Path $scriptRoot "..")
$resolvedSmokePath = Resolve-AddonPath -Path $SmokePath
if (!(Test-Path -LiteralPath $resolvedSmokePath -PathType Leaf)) {
	throw "SAM3 runtime smoke JSON was not found: $resolvedSmokePath"
}

$smoke = Get-Content -LiteralPath $resolvedSmokePath -Raw | ConvertFrom-Json
$summary = $smoke.Summary
if ($null -eq $summary) {
	throw "SAM3 runtime smoke JSON must include a Summary object. Run scripts\run-sam3-runtime-smoke.bat -Backend cpu -Json -SummaryOnly -OutputPath .sam3-runtime-smoke.json first."
}

if ([string]::IsNullOrWhiteSpace($CommitSha)) { $CommitSha = Get-GitValue -Args @("rev-parse", "HEAD") }
if ([string]::IsNullOrWhiteSpace($CommitSha)) { $CommitSha = "unknown" }
if ([string]::IsNullOrWhiteSpace($Backend)) { $Backend = $summary.Backend }
if ([string]::IsNullOrWhiteSpace($Backend)) { $Backend = "unknown" }
if ([string]::IsNullOrWhiteSpace($ArtifactPath)) { $ArtifactPath = ConvertTo-RepoRelativePath -Path $SmokePath }
if ([string]::IsNullOrWhiteSpace($Command)) {
	$Command = "scripts/run-sam3-runtime-smoke.bat -Backend $Backend -Json -SummaryOnly -OutputPath $ArtifactPath"
}

$result = if ($summary.Passed -eq $true) { "pass" } else { "fail" }
$certificationLevel = if ($summary.Passed -eq $true -and $summary.InferenceChecked -eq $true) { "runtime-certified" } else { "declared" }
$reasonCode = if ($smoke.FailureCategory) { $smoke.FailureCategory } elseif ($result -eq "pass") { "none" } else { "runtime_execution_failure" }
$timestamp = Get-IsoTimestamp
$treeState = Get-TreeState
$untrackedCount = Get-UntrackedCount

$evidence = [ordered] @{
	schema_version = "1"
	repo = $Repo
	lane = $Lane
	commit_sha = $CommitSha
	workflow_name = $WorkflowName
	runner_os = Get-RunnerOs
	backend = $Backend
	result = $result
	timestamp = $timestamp
	artifact_path = $ArtifactPath
	command = $Command
	command_exit_code = $(if ($result -eq "pass") { 0 } else { 1 })
	certification_level = $certificationLevel
	reason_code = $reasonCode
	producer = "write-sam3-runtime-evidence.ps1"
	producer_version = "1.0.0"
	tree_state = $treeState
	untracked_count = $untrackedCount
	subject_paths = @(
		"scripts/run-sam3-runtime-smoke.ps1",
		"tools/ofxGgmlSam3RuntimeSmoke"
	)
	quality_report_path = $QualityReportPath
	example_name = "ofxGgmlSamPointExample"
	smoke_kind = $summary.SmokeKind
	prompt_kind = $summary.PromptKind
	inference_checked = [bool] $summary.InferenceChecked
	duration_ms = $(if ($null -ne $summary.TotalMs) { [double] $summary.TotalMs } else { 0.0 })
	smoke_summary = $summary
}

if ($env:GITHUB_RUN_ID) { $evidence.workflow_run_id = $env:GITHUB_RUN_ID }
if ($env:GITHUB_RUN_ATTEMPT) { $evidence.workflow_run_attempt = $env:GITHUB_RUN_ATTEMPT }
if ($env:GITHUB_WORKFLOW_REF) { $evidence.workflow_ref = $env:GITHUB_WORKFLOW_REF }
if ($env:GITHUB_WORKFLOW_SHA) { $evidence.workflow_sha = $env:GITHUB_WORKFLOW_SHA }
if ($env:GITHUB_JOB) { $evidence.job_name = $env:GITHUB_JOB }
if ($env:GITHUB_EVENT_NAME) { $evidence.event_name = $env:GITHUB_EVENT_NAME }

$content = $evidence | ConvertTo-Json -Depth 8
$resolvedOutputPath = Resolve-AddonPath -Path $OutputPath
$outputDirectory = Split-Path -Parent $resolvedOutputPath
if (!(Test-Path -LiteralPath $outputDirectory -PathType Container)) {
	New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}
Set-Content -LiteralPath $resolvedOutputPath -Value $content

if ($PassThru) { Write-Output $content } else { Write-Host "Wrote SAM3 runtime Evidence Schema v1 wrapper: $resolvedOutputPath" }
exit 0
