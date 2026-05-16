param(
	[switch]$Build,
	[switch]$DryRun,
	[switch]$RepairProject,
	[string]$Configuration = "Release",
	[string]$Platform = "x64",
	[int]$Jobs = 1
)

$ErrorActionPreference = "Stop"

function Write-Step {
	param([string]$Message)
	Write-Output "==> $Message"
}

function Get-MsBuild {
	$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
	if (Test-Path -LiteralPath $vswhere) {
		$installPath = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -property installationPath 2>$null
		if ($installPath) {
			$candidate = Join-Path $installPath "MSBuild\Current\Bin\MSBuild.exe"
			if (Test-Path -LiteralPath $candidate) {
				return $candidate
			}
		}
	}

	foreach ($version in @("18", "17", "16")) {
		foreach ($edition in @("Community", "Professional", "Enterprise", "BuildTools")) {
			$candidate = "C:\Program Files\Microsoft Visual Studio\$version\$edition\MSBuild\Current\Bin\MSBuild.exe"
			if (Test-Path -LiteralPath $candidate) {
				return $candidate
			}
		}
	}
	return ""
}

function Get-StableNameFragment {
	param([string]$Text)
	$sha1 = [System.Security.Cryptography.SHA1]::Create()
	try {
		$bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
		$hash = $sha1.ComputeHash($bytes)
		return [System.BitConverter]::ToString($hash).Replace("-", "")
	} finally {
		$sha1.Dispose()
	}
}

function Invoke-WithNamedMutex {
	param(
		[string]$Name,
		[scriptblock]$Command
	)
	$mutex = New-Object System.Threading.Mutex($false, $Name)
	$locked = $false
	try {
		$locked = $mutex.WaitOne([TimeSpan]::FromMinutes(30))
		if (!$locked) {
			throw "Timed out waiting for build lock: $Name"
		}
		& $Command
	} finally {
		if ($locked) {
			$mutex.ReleaseMutex()
		}
		$mutex.Dispose()
	}
}

function Resolve-BuildJobs {
	param([int]$RequestedJobs)
	if ($RequestedJobs -lt 0) {
		throw "-Jobs must be 0 or greater."
	}
	if ($RequestedJobs -eq 0) {
		return [Environment]::ProcessorCount
	}
	return $RequestedJobs
}

function Get-MsBuildParallelArguments {
	param([int]$BuildJobs)
	if ($BuildJobs -gt 1) {
		return @("/p:MultiProcessorCompilation=true", "/m:$BuildJobs")
	}
	return @("/p:MultiProcessorCompilation=false", "/m:1")
}

function Test-GeneratedProjectWiring {
	param([string]$ProjectPath)

	$content = Get-Content -LiteralPath $ProjectPath -Raw
	$missing = @()
	foreach ($expected in @(
		"..\src",
		"..\..\ofxGgmlCore\src",
		"..\..\ofxImGui\src",
		"..\libs\sam3.cpp\include",
		"OFXGGML_ENABLE_SAM3_ADAPTER"
	)) {
		if ($content -notlike "*$expected*") {
			$missing += $expected
		}
	}
	return $missing
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonRoot = Split-Path -Parent $scriptRoot
$ofRoot = Split-Path -Parent (Split-Path -Parent $addonRoot)
$exampleName = "ofxGgmlSamPointExample"
$exampleRoot = Join-Path $addonRoot $exampleName
$exeSuffix = if ($IsLinux -or $IsMacOS) { "" } else { ".exe" }
$exampleExe = Join-Path $exampleRoot "bin\$exampleName$exeSuffix"
$projectPath = Join-Path $exampleRoot "$exampleName.vcxproj"

if (!(Test-Path -LiteralPath $exampleRoot -PathType Container)) {
	throw "Point example directory was not found: $exampleRoot"
}

if ($Build) {
	if ($IsLinux -or $IsMacOS) {
		throw "-Build is currently implemented for generated Visual Studio projects only."
	}
	if (!(Test-Path -LiteralPath $projectPath -PathType Leaf)) {
		throw "Visual Studio project was not found: $projectPath. Generate it with openFrameworks projectGenerator using addons ofxGgmlCore and ofxGgmlSam."
	}
	$missingWiring = Test-GeneratedProjectWiring -ProjectPath $projectPath
	if ($missingWiring.Count -gt 0) {
		if ($RepairProject) {
			& (Join-Path $scriptRoot "repair-point-example-vsproj.ps1") -ProjectPath $projectPath
			$missingWiring = Test-GeneratedProjectWiring -ProjectPath $projectPath
		}
		if ($missingWiring.Count -gt 0) {
			throw "Visual Studio project is missing addon include wiring for: $($missingWiring -join ', '). Regenerate it with openFrameworks projectGenerator using addons ofxGgmlCore, ofxGgmlSam, and ofxImGui, or run scripts\repair-point-example-vsproj.bat."
		}
	}
	$msbuild = Get-MsBuild
	if ([string]::IsNullOrWhiteSpace($msbuild)) {
		throw "MSBuild.exe was not found."
	}
	$buildJobs = Resolve-BuildJobs -RequestedJobs $Jobs
	$parallelArgs = Get-MsBuildParallelArguments -BuildJobs $buildJobs
	Write-Step "Building $exampleName $Configuration $Platform with MSBuild ($buildJobs jobs)"
	$lockName = "Local\ofxGgml-msbuild-" + (Get-StableNameFragment $ofRoot)
	Invoke-WithNamedMutex -Name $lockName -Command {
		& $msbuild $projectPath /t:Build /p:Configuration=$Configuration /p:Platform=$Platform /p:TrackFileAccess=false @parallelArgs /nr:false
		if ($LASTEXITCODE -ne 0) {
			throw "MSBuild $exampleName failed with exit code $LASTEXITCODE"
		}
	}
}

if (!(Test-Path -LiteralPath $exampleExe -PathType Leaf)) {
	if ($DryRun) {
		Write-Warning "Point example executable was not found: $exampleExe"
	} else {
		throw "Point example executable was not found: $exampleExe. Generate/build the example first, or rerun with -DryRun to inspect paths."
	}
}

if ($DryRun) {
	Write-Step "Example:    $exampleName"
	Write-Step "Root:       $exampleRoot"
	Write-Step "Executable: $exampleExe"
	Write-Step "Project:    $projectPath"
	return
}

Write-Step "Starting $exampleName"
& $exampleExe
exit $LASTEXITCODE
