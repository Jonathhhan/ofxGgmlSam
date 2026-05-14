param(
	[string]$AdapterExecutable = $(if ($env:OFXGGML_SAM_EXECUTABLE) { $env:OFXGGML_SAM_EXECUTABLE } else { "" }),
	[string]$Model = $(if ($env:OFXGGML_SAM_MODEL) { $env:OFXGGML_SAM_MODEL } else { "" }),
	[string]$Image = $(if ($env:OFXGGML_SAM_IMAGE) { $env:OFXGGML_SAM_IMAGE } else { "" }),
	[string]$Backend = $(if ($env:OFXGGML_SAM_BACKEND) { $env:OFXGGML_SAM_BACKEND } else { "external-sam" }),
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

function Normalize-Backend {
	param([string]$Name)
	$normalized = $Name.Trim().ToLowerInvariant()
	switch ($normalized) {
		"" { return "external-sam" }
		"external" { return "external-sam" }
		"external-sam" { return "external-sam" }
		"samcpp" { return "sam.cpp" }
		"sam.cpp" { return "sam.cpp" }
		"sam3" { return "sam3.cpp" }
		"sam3.cpp" { return "sam3.cpp" }
		default { return $normalized }
	}
}

function Get-SamCppSourceDir {
	if ([string]::IsNullOrWhiteSpace($env:OFXGGML_SAM_CPP_DIR)) {
		return Join-Path $addonRoot "libs\sam.cpp\source"
	}
	return $env:OFXGGML_SAM_CPP_DIR
}

function Get-Sam3CppSourceDir {
	if ([string]::IsNullOrWhiteSpace($env:OFXGGML_SAM3_CPP_DIR)) {
		return Join-Path $addonRoot "libs\sam3.cpp\source"
	}
	return $env:OFXGGML_SAM3_CPP_DIR
}

function Get-SamCppPackageDir {
	return Join-Path $addonRoot "libs\sam.cpp"
}

function Get-Sam3CppPackageDir {
	return Join-Path $addonRoot "libs\sam3.cpp"
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
$selectedBackend = Normalize-Backend $Backend
if ($selectedBackend -in @("external-sam", "sam.cpp", "sam3.cpp")) {
	$checks += New-Check "OK" "selected backend" $selectedBackend
} else {
	$checks += New-Check "WARN" "selected backend" "unknown backend '$Backend'; expected external-sam, sam.cpp, or sam3.cpp"
}

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

$checks += Test-PathCheck `
	-Path (Join-Path $addonRoot "src\ofxGgmlSam\ofxGgmlSamCppAdapters.h") `
	-Name "sam.cpp adapter header" `
	-MissingDetail "sam.cpp adapter header is missing"

$checks += Test-PathCheck `
	-Path (Join-Path $addonRoot "src\ofxGgmlSam\ofxGgmlSam3Adapters.h") `
	-Name "sam3.cpp adapter header" `
	-MissingDetail "sam3.cpp adapter header is missing"

switch ($selectedBackend) {
	"external-sam" {
		$checks += Test-ConfiguredFile `
			-Path $AdapterExecutable `
			-Name "SAM adapter executable" `
			-Hint "set OFXGGML_SAM_EXECUTABLE or pass -AdapterExecutable"
	}
	"sam.cpp" {
		$samCppSourceDir = Get-SamCppSourceDir
		$checks += Test-PathCheck `
			-Path (Join-Path $samCppSourceDir "sam.h") `
			-Name "sam.cpp local checkout" `
			-MissingDetail "run scripts\install-sam-cpp.bat before enabling OFXGGML_ENABLE_SAMCPP_ADAPTER"
		$checks += Test-PathCheck `
			-Path (Join-Path (Get-SamCppPackageDir) "include\sam.h") `
			-Name "sam.cpp package header" `
			-MissingDetail "run scripts\install-sam-cpp.bat to populate libs\sam.cpp"
	}
	"sam3.cpp" {
		$sam3CppSourceDir = Get-Sam3CppSourceDir
		$checks += Test-PathCheck `
			-Path (Join-Path $sam3CppSourceDir "sam3.h") `
			-Name "sam3.cpp local checkout" `
			-MissingDetail "run scripts\install-sam3-cpp.bat before enabling OFXGGML_ENABLE_SAM3_ADAPTER"
		$checks += Test-PathCheck `
			-Path (Join-Path (Get-Sam3CppPackageDir) "include\sam3.h") `
			-Name "sam3.cpp package header" `
			-MissingDetail "run scripts\install-sam3-cpp.bat to populate libs\sam3.cpp"

		$checks += Test-PathCheck `
			-Path (Join-Path $sam3CppSourceDir "build-cpu") `
			-Name "sam3.cpp CPU build" `
			-MissingDetail "run scripts\build-sam3-cpp.bat -CpuOnly" `
			-Directory
	}
}

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
