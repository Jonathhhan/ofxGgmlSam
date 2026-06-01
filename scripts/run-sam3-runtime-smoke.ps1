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
	[switch] $SummaryOnly,
	[switch] $CacheVerify,
	[switch] $FixtureVerify,
	[switch] $BoxPrompt,
	[switch] $BoxVerify
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
	param([string] $Step, [scriptblock] $Command)
	& $Command
	if ($LASTEXITCODE -ne 0) { throw "$Step failed with exit code $LASTEXITCODE" }
}

function Invoke-CheckedCmd {
	param([string] $Step, [string] $Command)
	& cmd.exe /d /s /c $Command
	if ($LASTEXITCODE -ne 0) { throw "$Step failed with exit code $LASTEXITCODE" }
}

function Get-VisualStudioDevCmd {
	$candidates = New-Object System.Collections.Generic.List[string]
	$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
	if (Test-Path -LiteralPath $vswhere) {
		$installPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
		if ($installPath) { $candidates.Add((Join-Path $installPath "Common7\Tools\VsDevCmd.bat")) }
	}
	foreach ($version in @("18", "17", "16")) {
		foreach ($edition in @("Community", "Professional", "Enterprise", "BuildTools")) {
			$candidates.Add("C:\Program Files\Microsoft Visual Studio\$version\$edition\Common7\Tools\VsDevCmd.bat")
			$candidates.Add("C:\Program Files (x86)\Microsoft Visual Studio\$version\$edition\Common7\Tools\VsDevCmd.bat")
		}
	}
	foreach ($candidate in $candidates) {
		if (Test-Path -LiteralPath $candidate) { return $candidate }
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
		if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
		$candidate = Get-ChildItem -LiteralPath $root -File -ErrorAction SilentlyContinue |
			Where-Object { $_.Extension -ieq ".ggml" -and $_.Name -match "(sam3|sam2|edgetam)" } |
			Sort-Object Name | Select-Object -First 1
		if ($candidate) { return $candidate.FullName }
	}
	return ""
}

function Get-SmokeExecutable {
	param([string] $BuildDir, [string] $Configuration)
	$candidates = @(
		(Join-Path $BuildDir "ofxGgmlSam3RuntimeSmoke.exe"),
		(Join-Path $BuildDir "$Configuration\ofxGgmlSam3RuntimeSmoke.exe")
	)
	foreach ($candidate in $candidates) {
		if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
	}
	return $candidates[0]
}

function Build-SmokeTool {
	param([string] $ToolDir, [string] $BuildDir, [string] $Configuration, [bool] $Quiet)
	if (Test-WindowsHost) {
		$vsDevCmd = Get-VisualStudioDevCmd
		if ([string]::IsNullOrWhiteSpace($vsDevCmd)) { throw "Visual Studio C++ build tools were not found." }
		$quietRedirect = if ($Quiet) { " >nul" } else { "" }
		$configure = "cmake -S $(Convert-ToCmdArgument $ToolDir) -B $(Convert-ToCmdArgument $BuildDir) -G $(Convert-ToCmdArgument "NMake Makefiles") -DCMAKE_BUILD_TYPE=$Configuration$quietRedirect"
		$build = "cmake --build $(Convert-ToCmdArgument $BuildDir)$quietRedirect"
		$command = "call $(Convert-ToCmdArgument $vsDevCmd) -arch=x64 -host_arch=x64 >nul && $configure && $build"
		Invoke-CheckedCmd "SAM3 runtime smoke build" $command
	} else {
		if ($Quiet) {
			$out = & cmake -S $ToolDir -B $BuildDir -DCMAKE_BUILD_TYPE=$Configuration 2>&1
			if ($LASTEXITCODE -ne 0) { $out | Write-Error; throw "cmake configure failed" }
			$out = & cmake --build $BuildDir --config $Configuration 2>&1
			if ($LASTEXITCODE -ne 0) { $out | Write-Error; throw "cmake build failed" }
		} else {
			Invoke-CheckedNative "cmake configure" { cmake -S $ToolDir -B $BuildDir -DCMAKE_BUILD_TYPE=$Configuration }
			Invoke-CheckedNative "cmake build" { cmake --build $BuildDir --config $Configuration }
		}
	}
}

function Classify-Failure {
	param([string] $ErrorMessage, [string] $ModelPath, [string] $Backend)
	if ([string]::IsNullOrWhiteSpace($ErrorMessage)) { return "none" }
	$lower = $ErrorMessage.ToLowerInvariant()
	if ($lower -match "no sam3 model|model was not found|could not open.*model|--model is required") {
		return "missing_model"
	}
	if ($lower -match "wrong.*extension|extension.*mismatch|\.gguf.*sam3|expected.*\.ggml") {
		return "wrong_extension"
	}
	if ($lower -match "sam3\.h was not found|sam3\.cpp|runtime.*not found|lib.*not found|build tools.*not found") {
		return "missing_runtime"
	}
	if ($lower -match "build.*failed|cmake.*failed|compile.*failed|link.*failed|vsdevcmd") {
		return "build_failure"
	}
	if ($lower -match "cuda.*mismatch|ggml.*mismatch|cuda.*not found|cudart|cublas.*not found|backend.*cuda.*not.*available") {
		return "cuda_mismatch"
	}
	if ($lower -match "executable.*not found|not found.*exe") {
		return "missing_runtime"
	}
	if ($lower -match "sam3_load_model|sam3_create_state|sam3_encode_image|sam3_segment_pvs|returned null|produced no detections") {
		return "runtime_execution_failure"
	}
	return "runtime_execution_failure"
}

function ConvertTo-PlanJson {
	param([hashtable] $Plan)
	return ($Plan | ConvertTo-Json -Depth 5)
}

function Write-SmokeOutputPath {
	param([string] $Path, [string] $Content)
	if ([string]::IsNullOrWhiteSpace($Path)) { return }
	$target = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $addonRoot $Path }
	$directory = Split-Path -Parent $target
	if (!(Test-Path -LiteralPath $directory -PathType Container)) {
		New-Item -ItemType Directory -Path $directory -Force | Out-Null
	}
	Set-Content -LiteralPath $target -Value $Content
}

function Get-ModelFamilyHint {
	param([string] $Name)
	if ($Name -match "edgetam") { return "edgetam" }
	if ($Name -match "sam3") { return "sam3" }
	if ($Name -match "sam2") { return "sam2" }
	return "unknown"
}

function Get-RequiredNumber {
	param([object] $Object, [string] $Name)
	$property = $Object.PSObject.Properties[$Name]
	if ($null -eq $property -or $null -eq $property.Value) {
		throw "missing numeric field: $Name"
	}
	$value = [double] $property.Value
	if ([double]::IsNaN($value) -or [double]::IsInfinity($value)) {
		throw "non-finite numeric field: $Name"
	}
	return $value
}

function Test-FixtureSmokeResult {
	param([object] $Result, [string] $ImagePath)
	if ($null -eq $Result -or $null -eq $Result.Summary) {
		throw "fixture output check requires parsed SAM3 smoke JSON"
	}
	if ([string]::IsNullOrWhiteSpace($ImagePath)) {
		throw "fixture output check requires -Image tests\fixtures\sam-point-square.ppm"
	}
	if ([System.IO.Path]::GetFileName($ImagePath) -ne "sam-point-square.ppm") {
		throw "fixture output check only supports sam-point-square.ppm"
	}

	$summary = $Result.Summary
	if (-not $summary.Passed -or -not $summary.InferenceChecked) {
		throw "fixture output check requires a passing inference result"
	}

	$maskCount = Get-RequiredNumber -Object $summary -Name "MaskCount"
	$maskWidth = Get-RequiredNumber -Object $summary -Name "FirstMaskWidth"
	$maskHeight = Get-RequiredNumber -Object $summary -Name "FirstMaskHeight"
	$activePixels = Get-RequiredNumber -Object $summary -Name "FirstMaskActivePixels"
	$activeRatio = Get-RequiredNumber -Object $summary -Name "FirstMaskActiveRatio"
	$meanValue = Get-RequiredNumber -Object $summary -Name "FirstMaskMeanValue"
	$promptValue = Get-RequiredNumber -Object $summary -Name "FirstMaskPromptValue"
	$centerValue = Get-RequiredNumber -Object $summary -Name "FirstMaskCenterValue"

	if ($maskCount -lt 1) { throw "fixture output check expected at least one mask" }
	if ($maskWidth -lt 1 -or $maskHeight -lt 1) { throw "fixture output check received an invalid first-mask size" }
	if ($activePixels -lt 1) { throw "fixture output check expected active pixels in the first mask" }
	if ($activeRatio -le 0.0 -or $activeRatio -gt 0.98) {
		throw "fixture output check expected a non-empty, non-saturated first mask; active ratio was $activeRatio"
	}
	if ($meanValue -le 0.0 -or $meanValue -gt 1.0) {
		throw "fixture output check expected first-mask mean in (0, 1]; mean was $meanValue"
	}
	if ($promptValue -le 0.0) {
		throw "fixture output check expected the positive prompt pixel to be covered by the first mask"
	}
	if ($centerValue -le 0.0) {
		throw "fixture output check expected the fixture center to be covered by the first mask"
	}

	return [ordered] @{
		Checked = $true
		Image = $ImagePath
		MaskCount = [int] $maskCount
		FirstMaskWidth = [int] $maskWidth
		FirstMaskHeight = [int] $maskHeight
		FirstMaskActivePixels = [int] $activePixels
		FirstMaskActiveRatio = [math]::Round($activeRatio, 6)
		FirstMaskMeanValue = [math]::Round($meanValue, 6)
		FirstMaskPromptValue = [math]::Round($promptValue, 6)
		FirstMaskCenterValue = [math]::Round($centerValue, 6)
	}
}

function Test-BoxSmokeResult {
	param([object] $Result)
	if ($null -eq $Result -or $null -eq $Result.Summary) {
		throw "box output check requires parsed SAM3 smoke JSON"
	}
	$summary = $Result.Summary
	if (-not $summary.Passed -or -not $summary.InferenceChecked) {
		throw "box output check requires a passing inference result"
	}
	if ($summary.PromptKind -ne "box" -or -not $summary.BoxPrompt) {
		throw "box output check expected a box-prompt smoke result"
	}

	$maskCount = Get-RequiredNumber -Object $summary -Name "MaskCount"
	$maskWidth = Get-RequiredNumber -Object $summary -Name "FirstMaskWidth"
	$maskHeight = Get-RequiredNumber -Object $summary -Name "FirstMaskHeight"
	$activePixels = Get-RequiredNumber -Object $summary -Name "FirstMaskActivePixels"
	$activeRatio = Get-RequiredNumber -Object $summary -Name "FirstMaskActiveRatio"
	$centerValue = Get-RequiredNumber -Object $summary -Name "FirstMaskCenterValue"
	if ($maskCount -lt 1) { throw "box output check expected at least one mask" }
	if ($maskWidth -lt 1 -or $maskHeight -lt 1) { throw "box output check received an invalid first-mask size" }
	if ($activePixels -lt 1) { throw "box output check expected active pixels in the first mask" }
	if ($activeRatio -le 0.0 -or $activeRatio -gt 0.98) {
		throw "box output check expected a non-empty, non-saturated first mask; active ratio was $activeRatio"
	}
	if ($centerValue -le 0.0) {
		throw "box output check expected the default box center to be covered by the first mask"
	}

	return [ordered] @{
		Checked = $true
		MaskCount = [int] $maskCount
		FirstMaskWidth = [int] $maskWidth
		FirstMaskHeight = [int] $maskHeight
		FirstMaskActivePixels = [int] $activePixels
		FirstMaskActiveRatio = [math]::Round($activeRatio, 6)
		FirstMaskCenterValue = [math]::Round($centerValue, 6)
	}
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonRoot = Resolve-Path (Join-Path $scriptRoot "..")
$toolDir = Join-Path $addonRoot "tools\ofxGgmlSam3RuntimeSmoke"
if ([string]::IsNullOrWhiteSpace($BuildDir)) {
	$BuildDir = Join-Path $addonRoot "build\sam3-runtime-smoke"
}
if (-not [string]::IsNullOrWhiteSpace($Image)) {
	$Image = [Environment]::ExpandEnvironmentVariables($Image)
	if (-not [System.IO.Path]::IsPathRooted($Image)) { $Image = Join-Path $addonRoot $Image }
}
if (-not [string]::IsNullOrWhiteSpace($Model)) { $Model = [Environment]::ExpandEnvironmentVariables($Model) }
if ([string]::IsNullOrWhiteSpace($Model)) { $Model = Find-DefaultModel -AddonRoot $addonRoot }

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
	FixtureOutputCheck = "sam-point-square prompt-mask invariants"
	FixtureChecked = $false
	FixtureVerify = $FixtureVerify.IsPresent
	BoxPrompt = $BoxPrompt.IsPresent -or $BoxVerify.IsPresent
	BoxVerify = $BoxVerify.IsPresent
	FailureCategory = "none"
	NextCommands = @(
		"scripts\run-sam3-runtime-smoke.bat -DryRun",
		"scripts\run-sam3-runtime-smoke.bat -Backend cpu -Json -SummaryOnly",
		"scripts\run-sam3-runtime-smoke.bat -Backend cpu -Json -SummaryOnly -BoxVerify",
		"scripts\run-sam3-runtime-smoke.bat -Backend cuda -Json -SummaryOnly",
		"scripts\run-sam3-runtime-smoke.bat -Backend cpu -Image tests\fixtures\sam-point-square.ppm -Json -SummaryOnly -FixtureVerify",
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
if ($FixtureVerify -and -not $Json) {
	throw "-FixtureVerify requires -Json so mask statistics can be checked."
}
if ($BoxVerify -and -not $Json) {
	throw "-BoxVerify requires -Json so mask statistics can be checked."
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

function Invoke-SmokeRun {
	param([string] $RunLabel, [bool] $WantJson)
	$args = @("--model", $Model, "--backend", $Backend, "--image-size", $ImageSize.ToString())
	if (-not [string]::IsNullOrWhiteSpace($Image)) { $args += @("--image", $Image) }
	if ($Threads -gt 0) { $args += @("--threads", $Threads.ToString()) }
	if ($BoxPrompt -or $BoxVerify) { $args += "--box" }
	if ($WantJson) { $args += "--json" }
	if ($SummaryOnly) { $args += "--summary-only" }
	Write-Step "$RunLabel"
	$prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
	$smokeOutput = & $exePath @args 2>$null
	$smokeExitCode = $LASTEXITCODE
	$ErrorActionPreference = $prev
	$rawOutput = ($smokeOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
	if ($smokeExitCode -ne 0) {
		$errorText = $rawOutput.Trim()
		if ([string]::IsNullOrWhiteSpace($errorText)) { $errorText = "SAM3 runtime smoke failed" }
		throw $errorText
	}
	return $rawOutput
}

try {
	$smokeOutput = Invoke-SmokeRun -RunLabel "Running SAM3 runtime smoke" -WantJson:$Json.IsPresent

	$cacheInfo = $null
	$fixtureInfo = $null
	$boxInfo = $null
	if ($CacheVerify) {
		$cacheOutput = Invoke-SmokeRun -RunLabel "Running repeated prompt (cache verify)" -WantJson:$true
	}

	$result = if ($Json) {
		try { $smokeOutput | ConvertFrom-Json } catch { $null }
	} else { $null }

	$failureCategory = "none"
	$errorDetail = ""
	if ($result -and $result.Summary -and [string]::IsNullOrWhiteSpace($result.Summary.Error)) {
		$failureCategory = "none"
	} elseif ($result -and $result.Summary -and ![string]::IsNullOrWhiteSpace($result.Summary.Error)) {
		$errorDetail = $result.Summary.Error
		$failureCategory = Classify-Failure -ErrorMessage $errorDetail -ModelPath $Model -Backend $Backend
	}

	if ($CacheVerify -and $result -and $cacheOutput) {
		try {
			$cacheJson = $cacheOutput | ConvertFrom-Json
			if ($cacheJson -and $cacheJson.Summary) {
				$firstEncode = [double]$result.Summary.EncodeMs
				$secondEncode = [double]$cacheJson.Summary.EncodeMs
				$cacheHit = $secondEncode -lt $firstEncode
				$cacheInfo = [ordered] @{
					FirstEncodeMs = $firstEncode
					SecondEncodeMs = $secondEncode
					CacheHit = $cacheHit
					CacheRatio = if ($firstEncode -gt 0) { [math]::Round($secondEncode / $firstEncode, 3) } else { 1.0 }
				}
			}
		} catch {
			$cacheInfo = [ordered] @{ FirstEncodeMs = 0; SecondEncodeMs = 0; CacheHit = $false; CacheRatio = 0; Error = $_.Exception.Message }
		}
	}
	if ($FixtureVerify) {
		$fixtureInfo = Test-FixtureSmokeResult -Result $result -ImagePath $Image
	}
	if ($BoxVerify) {
		$boxInfo = Test-BoxSmokeResult -Result $result
	}

	$content = if ($Json -and $result) {
		$envelope = [ordered] @{
			SummaryOnly = $result.SummaryOnly
			Summary = $result.Summary
			FailureCategory = $failureCategory
		}
		if ($CacheVerify -and $cacheInfo) { $envelope.CacheVerify = $cacheInfo }
		if ($FixtureVerify -and $fixtureInfo) { $envelope.FixtureVerify = $fixtureInfo }
		if ($BoxVerify -and $boxInfo) { $envelope.BoxVerify = $boxInfo }
		if ($null -ne $result.Masks) { $envelope.Masks = $result.Masks }
		$envelope | ConvertTo-Json -Depth 5
	} else { $smokeOutput }

	Write-SmokeOutputPath -Path $OutputPath -Content $content
	if (![string]::IsNullOrWhiteSpace($content) -and $Json) { Write-Output $content }
} catch {
	$errorMsg = $_.Exception.Message
	$failureCategory = Classify-Failure -ErrorMessage $errorMsg -ModelPath $Model -Backend $Backend
	if ($Json) {
		$modelFileName = if (-not [string]::IsNullOrWhiteSpace($Model)) { [System.IO.Path]::GetFileName($Model) } else { "" }
		$modelFamily = Get-ModelFamilyHint -Name $modelFileName
		$jsonError = [ordered] @{
			SummaryOnly = $true
			Summary = [ordered] @{
				Passed = $false; InferenceChecked = $false; SmokeKind = "model-backed-sam3-point-segmentation"
				PromptKind = $(if ($BoxPrompt -or $BoxVerify) { "box" } else { "point" })
				Backend = $Backend; ModelPath = $Model; ImagePath = $Image; Threads = $Threads; ImageSize = $ImageSize
				BoxPrompt = ($BoxPrompt.IsPresent -or $BoxVerify.IsPresent)
				BoxX0 = 0.25; BoxY0 = 0.25; BoxX1 = 0.75; BoxY1 = 0.75
				MaskCount = 0; LoadMs = 0; StateMs = 0; EncodeMs = 0; SegmentMs = 0; TotalMs = 0; Error = $errorMsg
				FirstMaskWidth = 0; FirstMaskHeight = 0; FirstMaskActivePixels = 0; FirstMaskActiveRatio = 0
				FirstMaskMeanValue = 0; FirstMaskPromptValue = 0; FirstMaskCenterValue = 0
			}
			FailureCategory = $failureCategory
			ModelFamily = $modelFamily
		}
		$content = $jsonError | ConvertTo-Json -Depth 5
		Write-SmokeOutputPath -Path $OutputPath -Content $content
		Write-Output $content
	} else {
		Write-Host "ofxGgmlSam SAM3 runtime smoke failed"
		Write-Host "Category: $failureCategory"
		Write-Host "Error:    $errorMsg"
	}
	exit 1
}
