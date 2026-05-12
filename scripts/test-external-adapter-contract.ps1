param(
	[string]$Configuration = "Release",
	[string]$BuildRoot = "",
	[switch]$Clean,
	[switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Write-Step {
	param([string]$Message)
	Write-Host "==> $Message"
}

function Test-WindowsHost {
	return !($IsLinux -or $IsMacOS)
}

function Convert-ToCmdArgument {
	param([string]$Value)
	return '"' + ($Value -replace '"', '""') + '"'
}

function Invoke-CheckedCmd {
	param(
		[string]$Step,
		[string]$Command
	)
	& cmd.exe /d /s /c $Command
	if ($LASTEXITCODE -ne 0) {
		throw "$Step failed with exit code $LASTEXITCODE"
	}
}

function Invoke-CheckedNative {
	param(
		[string]$Step,
		[scriptblock]$Command
	)
	& $Command
	if ($LASTEXITCODE -ne 0) {
		throw "$Step failed with exit code $LASTEXITCODE"
	}
}

function Get-VisualStudioDevCmd {
	$candidates = New-Object System.Collections.Generic.List[string]
	$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
	if (Test-Path -LiteralPath $vswhere) {
		$installPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
		if ($installPath) {
			$candidates.Add((Join-Path $installPath "Common7\Tools\VsDevCmd.bat"))
		}
	}

	foreach ($version in @("18", "17", "16")) {
		foreach ($edition in @("Community", "Professional", "Enterprise", "BuildTools")) {
			$candidates.Add("C:\Program Files\Microsoft Visual Studio\$version\$edition\Common7\Tools\VsDevCmd.bat")
			$candidates.Add("C:\Program Files (x86)\Microsoft Visual Studio\$version\$edition\Common7\Tools\VsDevCmd.bat")
		}
	}

	foreach ($candidate in $candidates) {
		if (Test-Path -LiteralPath $candidate) {
			return $candidate
		}
	}
	return ""
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonRoot = Resolve-Path (Join-Path $scriptRoot "..")
$adapterDir = Join-Path $addonRoot "tools\ofxGgmlSamMockAdapter"
$testsDir = Join-Path $addonRoot "tests"
if ([string]::IsNullOrWhiteSpace($BuildRoot)) {
	$BuildRoot = Join-Path ([System.IO.Path]::GetTempPath()) "sam-contract"
}
$adapterBuildDir = Join-Path $BuildRoot "adapter"
$testBuildDir = Join-Path $BuildRoot "tests"
$adapterExe = if (Test-WindowsHost) {
	Join-Path $adapterBuildDir "ofxGgmlSamMockAdapter.exe"
} else {
	Join-Path $adapterBuildDir "ofxGgmlSamMockAdapter"
}
$contractExe = if (Test-WindowsHost) {
	Join-Path $testBuildDir "sam_adapter_contract.exe"
} else {
	Join-Path $testBuildDir "sam_adapter_contract"
}

if ($DryRun) {
	Write-Step "External SAM adapter contract plan"
	Write-Host "  adapter source: $adapterDir"
	Write-Host "  tests source: $testsDir"
	Write-Host "  build root: $BuildRoot"
	Write-Host "  adapter exe: $adapterExe"
	Write-Host "  contract exe: $contractExe"
	Write-Host "  clean: $(if ($Clean) { 'ON' } else { 'OFF' })"
	Write-Step "Dry run complete; no files were changed"
	return
}

if ($Clean -and (Test-Path -LiteralPath $BuildRoot)) {
	Write-Step "Cleaning $BuildRoot"
	Remove-Item -LiteralPath $BuildRoot -Recurse -Force
}

if (Test-WindowsHost) {
	$vsDevCmd = Get-VisualStudioDevCmd
	if ([string]::IsNullOrWhiteSpace($vsDevCmd)) {
		throw "Visual Studio C++ build tools were not found."
	}

	$configureAdapter = "cmake -S $(Convert-ToCmdArgument $adapterDir) -B $(Convert-ToCmdArgument $adapterBuildDir) -G $(Convert-ToCmdArgument "NMake Makefiles") -DCMAKE_BUILD_TYPE=$Configuration"
	$buildAdapter = "cmake --build $(Convert-ToCmdArgument $adapterBuildDir)"
	$configureTests = "cmake -S $(Convert-ToCmdArgument $testsDir) -B $(Convert-ToCmdArgument $testBuildDir) -G $(Convert-ToCmdArgument "NMake Makefiles") -DCMAKE_BUILD_TYPE=$Configuration -DOFXGGMLSAM_BUILD_EXTERNAL_ADAPTER_CONTRACT=ON"
	$buildTests = "cmake --build $(Convert-ToCmdArgument $testBuildDir) --target sam_adapter_contract"
	$run = "$(Convert-ToCmdArgument $contractExe) $(Convert-ToCmdArgument $adapterExe)"
	$command = "call $(Convert-ToCmdArgument $vsDevCmd) -arch=x64 -host_arch=x64 >nul && $configureAdapter && $buildAdapter && $configureTests && $buildTests && $run"
	Write-Step "Building and running external SAM adapter contract with Visual Studio tools"
	Invoke-CheckedCmd "external SAM adapter contract" $command
} else {
	Write-Step "Building mock SAM adapter"
	Invoke-CheckedNative "configure mock SAM adapter" {
		cmake -S $adapterDir -B $adapterBuildDir -DCMAKE_BUILD_TYPE=$Configuration
	}
	Invoke-CheckedNative "build mock SAM adapter" {
		cmake --build $adapterBuildDir --config $Configuration
	}
	Write-Step "Building external SAM adapter contract test"
	Invoke-CheckedNative "configure external SAM adapter contract" {
		cmake -S $testsDir -B $testBuildDir -DCMAKE_BUILD_TYPE=$Configuration -DOFXGGMLSAM_BUILD_EXTERNAL_ADAPTER_CONTRACT=ON
	}
	Invoke-CheckedNative "build external SAM adapter contract" {
		cmake --build $testBuildDir --target sam_adapter_contract --config $Configuration
	}
	Write-Step "Running external SAM adapter contract"
	Invoke-CheckedNative "external SAM adapter contract" {
		& $contractExe $adapterExe
	}
}
