param()

$ErrorActionPreference = "Stop"

function Write-Step {
	param([string]$Message)
	Write-Host "==> $Message"
}

function Assert-Path {
	param(
		[string]$Path,
		[string]$Label
	)

	if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
		throw "$Label was not found: $Path"
	}
}

function Assert-FileContains {
	param(
		[string]$Path,
		[string]$Pattern,
		[string]$Label
	)

	$content = Get-Content -LiteralPath $Path -Raw
	if ($content -notmatch $Pattern) {
		throw "$Label did not contain expected pattern: $Pattern"
	}
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonRoot = Split-Path -Parent $scriptRoot
$releaseNotes = Join-Path $addonRoot "docs\releases\v1.0.1.md"

Write-Step "Checking release documentation"
Assert-Path (Join-Path $addonRoot "CHANGELOG.md") "changelog"
Assert-Path (Join-Path $addonRoot "docs\RELEASE_CHECKLIST.md") "release checklist"
Assert-Path (Join-Path $addonRoot "docs\RELEASE_POLICY.md") "release policy"
Assert-Path (Join-Path $addonRoot "docs\RELEASE_NOTES_TEMPLATE.md") "release notes template"
Assert-Path $releaseNotes "v1.0.1 release notes"
Assert-FileContains (Join-Path $addonRoot "CHANGELOG.md") "## 1\.0\.1" "changelog"
Assert-FileContains $releaseNotes "OFXGGML_SAM_VERSION_STRING.*1\.0\.1" "v1.0.1 release notes"
Assert-FileContains $releaseNotes "does not include a complete SAM/SAM2/SAM3 model runtime adapter yet" "v1.0.1 release notes"

Write-Step "Running local validation"
& (Join-Path $scriptRoot "validate-local.ps1")
if ($LASTEXITCODE -ne 0) {
	throw "Local validation failed with exit code $LASTEXITCODE"
}

Write-Step "Release candidate pass completed"
