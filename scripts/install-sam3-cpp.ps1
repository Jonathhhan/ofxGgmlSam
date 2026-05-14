param(
	[string] $Repo = "https://github.com/PABannier/sam3.cpp.git",
	[string] $Ref = "main",
	[switch] $Force
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

function Get-TextFile {
	param([string] $Path)
	$encoding = New-Object System.Text.UTF8Encoding $false
	return [System.IO.File]::ReadAllText($Path, $encoding)
}

function Set-TextFile {
	param(
		[string] $Path,
		[string] $Content
	)
	$encoding = New-Object System.Text.UTF8Encoding $false
	[System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Patch-Sam3CudaSupport {
	param([string] $SourceDir)

	$cmakePath = Join-Path $SourceDir "CMakeLists.txt"
	$cppPath = Join-Path $SourceDir "sam3.cpp"

	if (!(Test-Path -LiteralPath $cmakePath) -or !(Test-Path -LiteralPath $cppPath)) {
		throw "sam3.cpp checkout is missing CMakeLists.txt or sam3.cpp."
	}

	$cmake = Get-TextFile $cmakePath
	if ($cmake -notmatch "STB_IMAGE_STATIC") {
		$cmake = [regex]::Replace(
			$cmake,
			"target_compile_features\(sam3 PUBLIC cxx_std_14\)",
			"target_compile_features(sam3 PUBLIC cxx_std_14)`n`ntarget_compile_definitions(sam3 PRIVATE STB_IMAGE_STATIC)",
			1)
		Write-Host "Patched sam3 CMake STB private linkage."
	}
	if ($cmake -notmatch "SAM3_CUDA") {
		$cmake = [regex]::Replace(
			$cmake,
			"option\(SAM3_METAL `"Enable Metal backend`" ON\)",
			"option(SAM3_METAL `"Enable Metal backend`" ON)`noption(SAM3_CUDA `"Enable CUDA backend`" OFF)",
			1)
		$cmake = [regex]::Replace(
			$cmake,
			"if\(APPLE AND SAM3_METAL\)([\s\S]*?)endif\(\)",
			"if(APPLE AND SAM3_METAL)`$1endif()`nif(SAM3_CUDA)`n    set(GGML_CUDA ON CACHE BOOL `"`" FORCE)`nendif()",
			1)
		Write-Host "Patched sam3 CMake CUDA option."
	}
	if ($cmake -notmatch "SAM3_GGML_SOURCE_DIR") {
		$cmake = [regex]::Replace(
			$cmake,
			"add_subdirectory\(ggml\)",
			"set(SAM3_GGML_SOURCE_DIR `"`" CACHE PATH `"External ggml source directory`")`nif(SAM3_GGML_SOURCE_DIR)`n    add_subdirectory(`${SAM3_GGML_SOURCE_DIR} `${CMAKE_BINARY_DIR}/ggml)`nelse()`n    add_subdirectory(ggml)`nendif()",
			1)
		Write-Host "Patched sam3 CMake external ggml option."
	}
	if ($cmake -notmatch "GGML_USE_CUDA") {
		$cmake = [regex]::Replace(
			$cmake,
			"(target_compile_features\(sam3 PUBLIC cxx_std_14\)(?:\r?\n\r?\ntarget_compile_definitions\(sam3 PRIVATE STB_IMAGE_STATIC\))?)",
			"`$1`n`nif(SAM3_CUDA)`n    target_compile_definitions(sam3 PUBLIC GGML_USE_CUDA)`nendif()",
			1)
		Write-Host "Patched sam3 CMake CUDA compile definition."
	}
	Set-TextFile $cmakePath $cmake

	$cpp = Get-TextFile $cppPath
	if ($cpp -notmatch "ggml-cuda.h") {
		$cpp = [regex]::Replace(
			$cpp,
			"#include `"ggml\.h`"\r?\n\r?\n#ifdef GGML_USE_METAL",
			"#include `"ggml.h`"`n`n#ifdef GGML_USE_CUDA`n#include `"ggml-cuda.h`"`n#endif`n`n#ifdef GGML_USE_METAL",
			1)
	}
	if ($cpp -notmatch "ggml_backend_cuda_init") {
		$cpp = [regex]::Replace(
			$cpp,
			"#ifdef GGML_USE_METAL\r?\n    if \(params\.use_gpu\) \{\r?\n        fprintf\(stderr, `"%s: using Metal backend\\n`", __func__\);\r?\n        model->backend = ggml_backend_metal_init\(\);\r?\n    \}\r?\n#endif",
			"#ifdef GGML_USE_CUDA`n    if (params.use_gpu) {`n        fprintf(stderr, `"%s: using CUDA backend\n`", __func__);`n        model->backend = ggml_backend_cuda_init(0);`n        if (!model->backend) {`n            fprintf(stderr, `"%s: failed to init CUDA backend; falling back to CPU\n`", __func__);`n        }`n    }`n#endif`n#ifdef GGML_USE_METAL`n    if (params.use_gpu) {`n        fprintf(stderr, `"%s: using Metal backend\n`", __func__);`n        model->backend = ggml_backend_metal_init();`n    }`n#endif",
			1)
	}
	if ($cpp -notmatch "small head dimension on ggml 0\.11") {
		$cpp = [regex]::Replace(
			$cpp,
			"    // Attention\r?\n    float scale = 1\.0f / sqrtf\(\(float\)HD\);\r?\n    auto\* out = ggml_flash_attn_ext\(ctx, Q, K, V, nullptr, scale, 0\.0f, 0\.0f\);\r?\n    // out: \[HD, NH, N_q, B\] \(flash_attn_ext swaps dims 1,2 vs input\)\r?\n\r?\n#if 0  // Manual SDPA \(for debugging only\)",
			"    // Attention. The CUDA flash-attention kernels do not cover the SAM decoder's`n    // small head dimension on ggml 0.11, so CUDA uses the equivalent SDPA graph.`n    float scale = 1.0f / sqrtf((float)HD);`n#if defined(GGML_USE_CUDA)",
			1)
		$cpp = [regex]::Replace(
			$cpp,
			"(    // Permute to \[HD, NH, N_q, B\] to match flash_attn_ext output convention\r?\n    out = ggml_cont\(ctx, ggml_permute\(ctx, out, 0, 2, 1, 3\)\);\r?\n)#endif",
			"`$1#else`n    auto* out = ggml_flash_attn_ext(ctx, Q, K, V, nullptr, scale, 0.0f, 0.0f);`n    // out: [HD, NH, N_q, B] (flash_attn_ext swaps dims 1,2 vs input)`n#endif",
			1)
		Write-Host "Patched sam3 CUDA SAM-decoder attention fallback."
	}
	Set-TextFile $cppPath $cpp
}

function Sync-Sam3Package {
	param(
		[string] $SourceDir,
		[string] $PackageDir
	)

	$includeDir = Join-Path $PackageDir "include"
	$srcDir = Join-Path $PackageDir "src"
	New-Item -ItemType Directory -Force -Path $includeDir | Out-Null
	New-Item -ItemType Directory -Force -Path $srcDir | Out-Null

	Copy-Item -LiteralPath (Join-Path $SourceDir "sam3.h") -Destination (Join-Path $includeDir "sam3.h") -Force
	Copy-Item -LiteralPath (Join-Path $SourceDir "sam3.cpp") -Destination (Join-Path $srcDir "sam3.cpp") -Force

	$stbDir = Join-Path $includeDir "stb"
	New-Item -ItemType Directory -Force -Path $stbDir | Out-Null
	foreach ($header in @("stb_image.h", "stb_image_write.h")) {
		$sourceHeader = Join-Path $SourceDir "stb\$header"
		if (Test-Path -LiteralPath $sourceHeader -PathType Leaf) {
			Copy-Item -LiteralPath $sourceHeader -Destination (Join-Path $stbDir $header) -Force
		}
	}
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonRoot = Resolve-Path (Join-Path $scriptDir "..")
$packageDir = Join-Path $addonRoot "libs\sam3.cpp"
$destDir = if ([string]::IsNullOrWhiteSpace($env:OFXGGML_SAM3_CPP_DIR)) {
	Join-Path $packageDir "source"
} else {
	$env:OFXGGML_SAM3_CPP_DIR
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
	throw "git is required to install sam3.cpp."
}

if (Test-Path (Join-Path $destDir ".git")) {
	Invoke-Step "Updating existing sam3.cpp checkout" {
		git -C $destDir fetch --tags origin
	}
} else {
	if (Test-Path $destDir) {
		$children = Get-ChildItem -LiteralPath $destDir -Force
		if ($children.Count -gt 0 -and -not $Force) {
			throw "Refusing to overwrite non-empty directory: $destDir. Re-run with -Force to replace it."
		}
		Remove-Item -LiteralPath $destDir -Recurse -Force
	}
	New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destDir) | Out-Null
	Invoke-Step "Cloning sam3.cpp into $destDir" {
		git clone --recursive $Repo $destDir
	}
}

Invoke-Step "Checking out sam3.cpp ref $Ref" {
	git -C $destDir checkout $Ref
}
Invoke-Step "Updating sam3.cpp submodules" {
	git -C $destDir submodule update --init --recursive
}

Patch-Sam3CudaSupport -SourceDir $destDir
Sync-Sam3Package -SourceDir $destDir -PackageDir $packageDir

Write-Host "==> sam3.cpp is installed."
Write-Host "Package: $packageDir"
Write-Host "Source:  $destDir"
Write-Host "Ref:     $Ref"
Write-Host "CUDA:    patched ggml CUDA backend init support for sam3.cpp"
