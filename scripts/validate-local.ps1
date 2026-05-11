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

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonRoot = Split-Path -Parent $scriptRoot
$addonsRoot = Split-Path -Parent $addonRoot

Write-Step "Checking addon skeleton"
Assert-Path (Join-Path $addonRoot "addon_config.mk") "addon config"
Assert-Path (Join-Path $addonRoot "README.md") "README"
Assert-Path (Join-Path $addonRoot "LICENSE") "license"
Assert-Path (Join-Path $addonRoot "src\ofxGgmlSam.h") "public header"
Assert-Path (Join-Path $addonRoot "src\ofxGgmlSam\ofxGgmlSamTypes.h") "types header"

Write-Step "Checking dependency layout"
Assert-Path (Join-Path $addonsRoot "ofxGgml") "sibling ofxGgml addon" -Directory

Write-Step "Checking example layout"
$exampleRoot = Join-Path $addonRoot "ofxGgmlSamPointExample"
Assert-Path $exampleRoot "root-level point example" -Directory
Assert-Path (Join-Path $exampleRoot "addons.make") "point example addons.make"
Assert-Path (Join-Path $exampleRoot "src\main.cpp") "point example main.cpp"
Assert-Path (Join-Path $exampleRoot "src\ofApp.h") "point example ofApp.h"
Assert-Path (Join-Path $exampleRoot "src\ofApp.cpp") "point example ofApp.cpp"

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
	"models"
)

foreach ($relative in $forbidden) {
	$path = Join-Path $addonRoot $relative
	if (Test-Path -LiteralPath $path) {
		throw "Generated or local-only path should not be committed here: $relative"
	}
}

Write-Step "ofxGgmlSam local validation passed"
