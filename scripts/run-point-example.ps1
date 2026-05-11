param(
	[switch]$Build,
	[switch]$DryRun,
	[string]$Configuration = "Release",
	[string]$Platform = "x64"
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

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonRoot = Split-Path -Parent $scriptRoot
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
	$msbuild = Get-MsBuild
	if ([string]::IsNullOrWhiteSpace($msbuild)) {
		throw "MSBuild.exe was not found."
	}
	Write-Step "Building $exampleName $Configuration $Platform"
	& $msbuild $projectPath /t:Build /p:Configuration=$Configuration /p:Platform=$Platform /p:TrackFileAccess=false /p:MultiProcessorCompilation=false /m:1 /nr:false
	if ($LASTEXITCODE -ne 0) {
		throw "MSBuild $exampleName failed with exit code $LASTEXITCODE"
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
