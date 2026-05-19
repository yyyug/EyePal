param(
    [string]$Workflow = "ios-unsigned-build.yml",
    [string]$ArtifactName = "EyePal-unsigned-ipa",
    [string]$Branch = "main",
    [Nullable[int64]]$RunId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Require-Command {
    param([string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $Name"
    }
}

Require-Command git
Require-Command gh

$repoRoot = (git rev-parse --show-toplevel).Trim()
if (-not $repoRoot) {
    throw "Unable to determine repository root. Run this script inside the EyePal git repository."
}

Push-Location $repoRoot
try {
    $ghAuth = gh auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "GitHub CLI is not authenticated. Run 'gh auth login' first."
    }

    if (-not $RunId) {
        $runJson = gh run list --workflow $Workflow --branch $Branch --status completed --limit 20 --json databaseId,conclusion,createdAt 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to query workflow runs for $Workflow on branch $Branch.`n$runJson"
        }

        $runs = $runJson | ConvertFrom-Json
        $successfulRun = $runs |
            Where-Object { $_.conclusion -eq "success" } |
            Sort-Object createdAt -Descending |
            Select-Object -First 1

        if (-not $successfulRun) {
            throw "No successful runs found for workflow '$Workflow' on branch '$Branch'."
        }

        $RunId = [int64]$successfulRun.databaseId
    }

    $artifactsRoot = Join-Path $repoRoot "artifacts-ipa"
    $runDir = Join-Path $artifactsRoot ("run-" + $RunId)
    $latestRunDir = Join-Path $artifactsRoot "latest-run"
    $latestSuccessDir = Join-Path $artifactsRoot "latest-success"
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("eyepal-ipa-" + [guid]::NewGuid().ToString("N"))

    New-Item -ItemType Directory -Force -Path $artifactsRoot, $latestRunDir, $latestSuccessDir, $tempDir | Out-Null
    if (Test-Path $runDir) {
        Remove-Item -Recurse -Force $runDir
    }
    New-Item -ItemType Directory -Force -Path $runDir | Out-Null

    try {
        $downloadOutput = gh run download $RunId --name $ArtifactName --dir $tempDir 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to download artifact '$ArtifactName' from run $RunId.`n$downloadOutput"
        }

        $ipa = Get-ChildItem -Path $tempDir -Recurse -Filter *.ipa | Select-Object -First 1
        if (-not $ipa) {
            throw "Artifact '$ArtifactName' from run $RunId did not contain an IPA file."
        }

        $runIpa = Join-Path $runDir $ipa.Name
        $latestRunIpa = Join-Path $latestRunDir $ipa.Name
        $latestSuccessIpa = Join-Path $latestSuccessDir $ipa.Name

        Copy-Item -Force $ipa.FullName $runIpa
        Copy-Item -Force $ipa.FullName $latestRunIpa
        Copy-Item -Force $ipa.FullName $latestSuccessIpa

        Write-Host "Downloaded artifact from run $RunId"
        Write-Host "Run artifact: $runIpa"
        Write-Host "Latest run:   $latestRunIpa"
        Write-Host "Latest good:  $latestSuccessIpa"
    }
    finally {
        if (Test-Path $tempDir) {
            Remove-Item -Recurse -Force $tempDir
        }
    }
}
finally {
    Pop-Location
}