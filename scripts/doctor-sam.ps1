param(
	[string]$AdapterExecutable = $(if ($env:OFXGGML_SAM_EXECUTABLE) { $env:OFXGGML_SAM_EXECUTABLE } else { "" }),
	[string]$Model = $(if ($env:OFXGGML_SAM_MODEL) { $env:OFXGGML_SAM_MODEL } else { "" }),
	[string]$Image = $(if ($env:OFXGGML_SAM_IMAGE) { $env:OFXGGML_SAM_IMAGE } else { "" }),
	[switch]$Json,
	[switch]$Strict
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonRoot = Resolve-Path (Join-Path $scriptRoot "..")
$addonsRoot = Split-Path -Parent $addonRoot
$script:Warnings = 0

function New-Check {
	param(
		[string]$State,
		[string]$Name,
		[string]$Detail = ""
	)
	if ($State -eq "WARN") {
		$script:Warnings++
	}
	return [pscustomobject]@{
		State = $State
		Name = $Name
		Detail = $Detail
	}
}

function Test-CommandAvailable {
	param([string]$Name)
	return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-ConfiguredFile {
	param(
		[string]$Path,
		[string]$Name,
		[string]$Hint
	)
	if ([string]::IsNullOrWhiteSpace($Path)) {
		return New-Check "WARN" $Name $Hint
	}
	$expanded = [Environment]::ExpandEnvironmentVariables($Path)
	if (Test-Path -LiteralPath $expanded -PathType Leaf) {
		return New-Check "OK" $Name $expanded
	}
	return New-Check "WARN" $Name "configured path was not found: $expanded"
}

function Test-PathCheck {
	param(
		[string]$Path,
		[string]$Name,
		[string]$MissingDetail,
		[switch]$Directory
	)
	$exists = if ($Directory) {
		Test-Path -LiteralPath $Path -PathType Container
	} else {
		Test-Path -LiteralPath $Path -PathType Leaf
	}
	if ($exists) {
		return New-Check "OK" $Name $Path
	}
	return New-Check "WARN" $Name $MissingDetail
}

function Test-ForbiddenPath {
	param([string]$RelativePath)
	$path = Join-Path $addonRoot $RelativePath
	if (Test-Path -LiteralPath $path) {
		return New-Check "WARN" "artifact hygiene" "generated/local path exists: $RelativePath"
	}
	return $null
}

$checks = @()
$checks += New-Check "OK" "addon root" $addonRoot.Path

foreach ($tool in @("git", "cmake")) {
	if (Test-CommandAvailable $tool) {
		$checks += New-Check "OK" $tool ((Get-Command $tool).Source)
	} else {
		$checks += New-Check "WARN" $tool "not found in PATH"
	}
}

$checks += Test-PathCheck `
	-Path (Join-Path $addonsRoot "ofxGgmlCore") `
	-Name "ofxGgmlCore sibling" `
	-MissingDetail "clone beside ofxGgmlSam" `
	-Directory

$checks += Test-PathCheck `
	-Path (Join-Path $addonsRoot "ofxImGui") `
	-Name "ofxImGui" `
	-MissingDetail "install beside ofxGgmlSam before building the point example" `
	-Directory

$checks += Test-PathCheck `
	-Path (Join-Path $addonRoot "ofxGgmlSamPointExample\addons.make") `
	-Name "point example" `
	-MissingDetail "ofxGgmlSamPointExample skeleton is missing"

$checks += Test-PathCheck `
	-Path (Join-Path $addonRoot "tools\ofxGgmlSamMockAdapter\main.cpp") `
	-Name "mock adapter source" `
	-MissingDetail "mock adapter source is missing"

$checks += Test-PathCheck `
	-Path (Join-Path $addonRoot "tools\ofxGgmlSamMockAdapter\CMakeLists.txt") `
	-Name "mock adapter build file" `
	-MissingDetail "mock adapter CMakeLists.txt is missing"

$checks += Test-PathCheck `
	-Path (Join-Path $addonRoot "tests\test_external_adapter_contract.cpp") `
	-Name "external adapter contract test" `
	-MissingDetail "external adapter contract test is missing"

$checks += Test-ConfiguredFile `
	-Path $AdapterExecutable `
	-Name "SAM adapter executable" `
	-Hint "set OFXGGML_SAM_EXECUTABLE or pass -AdapterExecutable"

$checks += Test-ConfiguredFile `
	-Path $Model `
	-Name "SAM model" `
	-Hint "set OFXGGML_SAM_MODEL or pass -Model"

$checks += Test-ConfiguredFile `
	-Path $Image `
	-Name "sample image" `
	-Hint "set OFXGGML_SAM_IMAGE or pass -Image"

$dryRunOutput = try {
	& (Join-Path $scriptRoot "run-point-example.ps1") -DryRun *>&1 | Out-String
} catch {
	""
}
if ($dryRunOutput -like "*Example:    ofxGgmlSamPointExample*" -and $dryRunOutput -like "*Project:*") {
	$checks += New-Check "OK" "point example dry-run" "launcher paths resolved"
} else {
	$checks += New-Check "WARN" "point example dry-run" "run scripts\run-point-example.bat -DryRun"
}

$contractDryRun = try {
	& (Join-Path $scriptRoot "test-external-adapter-contract.ps1") -DryRun 2>&1 6>&1 | Out-String
} catch {
	""
}
if ($contractDryRun -like "*External SAM adapter contract plan*" -and $contractDryRun -like "*Dry run complete*") {
	$checks += New-Check "OK" "external adapter contract dry-run" "contract plan is available"
} else {
	$checks += New-Check "WARN" "external adapter contract dry-run" "run scripts\test-external-adapter-contract.bat -DryRun"
}

$artifactWarnings = @()
foreach ($relative in @(
	"build",
	".vs",
	"ofxGgmlSamPointExample\bin",
	"ofxGgmlSamPointExample\obj",
	"ofxGgmlSamPointExample\.vs",
	"models"
)) {
	$warning = Test-ForbiddenPath -RelativePath $relative
	if ($null -ne $warning) {
		$artifactWarnings += $warning
	}
}
if ($artifactWarnings.Count -eq 0) {
	$checks += New-Check "OK" "artifact hygiene" "no generated/local paths detected"
} else {
	$checks += $artifactWarnings
}

if ($Json) {
	[pscustomobject]@{
		Root = $addonRoot.Path
		Warnings = $script:Warnings
		Checks = $checks
	} | ConvertTo-Json -Depth 5
} else {
	Write-Host "ofxGgmlSam doctor"
	Write-Host "Root  $addonRoot"
	Write-Host ""
	foreach ($check in $checks) {
		$line = "{0,-5} {1}" -f $check.State, $check.Name
		if (![string]::IsNullOrWhiteSpace($check.Detail)) {
			$line += " - $($check.Detail)"
		}
		Write-Host $line
	}
	Write-Host ""
	if ($script:Warnings -eq 0) {
		Write-Host "Doctor passed."
	} else {
		Write-Host "Doctor found $script:Warnings warning(s)."
	}
}

if ($Strict -and $script:Warnings -gt 0) {
	exit 1
}
