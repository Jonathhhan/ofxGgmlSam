param(
	[switch] $Cuda,
	[switch] $CpuOnly,
	[string] $Configuration = "Release",
	[string] $CudaArchitectures = "",
	[string] $GgmlSourceDir = "",
	[switch] $BundledGgml,
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
	return $null -ne (Select-String -LiteralPath $cudaPath -Pattern "ggml_cuda_op_win_part" -SimpleMatch -Quiet)
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
}

if ($Cuda -and $CpuOnly) {
	throw "Use either -Cuda or -CpuOnly, not both."
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
	}
}

if (-not (Test-Path (Join-Path $sourceDir "sam3.cpp"))) {
	& (Join-Path $scriptDir "install-sam3-cpp.ps1")
	if ($LASTEXITCODE -ne 0) {
		throw "install-sam3-cpp.ps1 failed with exit code $LASTEXITCODE."
	}
}

$enableCuda = $Cuda.IsPresent
if (-not $Cuda -and -not $CpuOnly) {
	$enableCuda = -not [string]::IsNullOrWhiteSpace((Get-CudaRoot))
}

$generator = Get-CMakeGenerator
if ([string]::IsNullOrWhiteSpace($generator)) {
	throw "No supported Visual Studio CMake generator was found."
}

$buildDirName = if ($enableCuda) { "build-cuda" } else { "build-cpu" }
$buildDir = Join-Path $sourceDir $buildDirName
if ($Clean -and (Test-Path -LiteralPath $buildDir)) {
	Remove-Item -LiteralPath $buildDir -Recurse -Force
}
$cmakeArgs = @(
	"-S", $sourceDir,
	"-B", $buildDir,
	"-G", $generator,
	"-A", "x64",
	"-DBUILD_SHARED_LIBS=OFF",
	"-DSAM3_BUILD_EXAMPLES=$(-not $SkipExamples)",
	"-DSAM3_BUILD_TESTS=OFF",
	"-DSAM3_CUDA=$enableCuda"
)
if (-not [string]::IsNullOrWhiteSpace($GgmlSourceDir)) {
	$cmakeArgs += "-DSAM3_GGML_SOURCE_DIR=$GgmlSourceDir"
}

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
	if (-not [string]::IsNullOrWhiteSpace($GgmlSourceDir)) {
		$patchPath = Join-Path $addonRoot "patches\ggml-cuda-win-part-unpart.patch"
		Apply-GgmlCudaWindowOpsPatch -SourceDir $GgmlSourceDir -PatchPath $patchPath
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
