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
$batchDir = Join-Path $addonRoot "tools\ofxGgmlSamBatchExternal"
$fixturePath = Join-Path $addonRoot "tests\fixtures\sam-point-square.ppm"
if ([string]::IsNullOrWhiteSpace($BuildRoot)) {
	$BuildRoot = Join-Path ([System.IO.Path]::GetTempPath()) "sam-batch"
}
$adapterBuildDir = Join-Path $BuildRoot "adapter"
$batchBuildDir = Join-Path $BuildRoot "batch"
$inputDir = Join-Path $BuildRoot "inputs"
$outputDir = Join-Path $BuildRoot "masks"
$adapterExe = if (Test-WindowsHost) {
	Join-Path $adapterBuildDir "ofxGgmlSamMockAdapter.exe"
} else {
	Join-Path $adapterBuildDir "ofxGgmlSamMockAdapter"
}
$batchExe = if (Test-WindowsHost) {
	Join-Path $batchBuildDir "ofxGgmlSamBatchExternal.exe"
} else {
	Join-Path $batchBuildDir "ofxGgmlSamBatchExternal"
}

if ($DryRun) {
	Write-Step "External SAM batch plan"
	Write-Host "  adapter source: $adapterDir"
	Write-Host "  batch source: $batchDir"
	Write-Host "  fixture: $fixturePath"
	Write-Host "  build root: $BuildRoot"
	Write-Host "  adapter exe: $adapterExe"
	Write-Host "  batch exe: $batchExe"
	Write-Host "  output dir: $outputDir"
	Write-Host "  clean: $(if ($Clean) { 'ON' } else { 'OFF' })"
	Write-Step "Dry run complete; no files were changed"
	return
}

if (!(Test-Path -LiteralPath $fixturePath -PathType Leaf)) {
	throw "Batch fixture was not found: $fixturePath"
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
	$configureBatch = "cmake -S $(Convert-ToCmdArgument $batchDir) -B $(Convert-ToCmdArgument $batchBuildDir) -G $(Convert-ToCmdArgument "NMake Makefiles") -DCMAKE_BUILD_TYPE=$Configuration"
	$buildBatch = "cmake --build $(Convert-ToCmdArgument $batchBuildDir)"
	$command = "call $(Convert-ToCmdArgument $vsDevCmd) -arch=x64 -host_arch=x64 >nul && $configureAdapter && $buildAdapter && $configureBatch && $buildBatch"
	Write-Step "Building external SAM batch tool with Visual Studio tools"
	Invoke-CheckedCmd "external SAM batch build" $command
} else {
	Write-Step "Building mock SAM adapter"
	Invoke-CheckedNative "configure mock SAM adapter" {
		cmake -S $adapterDir -B $adapterBuildDir -DCMAKE_BUILD_TYPE=$Configuration
	}
	Invoke-CheckedNative "build mock SAM adapter" {
		cmake --build $adapterBuildDir --config $Configuration
	}
	Write-Step "Building external SAM batch tool"
	Invoke-CheckedNative "configure external SAM batch tool" {
		cmake -S $batchDir -B $batchBuildDir -DCMAKE_BUILD_TYPE=$Configuration
	}
	Invoke-CheckedNative "build external SAM batch tool" {
		cmake --build $batchBuildDir --config $Configuration
	}
}

Write-Step "Preparing batch fixture inputs"
New-Item -ItemType Directory -Force -Path $inputDir | Out-Null
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
Copy-Item -LiteralPath $fixturePath -Destination (Join-Path $inputDir "square-a.ppm") -Force
Copy-Item -LiteralPath $fixturePath -Destination (Join-Path $inputDir "square-b.ppm") -Force

Write-Step "Checking external SAM batch dry-run"
$dryRunOutput = & $batchExe `
	--input-dir $inputDir `
	--output-dir $outputDir `
	--point-x 0.5 `
	--point-y 0.5 `
	--dry-run `
	--json 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
	throw "External SAM batch dry-run failed with exit code $LASTEXITCODE`n$dryRunOutput"
}
$dryRunSummary = $dryRunOutput | ConvertFrom-Json
if ($dryRunSummary.name -ne "ofxGgmlSam external batch plan" -or
	!$dryRunSummary.dryRun -or
	$dryRunSummary.inputCount -ne 2) {
	throw "External SAM batch dry-run JSON summary was unexpected:`n$dryRunOutput"
}

Write-Step "Running external SAM batch smoke"
$batchOutput = & $batchExe `
	--adapter $adapterExe `
	--input-dir $inputDir `
	--output-dir $outputDir `
	--point-x 0.5 `
	--point-y 0.5 `
	--json 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
	throw "External SAM batch smoke failed with exit code $LASTEXITCODE`n$batchOutput"
}
$summary = $batchOutput | ConvertFrom-Json
if ($summary.name -ne "ofxGgmlSam external batch" -or $summary.count -ne 2) {
	throw "External SAM batch JSON summary was unexpected:`n$batchOutput"
}
foreach ($item in $summary.items) {
	if (!$item.success -or $item.maskCount -lt 1) {
		throw "External SAM batch item failed:`n$batchOutput"
	}
	if (!(Test-Path -LiteralPath $item.maskPath -PathType Leaf)) {
		throw "External SAM batch mask was not written: $($item.maskPath)"
	}
}
Write-Step "External SAM batch smoke passed"
