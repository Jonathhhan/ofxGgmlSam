param(
	[string]$OutputDir = "",
	[switch]$Clean,
	[switch]$Verify,
	[switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Write-Step {
	param([string]$Message)
	Write-Host "==> $Message"
}

function Get-SamPointSquarePpm {
	return @'
P3
# Hand-authored 8x8 RGB fixture for point-prompt segmentation smoke checks.
8 8
255
24 32 48   24 32 48   24 32 48   24 32 48   24 32 48   24 32 48   24 32 48   24 32 48
24 32 48   24 32 48   24 32 48   24 32 48   24 32 48   24 32 48   24 32 48   24 32 48
24 32 48   24 32 48   220 64 72  220 64 72  220 64 72  220 64 72  24 32 48   24 32 48
24 32 48   24 32 48   220 64 72  220 64 72  220 64 72  220 64 72  24 32 48   24 32 48
24 32 48   24 32 48   220 64 72  220 64 72  220 64 72  220 64 72  24 32 48   24 32 48
24 32 48   24 32 48   220 64 72  220 64 72  220 64 72  220 64 72  24 32 48   24 32 48
24 32 48   24 32 48   24 32 48   24 32 48   24 32 48   24 32 48   24 32 48   24 32 48
24 32 48   24 32 48   24 32 48   24 32 48   24 32 48   24 32 48   24 32 48   24 32 48
'@
}

function Normalize-Text {
	param([string]$Text)
	return ($Text -replace "`r`n", "`n").TrimEnd()
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonRoot = Resolve-Path (Join-Path $scriptRoot "..")
$fixtureDir = Join-Path $addonRoot "tests\fixtures"
$expectedFixture = Join-Path $fixtureDir "sam-point-square.ppm"
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
	$OutputDir = Join-Path ([System.IO.Path]::GetTempPath()) "ofxGgmlSam-fixtures"
}
$generatedFixture = Join-Path $OutputDir "sam-point-square.ppm"

if ($DryRun) {
	Write-Step "SAM fixture generation plan"
	Write-Host "  output dir: $OutputDir"
	Write-Host "  fixture: $generatedFixture"
	Write-Host "  verify: $(if ($Verify) { 'ON' } else { 'OFF' })"
	Write-Host "  clean: $(if ($Clean) { 'ON' } else { 'OFF' })"
	Write-Step "Dry run complete; no files were changed"
	return
}

if ($Clean -and (Test-Path -LiteralPath $OutputDir)) {
	Write-Step "Cleaning $OutputDir"
	Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

Write-Step "Generating SAM fixture images"
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($generatedFixture, (Get-SamPointSquarePpm) + "`n", $utf8NoBom)

if ($Verify) {
	Write-Step "Verifying generated fixtures"
	if (!(Test-Path -LiteralPath $expectedFixture -PathType Leaf)) {
		throw "Committed fixture was not found: $expectedFixture"
	}
	$expected = [System.IO.File]::ReadAllText($expectedFixture)
	$actual = [System.IO.File]::ReadAllText($generatedFixture)
	if ((Normalize-Text $expected) -ne (Normalize-Text $actual)) {
		throw "Generated sam-point-square.ppm did not match the committed fixture."
	}
}

Write-Step "SAM fixture generation passed"
