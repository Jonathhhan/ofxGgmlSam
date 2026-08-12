param(
	[switch] $Cuda,
	[switch] $CpuOnly,
	[string] $Configuration = "Release",
	[string] $CudaArchitectures = "",
	[string] $GgmlSourceDir = "",
	[switch] $BundledGgml,
	[switch] $CheckOnly,
	[switch] $Clean,
	[switch] $SkipExamples
)

$ErrorActionPreference = "Stop"

function Invoke-Step {
	param(
		[string] $Description,
		[scriptblock] $Script
	)
	Write-Host "==> $Description"
	& $Script
	if ($LASTEXITCODE -ne 0) {
		throw "$Description failed with exit code $LASTEXITCODE."
	}
}

function Get-CMakeGenerator {
	$help = & cmake --help
	foreach ($candidate in @("Visual Studio 18 2026", "Visual Studio 17 2022", "Visual Studio 16 2019")) {
		if ($help -match [regex]::Escape($candidate)) {
			return $candidate
		}
	}
	return ""
}

function Get-CudaRoot {
	foreach ($candidate in @($env:CUDA_PATH, $env:CUDAToolkit_ROOT)) {
		if (-not [string]::IsNullOrWhiteSpace($candidate) -and
			(Test-Path (Join-Path $candidate "bin\nvcc.exe"))) {
			return $candidate
		}
	}
	$nvcc = Get-Command nvcc.exe -ErrorAction SilentlyContinue
	if ($nvcc) {
		return (Resolve-Path (Join-Path (Split-Path -Parent $nvcc.Source) "..")).Path
	}
	return ""
}

function Test-CudaVsIntegration {
	param([string] $CudaRoot)
	$msbuildExt = Join-Path $CudaRoot "extras\visual_studio_integration\MSBuildExtensions"
	return (Test-Path (Join-Path $msbuildExt "CUDA *.props")) -and
		(Test-Path (Join-Path $msbuildExt "CUDA *.targets"))
}

function Test-GgmlCudaWindowOps {
	param([string] $SourceDir)
	$cudaPath = Join-Path $SourceDir "src\ggml-cuda\ggml-cuda.cu"
	if (-not (Test-Path -LiteralPath $cudaPath -PathType Leaf)) {
		return $false
	}
	return [bool](Select-String -LiteralPath $cudaPath -Pattern "ggml_cuda_op_win_part" -SimpleMatch -Quiet)
}

function Assert-GgmlSourceCompatibility {
	param([string] $SourceDir)

	foreach ($relativePath in @("CMakeLists.txt", "include\ggml.h", "include\ggml-backend.h", "src\ggml.c")) {
		$path = Join-Path $SourceDir $relativePath
		if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
			throw "Selected ggml source is not compatible with the SAM3 build contract; missing $relativePath in $SourceDir."
		}
	}
}

function Get-GgmlSourceRevision {
	param([string] $SourceDir)

	$revision = & git -C $SourceDir rev-parse --short=12 HEAD 2>$null
	if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($revision)) {
		return $revision.Trim()
	}
	return "unversioned"
}

function New-IsolatedGgmlSource {
	param(
		[string] $SourceDir,
		[string] $DestinationDir
	)

	if (Test-Path -LiteralPath $DestinationDir) {
		Remove-Item -LiteralPath $DestinationDir -Recurse -Force
	}
	New-Item -ItemType Directory -Force -Path $DestinationDir | Out-Null
	Get-ChildItem -LiteralPath $SourceDir -Force |
		Where-Object { $_.Name -ne ".git" } |
		ForEach-Object {
			Copy-Item -LiteralPath $_.FullName -Destination $DestinationDir -Recurse -Force
		}
	git -C $DestinationDir init --quiet
	if ($LASTEXITCODE -ne 0) {
		throw "Could not initialize isolated ggml source at $DestinationDir."
	}
	return (Resolve-Path -LiteralPath $DestinationDir).Path
}

function Apply-GgmlCudaWindowOpsPatch {
	param(
		[string] $SourceDir,
		[string] $PatchPath
	)

	if (Test-GgmlCudaWindowOps -SourceDir $SourceDir) {
		Write-Host "==> ggml CUDA window ops patch already present."
		return
	}
	if (-not (Test-Path -LiteralPath $PatchPath -PathType Leaf)) {
		throw "SAM3 CUDA requires ggml CUDA window-op support, but the patch file is missing: $PatchPath"
	}
	if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
		throw "git is required to apply the ggml CUDA window-op compatibility patch."
	}

	Write-Host "==> Applying ggml CUDA window ops compatibility patch"
	git -C $SourceDir apply --whitespace=nowarn $PatchPath
	if ($LASTEXITCODE -ne 0) {
		throw "Could not apply ggml CUDA window-op patch to $SourceDir. Re-run after refreshing the ggml checkout or apply the patch manually."
	}
	if (-not (Test-GgmlCudaWindowOps -SourceDir $SourceDir)) {
		throw "The ggml CUDA window-op patch completed without exposing the required operation in $SourceDir."
	}
}

if ($Cuda -and $CpuOnly) {
	throw "Use either -Cuda or -CpuOnly, not both."
}
if ($BundledGgml -and -not [string]::IsNullOrWhiteSpace($GgmlSourceDir)) {
	throw "Use either -BundledGgml or -GgmlSourceDir, not both."
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonRoot = Resolve-Path (Join-Path $scriptDir "..")
$packageDir = Join-Path $addonRoot "libs\sam3.cpp"
$sourceDir = if ([string]::IsNullOrWhiteSpace($env:OFXGGML_SAM3_CPP_DIR)) {
	Join-Path $packageDir "source"
} else {
	$env:OFXGGML_SAM3_CPP_DIR
}
if ([string]::IsNullOrWhiteSpace($GgmlSourceDir) -and -not $BundledGgml) {
	$coreGgmlSource = Join-Path $addonRoot "..\ofxGgmlCore\libs\ggml\.source"
	if (Test-Path (Join-Path $coreGgmlSource "CMakeLists.txt")) {
		$GgmlSourceDir = (Resolve-Path -LiteralPath $coreGgmlSource).Path
	} else {
		throw "The default ofxGgmlCore ggml source was not found at $coreGgmlSource. Run the Core ggml setup, pass -GgmlSourceDir, or explicitly opt into -BundledGgml."
	}
}

if (-not (Test-Path (Join-Path $sourceDir "sam3.cpp"))) {
	& (Join-Path $scriptDir "install-sam3-cpp.ps1")
	if ($LASTEXITCODE -ne 0) {
		throw "install-sam3-cpp.ps1 failed with exit code $LASTEXITCODE."
	}
}

if ($BundledGgml -and [string]::IsNullOrWhiteSpace($GgmlSourceDir)) {
	$GgmlSourceDir = Join-Path $sourceDir "ggml"
}

$GgmlSourceDir = (Resolve-Path -LiteralPath $GgmlSourceDir).Path
Assert-GgmlSourceCompatibility -SourceDir $GgmlSourceDir
$ggmlRevision = Get-GgmlSourceRevision -SourceDir $GgmlSourceDir

$enableCuda = $Cuda.IsPresent
if (-not $Cuda -and -not $CpuOnly) {
	$enableCuda = -not [string]::IsNullOrWhiteSpace((Get-CudaRoot))
}

$buildDirName = if ($enableCuda) { "build-cuda" } else { "build-cpu" }
$buildDir = Join-Path $sourceDir $buildDirName
if ($Clean -and (Test-Path -LiteralPath $buildDir)) {
	Remove-Item -LiteralPath $buildDir -Recurse -Force
}

$effectiveGgmlSourceDir = $GgmlSourceDir
if ($enableCuda -and -not (Test-GgmlCudaWindowOps -SourceDir $GgmlSourceDir)) {
	$patchPath = Join-Path $addonRoot "patches\ggml-cuda-win-part-unpart.patch"
	$overlayDir = Join-Path $buildDir "ofxggml-core-cuda-source"
	Write-Host "==> Creating isolated ggml CUDA compatibility source"
	$effectiveGgmlSourceDir = New-IsolatedGgmlSource -SourceDir $GgmlSourceDir -DestinationDir $overlayDir
	Apply-GgmlCudaWindowOpsPatch -SourceDir $effectiveGgmlSourceDir -PatchPath $patchPath
}

Write-Host "==> ggml source contract is compatible"
Write-Host "Source:   $GgmlSourceDir"
Write-Host "Revision: $ggmlRevision"
if ($effectiveGgmlSourceDir -ne $GgmlSourceDir) {
	Write-Host "Overlay:  $effectiveGgmlSourceDir"
}

if ($CheckOnly) {
	Write-Host "==> ggml compatibility check complete; no build was run."
	return
}

$generator = Get-CMakeGenerator
if ([string]::IsNullOrWhiteSpace($generator)) {
	throw "No supported Visual Studio CMake generator was found."
}

$cmakeArgs = @(
	"-S", $sourceDir,
	"-B", $buildDir,
	"-G", $generator,
	"-A", "x64",
	"-UMATH_LIBRARY",
	"-DBUILD_SHARED_LIBS=OFF",
	"-DSAM3_BUILD_EXAMPLES=$(-not $SkipExamples)",
	"-DSAM3_BUILD_TESTS=OFF",
	"-DSAM3_CUDA=$enableCuda"
)
$cmakeArgs += "-DSAM3_GGML_SOURCE_DIR=$effectiveGgmlSourceDir"

if ($enableCuda) {
	$cudaRoot = Get-CudaRoot
	if ([string]::IsNullOrWhiteSpace($cudaRoot)) {
		throw "CUDA was requested but nvcc.exe was not found."
	}
	if (-not (Test-CudaVsIntegration -CudaRoot $cudaRoot)) {
		throw "CUDA was requested but Visual Studio CUDA integration files were not found under $cudaRoot."
	}
	$cmakeArgs += @("-T", "host=x64,cuda=$cudaRoot")
	if (-not [string]::IsNullOrWhiteSpace($CudaArchitectures)) {
		$cmakeArgs += "-DCMAKE_CUDA_ARCHITECTURES=$CudaArchitectures"
	}
}

Invoke-Step "Configuring sam3.cpp ($buildDirName)" {
	cmake @cmakeArgs
}
Invoke-Step "Building sam3.cpp ($Configuration)" {
	cmake --build $buildDir --config $Configuration --parallel
}

$packageLibDir = Join-Path $packageDir "lib\vs\x64"
New-Item -ItemType Directory -Force -Path $packageLibDir | Out-Null
Get-ChildItem -LiteralPath $buildDir -Recurse -Filter "*.lib" |
	Where-Object { $_.FullName -notlike "*CompilerIdCUDA*" } |
	ForEach-Object {
		Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $packageLibDir $_.Name) -Force
	}

Write-Host "==> sam3.cpp build complete."
Write-Host "Package: $packageDir"
Write-Host "Build:   $buildDir"
Write-Host "Lib:     $packageLibDir"
Write-Host "CUDA:    $enableCuda"
