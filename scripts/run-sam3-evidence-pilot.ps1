param(
	[string] $Model = $env:OFXGGML_SAM_MODEL,
	[ValidateSet("cpu", "cuda")]
	[string] $Backend = $(if ([string]::IsNullOrWhiteSpace($env:OFXGGML_SAM_RUNTIME_BACKEND)) { "cpu" } else { $env:OFXGGML_SAM_RUNTIME_BACKEND }),
	[int] $Threads = 0,
	[int] $ImageSize = 256,
	[string] $Image = "",
	[string] $SmokePath = ".sam3-runtime-smoke.json",
	[string] $EvidencePath = "build\evidence\sam3-runtime-evidence.json",
	[string] $QualityReportPath = "build\evidence\evidence-quality.md",
	[string] $WorkflowsRoot = "",
	[switch] $SkipBuild,
	[switch] $SkipSmoke,
	[switch] $FixtureVerify,
	[switch] $BoxVerify,
	[switch] $DryRun,
	[switch] $Json
)

$ErrorActionPreference = "Stop"

function Write-Step {
	param([string] $Message)
	if (-not $Json) { Write-Host "==> $Message" }
}

function Resolve-AddonPath {
	param([string] $Path)
	if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
	return Join-Path $addonRoot $Path
}

function Resolve-WorkflowsRoot {
	if (-not [string]::IsNullOrWhiteSpace($WorkflowsRoot)) {
		return (Resolve-Path $WorkflowsRoot).Path
	}
	$candidate = Join-Path (Split-Path -Parent $addonRoot) "ofxGgmlWorkflows"
	if (Test-Path -LiteralPath $candidate -PathType Container) { return (Resolve-Path $candidate).Path }
	throw "ofxGgmlWorkflows sibling checkout was not found. Pass -WorkflowsRoot."
}

function Get-GitValue {
	param([string[]] $Args)
	try {
		$value = & git -C $addonRoot @Args 2>$null
		if ($LASTEXITCODE -eq 0 -and $value) { return ($value | Select-Object -First 1).ToString().Trim() }
	} catch {}
	return ""
}

function Get-PythonCommand {
	$python = Get-Command python -ErrorAction SilentlyContinue
	if ($python) { return $python.Source }
	$python3 = Get-Command python3 -ErrorAction SilentlyContinue
	if ($python3) { return $python3.Source }
	throw "Python was not found on PATH; cannot run Workflows evidence validator."
}

function Write-Plan {
	$resolvedWorkflowsRoot = Resolve-WorkflowsRoot
	$validator = Join-Path $resolvedWorkflowsRoot "scripts\validate-evidence.py"
	$plan = [ordered] @{
		Name = "ofxGgmlSam SAM3 evidence pilot"
		Backend = $Backend
		SmokePath = $SmokePath
		EvidencePath = $EvidencePath
		QualityReportPath = $QualityReportPath
		WorkflowsRoot = $resolvedWorkflowsRoot
		Validator = $validator
		SkipSmoke = $SkipSmoke.IsPresent
		NextCommands = @(
			"scripts\run-sam3-evidence-pilot.bat -DryRun",
			"scripts\run-sam3-evidence-pilot.bat -Backend cpu",
			"scripts\run-sam3-evidence-pilot.bat -Backend cpu -Image tests\fixtures\sam-point-square.ppm -FixtureVerify",
			"scripts\run-sam3-evidence-pilot.bat -Backend cpu -BoxVerify"
		)
	}
	if ($Json) { $plan | ConvertTo-Json -Depth 5 } else {
		Write-Host "ofxGgmlSam SAM3 evidence pilot plan"
		Write-Host "Backend:       $Backend"
		Write-Host "SmokePath:     $SmokePath"
		Write-Host "EvidencePath:  $EvidencePath"
		Write-Host "QualityReport: $QualityReportPath"
		Write-Host "Validator:     $validator"
	}
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonRoot = Resolve-Path (Join-Path $scriptRoot "..")

if ($DryRun) {
	Write-Plan
	exit 0
}

$resolvedSmokePath = Resolve-AddonPath -Path $SmokePath
$resolvedEvidencePath = Resolve-AddonPath -Path $EvidencePath
$resolvedQualityReportPath = Resolve-AddonPath -Path $QualityReportPath
$resolvedWorkflowsRoot = Resolve-WorkflowsRoot
$validator = Join-Path $resolvedWorkflowsRoot "scripts\validate-evidence.py"
if (!(Test-Path -LiteralPath $validator -PathType Leaf)) {
	throw "Workflows evidence validator was not found: $validator"
}

$smokeExitCode = 0
if (-not $SkipSmoke) {
	Write-Step "Running SAM3 runtime smoke"
	$smokeScript = Join-Path $scriptRoot "run-sam3-runtime-smoke.ps1"
	$smokeArgs = @("-Backend", $Backend, "-Json", "-SummaryOnly", "-OutputPath", $resolvedSmokePath)
	if (-not [string]::IsNullOrWhiteSpace($Model)) { $smokeArgs += @("-Model", $Model) }
	if (-not [string]::IsNullOrWhiteSpace($Image)) { $smokeArgs += @("-Image", $Image) }
	if ($Threads -gt 0) { $smokeArgs += @("-Threads", $Threads.ToString()) }
	if ($ImageSize -gt 0) { $smokeArgs += @("-ImageSize", $ImageSize.ToString()) }
	if ($SkipBuild) { $smokeArgs += "-SkipBuild" }
	if ($FixtureVerify) { $smokeArgs += "-FixtureVerify" }
	if ($BoxVerify) { $smokeArgs += "-BoxVerify" }
	$smokeOutput = & $smokeScript @smokeArgs 2>&1 | ForEach-Object { $_.ToString() }
	$smokeExitCode = $LASTEXITCODE
	if ($smokeExitCode -ne 0 -and !(Test-Path -LiteralPath $resolvedSmokePath -PathType Leaf)) {
		$detail = ($smokeOutput -join [Environment]::NewLine).Trim()
		throw "SAM3 runtime smoke failed before writing evidence input. $detail"
	}
} elseif (!(Test-Path -LiteralPath $resolvedSmokePath -PathType Leaf)) {
	throw "-SkipSmoke requires an existing smoke JSON file: $resolvedSmokePath"
}

Write-Step "Writing Evidence Schema v1 wrapper"
$writer = Join-Path $scriptRoot "write-sam3-runtime-evidence.ps1"
$writerOutput = & $writer -SmokePath $resolvedSmokePath -OutputPath $resolvedEvidencePath -Backend $Backend -PassThru 2>&1 | ForEach-Object { $_.ToString() }
if ($LASTEXITCODE -ne 0) {
	throw "SAM3 runtime evidence writer failed: $($writerOutput -join [Environment]::NewLine)"
}

Write-Step "Validating evidence with ofxGgmlWorkflows"
$commitSha = Get-GitValue -Args @("rev-parse", "HEAD")
if ([string]::IsNullOrWhiteSpace($commitSha)) { $commitSha = "unknown" }
$python = Get-PythonCommand
$validatorArgs = @(
	$validator,
	"--evidence-path", $resolvedEvidencePath,
	"--require-evidence-file", "true",
	"--require-schema-valid", "true",
	"--require-current-sha", "true",
	"--expected-commit-sha", $commitSha,
	"--required-backend", $Backend,
	"--required-result", "pass",
	"--minimum-certification-level", "runtime-certified",
	"--quality-report-path", $resolvedQualityReportPath
)
$validationOutput = & $python @validatorArgs 2>&1 | ForEach-Object { $_.ToString() }
$validationExitCode = $LASTEXITCODE

$status = if ($smokeExitCode -eq 0 -and $validationExitCode -eq 0) { "ready_for_advisory_caller" } else { "blocked" }
$result = [ordered] @{
	status = $status
	backend = $Backend
	smoke_exit_code = $smokeExitCode
	validation_exit_code = $validationExitCode
	evidence_path = $resolvedEvidencePath
	quality_report_path = $resolvedQualityReportPath
	validator = $validator
	next_action = $(if ($status -eq "ready_for_advisory_caller") { "Enable or keep evidence-validation.yml in advisory mode." } else { "Fix smoke or evidence validation before promotion." })
	validation_output = $validationOutput
}

if ($Json) {
	$result | ConvertTo-Json -Depth 5
} else {
	Write-Host "Status:       $status"
	Write-Host "Evidence:     $resolvedEvidencePath"
	Write-Host "Quality:      $resolvedQualityReportPath"
	if ($validationOutput) { $validationOutput | ForEach-Object { Write-Host $_ } }
}

if ($status -ne "ready_for_advisory_caller") { exit 1 }
exit 0