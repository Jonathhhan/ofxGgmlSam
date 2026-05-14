param(
	[string]$ProjectPath = ""
)

$ErrorActionPreference = "Stop"

function Set-SemicolonValues {
	param(
		[System.Xml.XmlElement]$Element,
		[string[]]$BaseValues,
		[string[]]$Values
	)

	$existing = @($BaseValues)

	foreach ($value in $Values) {
		if ($existing -notcontains $value) {
			$existing += $value
		}
	}

	$Element.InnerText = ($existing -join ";")
}

function Add-OptionValues {
	param(
		[System.Xml.XmlElement]$Element,
		[string[]]$Values
	)

	$text = $Element.InnerText
	foreach ($value in $Values) {
		if ($text -notlike "*$value*") {
			$text = "$text $value".Trim()
		}
	}
	$Element.InnerText = $text
}

function Remove-OptionValues {
	param(
		[System.Xml.XmlElement]$Element,
		[string[]]$Values
	)

	$options = @($Element.InnerText -split "\s+" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
	$options = @($options | Where-Object { $Values -notcontains $_ })
	$Element.InnerText = ($options -join " ")
}

function Ensure-ChildElement {
	param(
		[System.Xml.XmlElement]$Parent,
		[string]$Name,
		[string]$Namespace
	)

	$child = $Parent.SelectSingleNode("msb:$Name", $script:NamespaceManager)
	if ($child) {
		return [System.Xml.XmlElement]$child
	}

	$child = $script:Document.CreateElement($Name, $Namespace)
	[void]$Parent.AppendChild($child)
	return $child
}

function Ensure-Item {
	param(
		[System.Xml.XmlElement]$ItemGroup,
		[string]$ElementName,
		[string]$Include,
		[string]$Namespace
	)

	$escaped = $Include.Replace("'", "&apos;")
	$existing = $ItemGroup.SelectSingleNode("msb:$ElementName[@Include='$escaped']", $script:NamespaceManager)
	if ($existing) {
		return
	}

	$item = $script:Document.CreateElement($ElementName, $Namespace)
	$item.SetAttribute("Include", $Include)
	[void]$ItemGroup.AppendChild($item)
}

function Remove-ItemsByInclude {
	param(
		[System.Xml.XmlElement]$ItemGroup,
		[string]$ElementName,
		[string[]]$Includes
	)

	foreach ($include in $Includes) {
		$escaped = $include.Replace("'", "&apos;")
		$items = @($ItemGroup.SelectNodes("msb:$ElementName[@Include='$escaped']", $script:NamespaceManager))
		foreach ($item in $items) {
			[void]$ItemGroup.RemoveChild($item)
		}
	}
}

function Get-CudaLibDir {
	foreach ($candidate in @($env:CUDA_PATH, $env:CUDA_PATH_V13_2, $env:CUDAToolkit_ROOT)) {
		if (-not [string]::IsNullOrWhiteSpace($candidate)) {
			$libDir = Join-Path $candidate "lib\x64"
			if (Test-Path -LiteralPath (Join-Path $libDir "cudart.lib") -PathType Leaf) {
				return $libDir
			}
		}
	}
	return ""
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonRoot = Split-Path -Parent $scriptRoot
$exampleRoot = Join-Path $addonRoot "ofxGgmlSamPointExample"
if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
	$ProjectPath = Join-Path $exampleRoot "ofxGgmlSamPointExample.vcxproj"
}

if (!(Test-Path -LiteralPath $ProjectPath -PathType Leaf)) {
	throw "Visual Studio project was not found: $ProjectPath"
}

$script:Document = New-Object System.Xml.XmlDocument
$script:Document.PreserveWhitespace = $true
$script:Document.Load($ProjectPath)

$namespace = $script:Document.DocumentElement.NamespaceURI
$script:NamespaceManager = New-Object System.Xml.XmlNamespaceManager($script:Document.NameTable)
$script:NamespaceManager.AddNamespace("msb", $namespace)

$sam3LibDir = Join-Path $addonRoot "libs\sam3.cpp\lib\vs\x64"
$hasSam3Libs = Test-Path -LiteralPath (Join-Path $sam3LibDir "sam3.lib") -PathType Leaf
$hasSam3CudaLib = Test-Path -LiteralPath (Join-Path $sam3LibDir "ggml-cuda.lib") -PathType Leaf
$cudaLibDir = Get-CudaLibDir

$includeDirs = @(
	"..\src",
	"..\src\ofxGgmlSam",
	"..\libs\sam.cpp\include",
	"..\..\ofxGgmlCore\src",
	"..\..\ofxGgmlCore\libs\ggml\include",
	"..\libs\sam3.cpp\include",
	"..\libs\sam3.cpp\include\stb",
	"..\..\ofxImGui\src",
	"..\..\ofxImGui\libs\imgui",
	"..\..\ofxImGui\libs\imgui\src",
	"..\..\ofxImGui\libs\imgui\backends",
	"..\..\ofxImGui\libs\imgui\extras"
)

$defines = @(
	"-DofxAddons_ENABLE_IMGUI",
	"-DOFXGGML_ENABLE_SAM3_ADAPTER",
	"-DOFXIMGUI_GLFW_EVENTS_REPLACE_OF_CALLBACKS=1",
	"-DOFXIMGUI_GLFW_FIX_MULTICONTEXT_PRIMARY_VP=0",
	"-DOFXIMGUI_GLFW_FIX_MULTICONTEXT_SECONDARY_VP=1"
)

$libraryDirs = @()
$dependencies = @()
if ($hasSam3Libs) {
	$libraryDirs += "..\libs\sam3.cpp\lib\vs\x64"
	$dependencies += @("sam3.lib", "ggml.lib", "ggml-base.lib", "ggml-cpu.lib")
	if ($hasSam3CudaLib) {
		$dependencies += "ggml-cuda.lib"
		if (-not [string]::IsNullOrWhiteSpace($cudaLibDir)) {
			$libraryDirs += $cudaLibDir
			$dependencies += @("cudart.lib", "cublas.lib", "cuda.lib")
		}
	}
}

$compileNodes = $script:Document.SelectNodes("//msb:ItemDefinitionGroup/msb:ClCompile", $script:NamespaceManager)
foreach ($compileNode in $compileNodes) {
	$includeNode = Ensure-ChildElement -Parent $compileNode -Name "AdditionalIncludeDirectories" -Namespace $namespace
	Set-SemicolonValues -Element $includeNode -BaseValues @("%(AdditionalIncludeDirectories)") -Values $includeDirs

	$optionsNode = Ensure-ChildElement -Parent $compileNode -Name "AdditionalOptions" -Namespace $namespace
	Remove-OptionValues -Element $optionsNode -Values @("-DOFXGGML_ENABLE_SAMCPP_ADAPTER")
	Add-OptionValues -Element $optionsNode -Values $defines
}

$linkNodes = $script:Document.SelectNodes("//msb:ItemDefinitionGroup/msb:Link", $script:NamespaceManager)
foreach ($linkNode in $linkNodes) {
	if ($libraryDirs.Count -gt 0) {
		$libraryNode = Ensure-ChildElement -Parent $linkNode -Name "AdditionalLibraryDirectories" -Namespace $namespace
		Set-SemicolonValues -Element $libraryNode -BaseValues @("%(AdditionalLibraryDirectories)") -Values $libraryDirs
	}
	if ($dependencies.Count -gt 0) {
		$dependencyNode = Ensure-ChildElement -Parent $linkNode -Name "AdditionalDependencies" -Namespace $namespace
		Set-SemicolonValues -Element $dependencyNode -BaseValues @("%(AdditionalDependencies)") -Values $dependencies
	}
}

$resourceNodes = $script:Document.SelectNodes("//msb:ResourceCompile", $script:NamespaceManager)
foreach ($resourceNode in $resourceNodes) {
	$includeNode = Ensure-ChildElement -Parent $resourceNode -Name "AdditionalIncludeDirectories" -Namespace $namespace
	Set-SemicolonValues -Element $includeNode -BaseValues @('$(OF_ROOT)\libs\openFrameworksCompiled\project\vs') -Values $includeDirs
}

$compileItemGroup = $script:Document.SelectSingleNode("//msb:ItemGroup[msb:ClCompile]", $script:NamespaceManager)
if (-not $compileItemGroup) {
	$compileItemGroup = $script:Document.CreateElement("ItemGroup", $namespace)
	[void]$script:Document.DocumentElement.InsertBefore($compileItemGroup, $script:Document.DocumentElement.SelectSingleNode("msb:Import[@Project='`$(VCTargetsPath)\Microsoft.Cpp.targets']", $script:NamespaceManager))
}

Remove-ItemsByInclude -ItemGroup $compileItemGroup -ElementName "ClCompile" -Includes @(
	"..\src\ofxGgmlSam\ofxGgmlSamLegacyAllocr.c",
	"..\libs\sam.cpp\src\sam.cpp"
)

$sourceItems = @(
	"..\src\ofxGgmlSam\ofxGgmlSamExternalBackend.cpp",
	"..\src\ofxGgmlSam\ofxGgmlSamInference.cpp",
	"..\src\ofxGgmlSam\ofxGgmlSamUtils.cpp",
	"..\..\ofxImGui\src\BaseEngine.cpp",
	"..\..\ofxImGui\src\DefaultTheme.cpp",
	"..\..\ofxImGui\src\EngineGLFW.cpp",
	"..\..\ofxImGui\src\EngineOpenFrameworks.cpp",
	"..\..\ofxImGui\src\EngineOpenGLES.cpp",
	"..\..\ofxImGui\src\Gui.cpp",
	"..\..\ofxImGui\src\GuiEventHelper.cpp",
	"..\..\ofxImGui\src\ImHelpers.cpp",
	"..\..\ofxImGui\src\ofxImGuiLoggerChannel.cpp",
	"..\..\ofxImGui\libs\imgui\src\imgui.cpp",
	"..\..\ofxImGui\libs\imgui\src\imgui_demo.cpp",
	"..\..\ofxImGui\libs\imgui\src\imgui_draw.cpp",
	"..\..\ofxImGui\libs\imgui\src\imgui_tables.cpp",
	"..\..\ofxImGui\libs\imgui\src\imgui_widgets.cpp",
	"..\..\ofxImGui\libs\imgui\backends\imgui_impl_glfw.cpp",
	"..\..\ofxImGui\libs\imgui\backends\imgui_impl_glfw_context_support.cpp",
	"..\..\ofxImGui\libs\imgui\backends\imgui_impl_opengl2.cpp",
	"..\..\ofxImGui\libs\imgui\backends\imgui_impl_opengl3.cpp",
	"..\..\ofxImGui\libs\imgui\extras\imgui_stdlib.cpp"
)
foreach ($source in $sourceItems) {
	Ensure-Item -ItemGroup $compileItemGroup -ElementName "ClCompile" -Include $source -Namespace $namespace
}

$includeItemGroup = $script:Document.SelectSingleNode("//msb:ItemGroup[msb:ClInclude]", $script:NamespaceManager)
if (-not $includeItemGroup) {
	$includeItemGroup = $script:Document.CreateElement("ItemGroup", $namespace)
	[void]$script:Document.DocumentElement.InsertAfter($includeItemGroup, $compileItemGroup)
}

foreach ($header in @(
	"..\src\ofxGgmlSam.h",
	"..\src\ofxGgmlSamVersion.h",
	"..\src\ofxGgmlSam\ofxGgmlSam3Adapters.h",
	"..\src\ofxGgmlSam\ofxGgmlSamCppAdapters.h",
	"..\src\ofxGgmlSam\ofxGgmlSamExternalBackend.h",
	"..\src\ofxGgmlSam\ofxGgmlSamInference.h",
	"..\src\ofxGgmlSam\ofxGgmlSamTypes.h",
	"..\src\ofxGgmlSam\ofxGgmlSamUtils.h"
)) {
	Ensure-Item -ItemGroup $includeItemGroup -ElementName "ClInclude" -Include $header -Namespace $namespace
}

$script:Document.Save($ProjectPath)
Write-Host "Repaired Visual Studio addon wiring: $ProjectPath"
