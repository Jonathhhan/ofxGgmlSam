param(
	[string] $Model = $env:OFXGGML_SAM_MODEL,
	[ValidateSet("cpu", "cuda")]
	[string] $Backend = $(if ([string]::IsNullOrWhiteSpace($env:OFXGGML_SAM_RUNTIME_BACKEND)) { "cpu" } else { $env:OFXGGML_SAM_RUNTIME_BACKEND }),
	[int] $Threads = 0,
	[int] $ImageSize = 256,
	[string] $Image = "",
	[string] $Configuration = "Release",
	[string] $BuildDir = "",
	[string] $OutputPath = "",
	[switch] $SkipBuild,
	[switch] $BuildOnly,
	[switch] $DryRun,
	[switch] $Json,
	[switch] $SummaryOnly
)

$ErrorActionPreference = "Stop"

function Write-Step {
	param([string] $Message)
	if (-not $Json) {
		Write-Host "==> $Message"
	}
}

function Test-WindowsHost {
	return !($IsLinux -or $IsMacOS)
}

function Convert-ToCmdArgument {
	param([string] $Value)
	return '"' + ($Value -replace '"', '""') + '"'
}

function Invoke-CheckedNative {
	param(
		[string] $Step,
		[scriptblock] $Command
	)
	& $Command
	if ($LASTEXITCODE -ne 0) {
		throw "$Step failed with exit code $LASTEXITCODE"
	}
}

function Invoke-CheckedCmd {
	param(
		[string] $Step,
		[string] $Command
	)
	& cmd.exe /d /s /c $Command
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

function Find-DefaultModel {
	param([string] $AddonRoot)

	$searchRoots = @(
		(Join-Path $AddonRoot "ofxGgmlSamPointExample\bin\data\models"),
		(Join-Path $AddonRoot "models"),
		(Join-Path (Split-Path -Parent $AddonRoot) "models")
	)
	foreach ($root in $searchRoots) {
		if (-not (Test-Path -LiteralPath $root -PathType Container)) {
			continue
		}
		$candidate = Get-ChildItem -LiteralPath $root -File -ErrorAction SilentlyContinue |
			Where-Object {
				$_.Extension -ieq ".ggml" -and
				$_.Name -match "(sam3|sam2|edgetam)"
			} |
			Sort-Object Name |
			Select-Object -First 1
		if ($candidate) {
			return $candidate.FullName
		}
	}
	return ""
}

function Get-SmokeExecutable {
	param(
		[string] $BuildDir,
		[string] $Configuration
	)

	$candidates = @(
		(Join-Path $BuildDir "ofxGgmlSam3RuntimeSmoke.exe"),
		(Join-Path $BuildDir "$Configuration\ofxGgmlSam3RuntimeSmoke.exe")
	)
	foreach ($candidate in $candidates) {
		if (Test-Path -LiteralPath $candidate -PathType Leaf) {
			return $candidate
		}
	}
	return $candidates[0]
}

function Build-SmokeTool {
	param(
		[string] $ToolDir,
		[string] $BuildDir,
		[string] $Configuration,
		[bool] $Quiet
	)

	if (Test-WindowsHost) {
		$vsDevCmd = Get-VisualStudioDevCmd
		if ([string]::IsNullOrWhiteSpace($vsDevCmd)) {
			throw "Visual Studio C++ build tools were not found."
		}
		$quietRedirect = if ($Quiet) { " >nul" } else { "" }
		$configure = "cmake -S $(Convert-ToCmdArgument $ToolDir) -B $(Convert-ToCmdArgument $BuildDir) -G $(Convert-ToCmdArgument "NMake Makefiles") -DCMAKE_BUILD_TYPE=$Configuration$quietRedirect"
		$build = "cmake --build $(Convert-ToCmdArgument $BuildDir)$quietRedirect"
		$command = "call $(Convert-ToCmdArgument $vsDevCmd) -arch=x64 -host_arch=x64 >nul && $configure && $build"
		Invoke-CheckedCmd "SAM3 runtime smoke build" $command
	} else {
		if ($Quiet) {
			$configureOutput = & cmake -S $ToolDir -B $BuildDir -DCMAKE_BUILD_TYPE=$Configuration 2>&1
			if ($LASTEXITCODE -ne 0) {
				$configureOutput | Write-Error
				throw "cmake configure SAM3 runtime smoke failed with exit code $LASTEXITCODE"
			}
			$buildOutput = & cmake --build $BuildDir --config $Configuration 2>&1
			if ($LASTEXITCODE -ne 0) {
				$buildOutput | Write-Error
				throw "cmake build SAM3 runtime smoke failed with exit code $LASTEXITCODE"
			}
		} else {
			Invoke-CheckedNative "cmake configure SAM3 runtime smoke" {
				cmake -S $ToolDir -B $BuildDir -DCMAKE_BUILD_TYPE=$Configuration
			}
			Invoke-CheckedNative "cmake build SAM3 runtime smoke" {
				cmake --build $BuildDir --config $Configuration
			}
		}
	}
}

function ConvertTo-PlanJson {
	param([hashtable] $Plan)
	return ($Plan | ConvertTo-Json -Depth 5)
}

function Write-SmokeOutputPath {
	param(
		[string] $Path,
		[string] $Content
	)
	if ([string]::IsNullOrWhiteSpace($Path)) {
		return
	}
	$target = if ([System.IO.Path]::IsPathRooted($Path)) {
		$Path
	} else {
		Join-Path $addonRoot $Path
	}
	$directory = Split-Path -Parent $target
	if (!(Test-Path -LiteralPath $directory -PathType Container)) {
		New-Item -ItemType Directory -Path $directory -Force | Out-Null
	}
	Set-Content -LiteralPath $target -Value $Content
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonRoot = Resolve-Path (Join-Path $scriptRoot "..")
$toolDir = Join-Path $addonRoot "tools\ofxGgmlSam3RuntimeSmoke"
if ([string]::IsNullOrWhiteSpace($BuildDir)) {
	$BuildDir = Join-Path $addonRoot "build\sam3-runtime-smoke"
}
if (-not [string]::IsNullOrWhiteSpace($Image)) {
	$Image = [Environment]::ExpandEnvironmentVariables($Image)
	if (-not [System.IO.Path]::IsPathRooted($Image)) {
		$Image = Join-Path $addonRoot $Image
	}
}

if (-not [string]::IsNullOrWhiteSpace($Model)) {
	$Model = [Environment]::ExpandEnvironmentVariables($Model)
}
if ([string]::IsNullOrWhiteSpace($Model)) {
	$Model = Find-DefaultModel -AddonRoot $addonRoot
}

$exePath = Get-SmokeExecutable -BuildDir $BuildDir -Configuration $Configuration
$plan = @{
	Name = "ofxGgmlSam SAM3 runtime smoke"
	Root = $addonRoot.Path
	Tool = $toolDir
	BuildDir = $BuildDir
	Executable = $exePath
	Backend = $Backend
	Model = $Model
	Image = $Image
	Threads = $Threads
	ImageSize = $ImageSize
	Ready = -not [string]::IsNullOrWhiteSpace($Model)
	SmokeKind = "model-backed-sam3-point-segmentation"
	InferenceCheck = "dry-run"
	InferenceChecked = $false
	NextCommands = @(
		"scripts\run-sam3-runtime-smoke.bat -DryRun",
		"scripts\run-sam3-runtime-smoke.bat -Backend cpu -Json -SummaryOnly",
		"scripts\run-sam3-runtime-smoke.bat -Backend cuda -Json -SummaryOnly",
		"scripts\run-sam3-runtime-smoke.bat -Backend cpu -Json -SummaryOnly -OutputPath .sam3-runtime-smoke.json",
		"scripts\run-sam3-runtime-smoke.bat -Backend cuda -Json -SummaryOnly -OutputPath .sam3-runtime-smoke.json"
	)
}

if ($DryRun) {
	if ($Json) {
		$content = ConvertTo-PlanJson -Plan $plan
		Write-SmokeOutputPath -Path $OutputPath -Content $content
		$content
	} else {
		Write-Host "ofxGgmlSam SAM3 runtime smoke plan"
		Write-Host "Tool:       $toolDir"
		Write-Host "BuildDir:   $BuildDir"
		Write-Host "Executable: $exePath"
		Write-Host "Backend:    $Backend"
		Write-Host "Model:      $Model"
		Write-Host "Image:      $Image"
		Write-Host "Ready:      $($plan.Ready)"
		Write-Host "Next:       scripts\run-sam3-runtime-smoke.bat -Backend $Backend -Json -SummaryOnly"
	}
	exit 0
}

if ([string]::IsNullOrWhiteSpace($Model)) {
	throw "No SAM3 model was found. Set OFXGGML_SAM_MODEL or place a .ggml model under ofxGgmlSamPointExample\bin\data\models."
}

if (-not $SkipBuild) {
	Write-Step "Building SAM3 runtime smoke tool"
	Build-SmokeTool -ToolDir $toolDir -BuildDir $BuildDir -Configuration $Configuration -Quiet:$Json.IsPresent
}

$exePath = Get-SmokeExecutable -BuildDir $BuildDir -Configuration $Configuration
if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
	throw "SAM3 runtime smoke executable was not found: $exePath"
}

if ($BuildOnly) {
	if ($Json) {
		$plan.Executable = $exePath
		$plan.BuildOnly = $true
		$content = ConvertTo-PlanJson -Plan $plan
		Write-SmokeOutputPath -Path $OutputPath -Content $content
		$content
	} else {
		Write-Host "SAM3 runtime smoke built: $exePath"
	}
	exit 0
}

$args = @(
	"--model", $Model,
	"--backend", $Backend,
	"--image-size", $ImageSize.ToString()
)
if (-not [string]::IsNullOrWhiteSpace($Image)) {
	$args += @("--image", $Image)
}
if ($Threads -gt 0) {
	$args += @("--threads", $Threads.ToString())
}
if ($Json) {
	$args += "--json"
}
if ($SummaryOnly) {
	$args += "--summary-only"
}

Write-Step "Running SAM3 runtime smoke"
if ($Json) {
	$previousErrorActionPreference = $ErrorActionPreference
	$ErrorActionPreference = "Continue"
	$smokeOutput = & $exePath @args 2>$null
	$smokeExitCode = $LASTEXITCODE
	$ErrorActionPreference = $previousErrorActionPreference
	$content = ($smokeOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
	Write-SmokeOutputPath -Path $OutputPath -Content $content
	if (![string]::IsNullOrWhiteSpace($content)) {
		Write-Output $content
	}
} else {
	& $exePath @args
	$smokeExitCode = $LASTEXITCODE
}
if ($smokeExitCode -ne 0) {
	throw "SAM3 runtime smoke failed with exit code $smokeExitCode"
}
