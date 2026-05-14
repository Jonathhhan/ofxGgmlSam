@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "ADDON_ROOT=%SCRIPT_DIR%.."
set "PACKAGE_DIR=%ADDON_ROOT%\libs\sam.cpp"
if "%OFXGGML_SAM_CPP_DIR%"=="" (
	set "DEST_DIR=%PACKAGE_DIR%\source"
) else (
	set "DEST_DIR=%OFXGGML_SAM_CPP_DIR%"
)
if "%OFXGGML_SAM_CPP_REPO%"=="" set "OFXGGML_SAM_CPP_REPO=https://github.com/YavorGIvanov/sam.cpp.git"
if "%OFXGGML_SAM_CPP_REF%"=="" set "OFXGGML_SAM_CPP_REF=81002818eb0e2cb3b9a523286b067f80f8424431"

where git >nul 2>nul
if errorlevel 1 (
	echo git is required to install sam.cpp
	exit /b 1
)

if not exist "%DEST_DIR%\.." mkdir "%DEST_DIR%\.."

if exist "%DEST_DIR%\.git" (
	echo ==^> Updating existing sam.cpp checkout in %DEST_DIR%
	git -C "%DEST_DIR%" fetch --tags origin
) else (
	if exist "%DEST_DIR%" (
		for /f %%A in ('dir /b "%DEST_DIR%" 2^>nul') do (
			echo Refusing to overwrite non-empty directory: %DEST_DIR%
			exit /b 1
		)
	)
	if exist "%DEST_DIR%" rmdir "%DEST_DIR%"
	echo ==^> Cloning sam.cpp into %DEST_DIR%
	git clone --recursive "%OFXGGML_SAM_CPP_REPO%" "%DEST_DIR%"
)

git -C "%DEST_DIR%" checkout "%OFXGGML_SAM_CPP_REF%"
if errorlevel 1 exit /b 1
git -C "%DEST_DIR%" submodule update --init --recursive
if errorlevel 1 exit /b 1

powershell -NoProfile -ExecutionPolicy Bypass -Command "$p='%DEST_DIR%\sam.cpp'; $t=[IO.File]::ReadAllText($p); $t=$t.Replace('ggml_scale(ctx0, cur, ggml_new_f32(ctx0, float(2.0f*M_PI)))','ggml_scale(ctx0, cur, float(2.0f*M_PI))'); $t=$t.Replace('ggml_new_f32(ctx0, 1.0f/sqrtf(n_enc_head_dim))','1.0f/sqrtf(n_enc_head_dim)'); $t=$t.Replace('ggml_new_f32(ctx0, 1.0f/sqrt(float(Q->ne[0])))','1.0f/sqrt(float(Q->ne[0]))'); [IO.File]::WriteAllText($p,$t,(New-Object Text.UTF8Encoding $false))"
if errorlevel 1 exit /b 1

if not exist "%PACKAGE_DIR%\include" mkdir "%PACKAGE_DIR%\include"
if not exist "%PACKAGE_DIR%\src" mkdir "%PACKAGE_DIR%\src"
copy /Y "%DEST_DIR%\sam.h" "%PACKAGE_DIR%\include\sam.h" >nul
copy /Y "%DEST_DIR%\sam.cpp" "%PACKAGE_DIR%\src\sam.cpp" >nul

echo ==^> sam.cpp is installed.
echo Package: %PACKAGE_DIR%
echo Source:  %DEST_DIR%
echo Ref:     %OFXGGML_SAM_CPP_REF%
echo Note: this source is patched for the Core ggml scale API, but the in-process adapter is not auto-enabled because this sam.cpp revision still needs a Core ggml allocator port.

endlocal
