param(
	[string] $Model = $env:OFXGGML_SAM_MODEL,
	[switch] $Json,
	[switch] $SummaryOnly,
	[switch] $Strict
)

$ErrorActionPreference = "Stop"

function Get-FamilyHint {
	param([string] $Name)

	if ($Name -match "edgetam") { return "edgetam" }
	if ($Name -match "sam3") { return "sam3" }
	if ($Name -match "sam2") { return "sam2" }
	if ($Name -match "mobile.?sam") { return "mobile-sam" }
	if ($Name -match "sam") { return "sam" }
	return "unknown"
}

function ConvertTo-ModelRecord {
	param(
		[System.IO.FileInfo] $File,
		[string] $Source
	)

	$family = Get-FamilyHint -Name $File.Name
	$runtimeSmokeCandidate = $File.Extension -ieq ".ggml" -and $File.Name -match "(sam3|sam2|edgetam)"
	[ordered] @{
		Name = $File.Name
		Path = $File.FullName
		Directory = $File.DirectoryName
		Extension = $File.Extension.ToLowerInvariant()
		Bytes = $File.Length
		FamilyHint = $family
		Source = $Source
		RuntimeSmokeCandidate = [bool] $runtimeSmokeCandidate
	}
}

function Get-SearchDirectories {
	param([string] $AddonRoot)

	@(
		(Join-Path $AddonRoot "ofxGgmlSamPointExample\bin\data\models"),
		(Join-Path $AddonRoot "ofxGgmlSamPointExample\bin\data"),
		(Join-Path $AddonRoot "models"),
		(Join-Path (Split-Path -Parent $AddonRoot) "models")
	)
}

function Resolve-OptionalModel {
	param([string] $Path)

	if ([string]::IsNullOrWhiteSpace($Path)) {
		return $null
	}
	$expanded = [Environment]::ExpandEnvironmentVariables($Path)
	if ([System.IO.Path]::IsPathRooted($expanded)) {
		return $expanded
	}
	return Join-Path $addonRoot $expanded
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonRoot = (Resolve-Path (Join-Path $scriptRoot "..")).Path
$searchDirectories = Get-SearchDirectories -AddonRoot $addonRoot
$existingDirectories = @($searchDirectories | Where-Object { Test-Path -LiteralPath $_ -PathType Container })
$records = New-Object System.Collections.Generic.List[object]

foreach ($directory in $existingDirectories) {
	$files = Get-ChildItem -LiteralPath $directory -File -ErrorAction SilentlyContinue |
		Where-Object {
			($_.Extension -ieq ".ggml" -or $_.Extension -ieq ".gguf") -and
			$_.Name -match "(sam|edgetam)"
		} |
		Sort-Object Name
	foreach ($file in $files) {
		$records.Add((ConvertTo-ModelRecord -File $file -Source "search"))
	}
}

$envModelPath = Resolve-OptionalModel -Path $Model
$envModelRecord = $null
if (-not [string]::IsNullOrWhiteSpace($envModelPath) -and (Test-Path -LiteralPath $envModelPath -PathType Leaf)) {
	$envModelRecord = ConvertTo-ModelRecord -File (Get-Item -LiteralPath $envModelPath) -Source "OFXGGML_SAM_MODEL"
}

$runtimeCandidates = @($records | Where-Object { $_.RuntimeSmokeCandidate })
$effectiveModel = if ($envModelRecord) {
	$envModelRecord.Path
} elseif ($runtimeCandidates.Count -gt 0) {
	$runtimeCandidates[0].Path
} else {
	""
}

$summary = [ordered] @{
	SearchDirectoryCount = $searchDirectories.Count
	ExistingSearchDirectoryCount = $existingDirectories.Count
	ModelCount = $records.Count
	RuntimeSmokeCandidateCount = $runtimeCandidates.Count
	HasEnvironmentModel = $null -ne $envModelRecord
	HasRuntimeSmokeCandidate = $runtimeCandidates.Count -gt 0
	EffectiveModel = $effectiveModel
	Ready = -not [string]::IsNullOrWhiteSpace($effectiveModel)
}

$modelsOutput = @()
if (-not $SummaryOnly) {
	$modelsOutput = @($records.ToArray())
}

$result = [ordered] @{
	Name = "ofxGgmlSam model discovery"
	Root = $addonRoot
	EnvironmentModel = $envModelRecord
	Summary = $summary
	SearchDirectories = @($searchDirectories | ForEach-Object {
		[ordered] @{
			Path = $_
			Exists = (Test-Path -LiteralPath $_ -PathType Container)
		}
	})
	Models = $modelsOutput
	NextCommands = @(
		"scripts\list-models.bat -Json -SummaryOnly",
		"scripts\run-sam3-runtime-smoke.bat -DryRun",
		"scripts\run-sam3-runtime-smoke.bat -Backend cpu -Json -SummaryOnly"
	)
}

if ($Json) {
	$result | ConvertTo-Json -Depth 6
} else {
	Write-Host "ofxGgmlSam model discovery"
	Write-Host "Root:       $addonRoot"
	Write-Host "Ready:      $($summary.Ready)"
	Write-Host "Effective:  $effectiveModel"
	Write-Host "Search directories:"
	foreach ($directory in $result.SearchDirectories) {
		Write-Host "  [$($directory.Exists)] $($directory.Path)"
	}
	if ($envModelRecord) {
		Write-Host "Environment model:"
		Write-Host "  $($envModelRecord.Name) ($($envModelRecord.FamilyHint), $($envModelRecord.Extension))"
		Write-Host "  $($envModelRecord.Path)"
	}
	if (-not $SummaryOnly) {
		Write-Host "Discovered models:"
		if ($records.Count -eq 0) {
			Write-Host "  none"
		} else {
			foreach ($modelRecord in $records) {
				$marker = if ($modelRecord.RuntimeSmokeCandidate) { "runtime" } else { "candidate" }
				Write-Host "  [$marker] $($modelRecord.Name) ($($modelRecord.FamilyHint), $($modelRecord.Extension))"
				Write-Host "    $($modelRecord.Path)"
			}
		}
	}
	Write-Host "Next:       scripts\run-sam3-runtime-smoke.bat -DryRun"
}

if ($Strict -and -not $summary.Ready) {
	throw "No SAM model was found. Set OFXGGML_SAM_MODEL or place a .ggml SAM3/SAM2/EdgeTAM model under ofxGgmlSamPointExample\bin\data\models."
}
