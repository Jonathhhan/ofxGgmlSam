$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$doctorScript = Join-Path $scriptRoot "doctor-sam.ps1"

$output = & $doctorScript *>&1 | ForEach-Object { $_.ToString() }
if (!$?) {
	throw "doctor-sam.ps1 failed."
}

$text = $output -join "`n"
foreach ($expected in @(
	"ofxGgmlSam doctor",
	"ofxGgmlCore sibling",
	"point example",
	"selected backend",
	"SAM adapter executable",
	"sam.cpp adapter header",
	"sam3.cpp adapter header",
	"external adapter contract dry-run",
	"artifact hygiene"
)) {
	if ($text -notmatch [regex]::Escape($expected)) {
		throw "doctor output did not contain expected text: $expected"
	}
}

$jsonOutput = & $doctorScript -Json *>&1 | ForEach-Object { $_.ToString() }
if (!$?) {
	throw "doctor-sam.ps1 -Json failed."
}

$parsed = ($jsonOutput -join "`n") | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace([string]$parsed.Root)) {
	throw "doctor JSON output did not include Root."
}
if (!$parsed.Checks -or $parsed.Checks.Count -eq 0) {
	throw "doctor JSON output did not include checks."
}

$sam3Json = & $doctorScript -Json -Backend "sam3.cpp" *>&1 | ForEach-Object { $_.ToString() }
if (!$?) {
	throw "doctor-sam.ps1 -Json -Backend sam3.cpp failed."
}

$sam3Parsed = ($sam3Json -join "`n") | ConvertFrom-Json
$sam3CheckText = ($sam3Parsed.Checks | ForEach-Object { $_.Name }) -join "`n"
foreach ($expected in @("selected backend", "sam3.cpp local checkout", "sam3.cpp CPU build")) {
	if ($sam3CheckText -notmatch [regex]::Escape($expected)) {
		throw "sam3 doctor JSON output did not contain expected check: $expected"
	}
}
