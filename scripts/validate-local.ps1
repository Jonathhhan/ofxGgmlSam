param()

$ErrorActionPreference = "Stop"

function Write-Step {
	param([string]$Message)
	Write-Host "==> $Message"
}

function Assert-Path {
	param(
		[string]$Path,
		[string]$Label,
		[switch]$Directory
	)

	if ($Directory) {
		if (!(Test-Path -LiteralPath $Path -PathType Container)) {
			throw "$Label was not found: $Path"
		}
	} elseif (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
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

function Assert-FileNotContains {
	param(
		[string]$Path,
		[string]$Pattern,
		[string]$Label
	)

	$content = Get-Content -LiteralPath $Path -Raw
	if ($content -match $Pattern) {
		throw "$Label contained forbidden pattern: $Pattern"
	}
}
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonRoot = Split-Path -Parent $scriptRoot
$addonsRoot = Split-Path -Parent $addonRoot

Write-Step "Checking addon skeleton"
$addonConfig = Join-Path $addonRoot "addon_config.mk"
Assert-Path $addonConfig "addon config"
Assert-FileContains $addonConfig "(?m)^\s*ADDON_INCLUDES\s*=\s*src\s*$" "addon config"
Assert-FileContains $addonConfig "src/ofxGgmlSam/ofxGgmlSamExternalBackend.cpp" "addon config"
Assert-FileContains $addonConfig "src/ofxGgmlSam/ofxGgmlSamInference.cpp" "addon config"
Assert-FileContains $addonConfig "src/ofxGgmlSam/ofxGgmlSamUtils.cpp" "addon config"
Assert-FileNotContains $addonConfig "ADDON_SOURCES_EXCLUDE" "addon config"
Assert-FileNotContains $addonConfig "ADDON_INCLUDES_EXCLUDE" "addon config"
Assert-FileNotContains $addonConfig "libs[/\\]sam" "addon config"
Assert-FileNotContains $addonConfig "\.local[/\\]runtimes" "addon config"
Assert-Path (Join-Path $addonRoot "README.md") "README"
Assert-Path (Join-Path $addonRoot "LICENSE") "license"
Assert-Path (Join-Path $addonRoot "docs\SAM_WORKFLOWS.md") "SAM workflow docs"
Assert-Path (Join-Path $addonRoot ".github\workflows\evidence-validation.yml") "evidence validation workflow"
Assert-Path (Join-Path $addonRoot ".github\workflows\evidence-promotion-advisor.yml") "evidence promotion advisor workflow"
Assert-Path (Join-Path $addonRoot "tests\fixtures\README.md") "SAM fixture docs"
Assert-Path (Join-Path $addonRoot "tests\fixtures\sam-point-square.ppm") "SAM point fixture"
Assert-FileContains (Join-Path $addonRoot "README.md") "docs/SAM_WORKFLOWS.md" "README"
Assert-FileContains (Join-Path $addonRoot "docs\SAM_WORKFLOWS.md") "Planning handoff" "SAM workflow docs"
Assert-FileContains (Join-Path $addonRoot "docs\SAM_WORKFLOWS.md") "Validation ladder" "SAM workflow docs"
Assert-FileContains (Join-Path $addonRoot "docs\SAM_WORKFLOWS.md") "generated masks" "SAM workflow docs"
Assert-FileContains (Join-Path $addonRoot "docs\SAM_WORKFLOWS.md") "tests\\fixtures\\sam-point-square\.ppm" "SAM workflow docs"
Assert-FileContains (Join-Path $addonRoot ".github\workflows\evidence-validation.yml") "evidence_profile:\s+advisory" "evidence validation workflow"
Assert-FileContains (Join-Path $addonRoot ".github\workflows\evidence-validation.yml") "sam3-runtime-evidence\.json" "evidence validation workflow"
Assert-FileContains (Join-Path $addonRoot ".github\workflows\evidence-promotion-advisor.yml") "current_profile:\s+advisory" "evidence promotion advisor workflow"
Assert-FileContains (Join-Path $addonRoot ".github\workflows\evidence-promotion-advisor.yml") "candidate_profile:\s+schema" "evidence promotion advisor workflow"
Assert-FileContains (Join-Path $addonRoot ".github\workflows\evidence-promotion-advisor.yml") "observed_clean_runs:\s+`"0`"" "evidence promotion advisor workflow"
Assert-FileContains (Join-Path $addonRoot ".github\workflows\evidence-promotion-advisor.yml") "evidence-promotion\.json" "evidence promotion advisor workflow"
Assert-Path (Join-Path $addonRoot "src\ofxGgmlSam.h") "public header"
Assert-Path (Join-Path $addonRoot "src\ofxGgmlSamVersion.h") "version header"
Assert-FileContains (Join-Path $addonRoot "src\ofxGgmlSam.h") "ofxGgmlSamVersion.h" "public header"
Assert-FileContains (Join-Path $addonRoot "src\ofxGgmlSamVersion.h") "OFXGGML_SAM_VERSION_STRING" "version header"
Assert-Path (Join-Path $addonRoot "src\ofxGgmlSam\ofxGgmlSamTypes.h") "types header"
Assert-FileContains (Join-Path $addonRoot "src\ofxGgmlSam\ofxGgmlSamTypes.h") "ofxGgmlSamBox" "types header box prompt"
Assert-FileContains (Join-Path $addonRoot "src\ofxGgmlSam\ofxGgmlSamTypes.h") "refinementMask" "types header refinement mask"
Assert-FileContains (Join-Path $addonRoot "src\ofxGgmlSam\ofxGgmlSamTypes.h") "maskInputFlag" "external adapter mask input flag"
Assert-Path (Join-Path $addonRoot "src\ofxGgmlSam\ofxGgmlSamExternalBackend.h") "external backend header"
Assert-Path (Join-Path $addonRoot "src\ofxGgmlSam\ofxGgmlSamExternalBackend.cpp") "external backend source"
Assert-FileContains (Join-Path $addonRoot "src\ofxGgmlSam\ofxGgmlSamExternalBackend.cpp") "for \(const auto & point : request\.points\)" "external backend multi-point forwarding"
Assert-FileContains (Join-Path $addonRoot "src\ofxGgmlSam\ofxGgmlSamExternalBackend.cpp") "for \(const auto & box : request\.boxes\)" "external backend box forwarding"
Assert-FileContains (Join-Path $addonRoot "src\ofxGgmlSam\ofxGgmlSamExternalBackend.cpp") "writePgmMask" "external backend refinement mask forwarding"
Assert-Path (Join-Path $addonRoot "src\ofxGgmlSam\ofxGgmlSamCppAdapters.h") "sam.cpp adapter header"
Assert-Path (Join-Path $addonRoot "src\ofxGgmlSam\ofxGgmlSam3Adapters.h") "sam3.cpp adapter header"
Assert-FileContains (Join-Path $addonRoot "src\ofxGgmlSam\ofxGgmlSam3Adapters.h") "pvs\.use_box = true" "sam3.cpp adapter box prompt support"
Assert-FileContains (Join-Path $addonRoot "src\ofxGgmlSam.h") "ofxGgmlSamCppAdapters.h" "public header sam.cpp adapter export"
Assert-FileContains (Join-Path $addonRoot "src\ofxGgmlSam.h") "ofxGgmlSam3Adapters.h" "public header sam3.cpp adapter export"
Assert-Path (Join-Path $addonRoot "src\ofxGgmlSam\ofxGgmlSamInference.h") "inference header"
Assert-Path (Join-Path $addonRoot "src\ofxGgmlSam\ofxGgmlSamInference.cpp") "inference source"
Assert-FileContains (Join-Path $addonRoot "src\ofxGgmlSam\ofxGgmlSamInference.h") "segmentBatch" "inference header batch API"
Assert-FileContains (Join-Path $addonRoot "src\ofxGgmlSam\ofxGgmlSamInference.cpp") "ofxGgmlSamInference::segmentBatch" "inference source batch API"
Assert-Path (Join-Path $addonRoot "src\ofxGgmlSam\ofxGgmlSamUtils.h") "utility header"
Assert-Path (Join-Path $addonRoot "src\ofxGgmlSam\ofxGgmlSamUtils.cpp") "utility source"
Assert-Path (Join-Path $addonRoot "libs\sam.cpp\README.md") "sam.cpp package README"
Assert-Path (Join-Path $addonRoot "libs\sam.cpp\include\.gitkeep") "sam.cpp include placeholder"
Assert-Path (Join-Path $addonRoot "libs\sam.cpp\src\.gitkeep") "sam.cpp src placeholder"
Assert-Path (Join-Path $addonRoot "libs\sam3.cpp\README.md") "sam3.cpp package README"
Assert-Path (Join-Path $addonRoot "libs\sam3.cpp\include\.gitkeep") "sam3.cpp include placeholder"
Assert-Path (Join-Path $addonRoot "libs\sam3.cpp\src\.gitkeep") "sam3.cpp src placeholder"

Write-Step "Checking dependency layout"
Assert-Path (Join-Path $addonsRoot "ofxGgmlCore") "sibling ofxGgmlCore addon" -Directory
Assert-Path (Join-Path $addonsRoot "ofxImGui") "sibling ofxImGui addon for examples" -Directory

Write-Step "Checking example layout"
$exampleRoot = Join-Path $addonRoot "ofxGgmlSamPointExample"
Assert-Path $exampleRoot "root-level point example" -Directory
Assert-Path (Join-Path $exampleRoot "addons.make") "point example addons.make"
Assert-FileContains (Join-Path $exampleRoot "addons.make") "(?m)^ofxImGui\s*$" "example addons.make"
Assert-Path (Join-Path $exampleRoot "src\main.cpp") "point example main.cpp"
Assert-Path (Join-Path $exampleRoot "src\ofApp.h") "point example ofApp.h"
Assert-Path (Join-Path $exampleRoot "src\ofApp.cpp") "point example ofApp.cpp"
Assert-FileContains (Join-Path $exampleRoot "src\ofApp.h") "ofxImGui.h" "point example ImGui header"
Assert-FileContains (Join-Path $exampleRoot "src\ofApp.cpp") "sam3.cpp" "point example sam3 backend"
Assert-FileContains (Join-Path $exampleRoot "src\ofApp.cpp") "sam.cpp" "point example sam backend"
Assert-FileContains (Join-Path $exampleRoot "src\ofApp.cpp") "maskTexture" "point example mask overlay"
Assert-FileContains (Join-Path $exampleRoot "src\ofApp.cpp") "kPromptLabels" "point example prompt mode selector"
Assert-FileContains (Join-Path $exampleRoot "src\ofApp.cpp") "mouseDragged" "point example box drag prompt"
Assert-FileContains (Join-Path $exampleRoot "src\ofApp.cpp") "setBoxFromCorners" "point example box prompt update"
Assert-Path (Join-Path $scriptRoot "run-point-example.ps1") "point example run script"
Assert-Path (Join-Path $scriptRoot "run-point-example.bat") "point example Windows wrapper"
Assert-Path (Join-Path $scriptRoot "run-point-example.sh") "point example shell wrapper"
Assert-Path (Join-Path $scriptRoot "repair-point-example-vsproj.ps1") "point example Visual Studio repair script"
Assert-Path (Join-Path $scriptRoot "repair-point-example-vsproj.bat") "point example Visual Studio repair Windows wrapper"
Assert-Path (Join-Path $scriptRoot "doctor-sam.ps1") "SAM doctor script"
Assert-Path (Join-Path $scriptRoot "doctor-sam.bat") "SAM doctor Windows wrapper"
Assert-Path (Join-Path $scriptRoot "doctor-sam.sh") "SAM doctor shell wrapper"
Assert-Path (Join-Path $scriptRoot "test-doctor-sam.ps1") "SAM doctor smoke test"
Assert-Path (Join-Path $scriptRoot "generate-sam-fixtures.ps1") "SAM fixture generator script"
Assert-Path (Join-Path $scriptRoot "generate-sam-fixtures.bat") "SAM fixture generator Windows wrapper"
Assert-Path (Join-Path $scriptRoot "generate-sam-fixtures.sh") "SAM fixture generator shell wrapper"
Assert-Path (Join-Path $scriptRoot "list-models.ps1") "SAM model discovery script"
Assert-Path (Join-Path $scriptRoot "list-models.bat") "SAM model discovery Windows wrapper"
Assert-Path (Join-Path $scriptRoot "list-models.sh") "SAM model discovery shell wrapper"
Assert-Path (Join-Path $scriptRoot "run-sam3-runtime-smoke.ps1") "SAM3 runtime smoke script"
Assert-Path (Join-Path $scriptRoot "run-sam3-runtime-smoke.bat") "SAM3 runtime smoke Windows wrapper"
Assert-Path (Join-Path $scriptRoot "run-sam3-runtime-smoke.sh") "SAM3 runtime smoke shell wrapper"
Assert-Path (Join-Path $scriptRoot "test-sam3-runtime-smoke.ps1") "SAM3 runtime smoke contract test"
Assert-Path (Join-Path $scriptRoot "write-sam3-runtime-evidence.ps1") "SAM3 runtime evidence writer"
Assert-Path (Join-Path $scriptRoot "write-sam3-runtime-evidence.bat") "SAM3 runtime evidence writer Windows wrapper"
Assert-Path (Join-Path $scriptRoot "run-sam3-evidence-pilot.ps1") "SAM3 evidence pilot script"
Assert-Path (Join-Path $scriptRoot "run-sam3-evidence-pilot.bat") "SAM3 evidence pilot Windows wrapper"
Assert-Path (Join-Path $scriptRoot "test-sam3-runtime-evidence.ps1") "SAM3 runtime evidence writer contract test"
Assert-Path (Join-Path $scriptRoot "test-sam3-evidence-pilot.ps1") "SAM3 evidence pilot contract test"
Assert-FileContains (Join-Path $scriptRoot "run-sam3-runtime-smoke.ps1") "BoxVerify" "SAM3 runtime smoke box verification"
Assert-FileContains (Join-Path $scriptRoot "write-sam3-runtime-evidence.ps1") "schema_version" "SAM3 runtime evidence schema wrapper"
Assert-FileContains (Join-Path $scriptRoot "run-sam3-evidence-pilot.ps1") "validate-evidence.py" "SAM3 evidence pilot validator"
Assert-Path (Join-Path $scriptRoot "install-sam-cpp.bat") "sam.cpp install Windows wrapper"
Assert-Path (Join-Path $scriptRoot "install-sam-cpp.sh") "sam.cpp install shell wrapper"
Assert-Path (Join-Path $scriptRoot "install-sam3-cpp.ps1") "sam3.cpp install script"
Assert-Path (Join-Path $scriptRoot "install-sam3-cpp.bat") "sam3.cpp install Windows wrapper"
Assert-Path (Join-Path $scriptRoot "build-sam3-cpp.ps1") "sam3.cpp build script"
Assert-Path (Join-Path $scriptRoot "build-sam3-cpp.bat") "sam3.cpp build Windows wrapper"
Assert-Path (Join-Path $scriptRoot "test-external-adapter-contract.ps1") "external adapter contract script"
Assert-Path (Join-Path $scriptRoot "test-external-adapter-contract.bat") "external adapter contract Windows wrapper"
Assert-Path (Join-Path $scriptRoot "test-external-adapter-contract.sh") "external adapter contract shell wrapper"
Assert-Path (Join-Path $scriptRoot "test-external-batch.ps1") "external batch script"
Assert-Path (Join-Path $scriptRoot "test-external-batch.bat") "external batch Windows wrapper"
Assert-Path (Join-Path $scriptRoot "test-external-batch.sh") "external batch shell wrapper"
Assert-Path (Join-Path $scriptRoot "test-addon.ps1") "test script"
Assert-Path (Join-Path $scriptRoot "test-addon.bat") "test Windows wrapper"
Assert-Path (Join-Path $scriptRoot "test-addon.sh") "test shell wrapper"
Assert-Path (Join-Path $addonRoot "tests\CMakeLists.txt") "test CMakeLists"
Assert-Path (Join-Path $addonRoot "tests\test_main.cpp") "test source"
Assert-FileContains (Join-Path $addonRoot "tests\test_main.cpp") "segmentBatch" "test source batch API"
Assert-Path (Join-Path $addonRoot "tests\test_external_adapter_contract.cpp") "external adapter contract test source"
Assert-Path (Join-Path $addonRoot "tools\ofxGgmlSamMockAdapter\CMakeLists.txt") "mock adapter CMakeLists"
Assert-Path (Join-Path $addonRoot "tools\ofxGgmlSamMockAdapter\main.cpp") "mock adapter source"
Assert-FileContains (Join-Path $addonRoot "tools\ofxGgmlSamMockAdapter\main.cpp") "std::vector<float> pointXs" "mock adapter multi-point support"
Assert-FileContains (Join-Path $addonRoot "tools\ofxGgmlSamMockAdapter\main.cpp") "std::vector<float> boxX0s" "mock adapter box support"
Assert-FileContains (Join-Path $addonRoot "tools\ofxGgmlSamMockAdapter\main.cpp") "maskInputPath" "mock adapter refinement mask support"
Assert-Path (Join-Path $addonRoot "tools\ofxGgmlSamBatchExternal\CMakeLists.txt") "external batch CMakeLists"
Assert-Path (Join-Path $addonRoot "tools\ofxGgmlSamBatchExternal\main.cpp") "external batch source"
Assert-FileContains (Join-Path $addonRoot "tools\ofxGgmlSamBatchExternal\main.cpp") "segmentBatch" "external batch source batch API"
Assert-FileContains (Join-Path $addonRoot "tools\ofxGgmlSamBatchExternal\main.cpp") "--input-dir" "external batch source directory input"
Assert-Path (Join-Path $addonRoot "tools\ofxGgmlSam3RuntimeSmoke\CMakeLists.txt") "SAM3 runtime smoke CMakeLists"
Assert-Path (Join-Path $addonRoot "tools\ofxGgmlSam3RuntimeSmoke\main.cpp") "SAM3 runtime smoke source"

$nestedExamples = Join-Path $addonRoot "examples"
if (Test-Path -LiteralPath $nestedExamples -PathType Container) {
	throw "Examples should live at the addon root, not under: $nestedExamples"
}

Write-Step "Checking generated artifact hygiene"
$forbidden = @(
	"build",
	".vs",
	"ofxGgmlSamPointExample\bin",
	"ofxGgmlSamPointExample\obj",
	"ofxGgmlSamPointExample\.vs",
	".local",
	"libs\sam.cpp\source",
	"libs\sam.cpp\lib",
	"libs\sam3.cpp\source",
	"libs\sam3.cpp\lib",
	"models"
)

foreach ($relative in $forbidden) {
	$tracked = git -C $addonRoot ls-files -- $relative
	if ($tracked) {
		throw "Generated or local-only path is tracked and should not be committed here: $relative"
	}
}

Write-Step "Checking point example launch dry-run"
$dryRunOutput = try {
	& (Join-Path $scriptRoot "run-point-example.ps1") -DryRun 2>&1 | Out-String
} catch {
	throw "Point example dry-run failed: $($_.Exception.Message)"
}
foreach ($expected in @("Example:    ofxGgmlSamPointExample", "Executable:", "Project:")) {
	if ($dryRunOutput -notlike "*$expected*") {
		throw "Point example dry-run did not include expected text: $expected"
	}
}

Write-Step "Checking SAM model discovery"
$modelDiscoveryOutput = & (Join-Path $scriptRoot "list-models.ps1") -Json -SummaryOnly 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
	throw "SAM model discovery failed with exit code $LASTEXITCODE"
}
$modelDiscovery = $modelDiscoveryOutput | ConvertFrom-Json
if ($modelDiscovery.Name -ne "ofxGgmlSam model discovery") {
	throw "SAM model discovery JSON did not include the expected name."
}
if ($modelDiscovery.Summary.SearchDirectoryCount -lt 3) {
	throw "SAM model discovery did not report the expected search directories."
}
if (($modelDiscovery.NextCommands -join "`n") -notmatch "run-sam3-runtime-smoke\.bat -DryRun") {
	throw "SAM model discovery JSON did not include the runtime smoke next command."
}
Assert-FileContains (Join-Path $addonRoot "README.md") "scripts\\list-models\.bat -Json -SummaryOnly" "README"

Write-Step "Checking SAM fixture generation"
$fixtureDryRun = & (Join-Path $scriptRoot "generate-sam-fixtures.ps1") -DryRun -Verify 2>&1 6>&1 | Out-String
if (!$fixtureDryRun.Contains("SAM fixture generation plan") -or
	!$fixtureDryRun.Contains("Dry run complete; no files were changed")) {
	throw "SAM fixture generation dry-run output was unexpected:`n$fixtureDryRun"
}
& (Join-Path $scriptRoot "generate-sam-fixtures.ps1") -Clean -Verify
if ($LASTEXITCODE -ne 0) {
	throw "SAM fixture generation failed with exit code $LASTEXITCODE"
}

Write-Step "Running headless tests"
& (Join-Path $scriptRoot "test-addon.ps1")
if ($LASTEXITCODE -ne 0) {
	throw "Headless tests failed with exit code $LASTEXITCODE"
}

Write-Step "Checking external adapter contract"
$adapterDryRun = & (Join-Path $scriptRoot "test-external-adapter-contract.ps1") -DryRun 2>&1 6>&1 | Out-String
if (!$adapterDryRun.Contains("External SAM adapter contract plan") -or
	!$adapterDryRun.Contains("Dry run complete; no files were changed")) {
	throw "External adapter contract dry-run output was unexpected:`n$adapterDryRun"
}

Write-Step "Checking external batch workflow"
$batchDryRun = & (Join-Path $scriptRoot "test-external-batch.ps1") -DryRun 2>&1 6>&1 | Out-String
if (!$batchDryRun.Contains("External SAM batch plan") -or
	!$batchDryRun.Contains("Dry run complete; no files were changed")) {
	throw "External SAM batch dry-run output was unexpected:`n$batchDryRun"
}

Write-Step "Checking SAM doctor"
& (Join-Path $scriptRoot "test-doctor-sam.ps1")
if ($LASTEXITCODE -ne 0) {
	throw "SAM doctor smoke test failed with exit code $LASTEXITCODE"
}

Write-Step "Checking SAM3 runtime smoke contract"
& (Join-Path $scriptRoot "test-sam3-runtime-smoke.ps1")
if ($LASTEXITCODE -ne 0) {
	throw "SAM3 runtime smoke contract failed with exit code $LASTEXITCODE"
}

Write-Step "Checking SAM3 runtime evidence wrapper contract"
& (Join-Path $scriptRoot "test-sam3-runtime-evidence.ps1")
if ($LASTEXITCODE -ne 0) {
	throw "SAM3 runtime evidence wrapper contract failed with exit code $LASTEXITCODE"
}

Write-Step "Checking SAM3 evidence pilot contract"
& (Join-Path $scriptRoot "test-sam3-evidence-pilot.ps1")
if ($LASTEXITCODE -ne 0) {
	throw "SAM3 evidence pilot contract failed with exit code $LASTEXITCODE"
}

& (Join-Path $scriptRoot "test-external-adapter-contract.ps1") -Clean
if ($LASTEXITCODE -ne 0) {
	throw "External adapter contract failed with exit code $LASTEXITCODE"
}

& (Join-Path $scriptRoot "test-external-batch.ps1") -Clean
if ($LASTEXITCODE -ne 0) {
	throw "External batch workflow failed with exit code $LASTEXITCODE"
}

Write-Step "ofxGgmlSam local validation passed"
