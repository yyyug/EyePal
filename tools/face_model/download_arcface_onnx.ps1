param(
    [string]$OutDir = "tools\face_model\models"
)

$ErrorActionPreference = "Stop"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$zipUrl = "https://github.com/deepinsight/insightface/releases/download/v0.7/buffalo_sc.zip"
$zipPath = Join-Path $OutDir "buffalo_sc.zip"
$extractDir = Join-Path $OutDir "buffalo_sc"
$outFile = Join-Path $OutDir "w600k_mbf.onnx"

if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}
if (Test-Path $extractDir) {
    Remove-Item $extractDir -Recurse -Force
}

Write-Host "Downloading InsightFace buffalo_sc model pack..."
Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath
Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

$model = Get-ChildItem -Path $extractDir -Filter "w600k_mbf.onnx" -Recurse | Select-Object -First 1
if (-not $model) {
    throw "w600k_mbf.onnx not found in buffalo_sc.zip"
}
Copy-Item $model.FullName $outFile -Force
Remove-Item $zipPath -Force
Remove-Item $extractDir -Recurse -Force
Write-Host "Saved model to $outFile"
