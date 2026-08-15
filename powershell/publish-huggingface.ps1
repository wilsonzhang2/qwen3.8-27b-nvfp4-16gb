param(
    [string]$VmHost = "ai@192.168.10.101",
    [string]$RemoteDir = "/home/ai/qwen38-publish",
    [string]$GitHubRepo = "wilsonzhang2/qwen3.8-27b-nvfp4-16gb"
)

$ErrorActionPreference = "Stop"

function Require-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name is required but was not found."
    }
}

function Assert-Exit([string]$Action) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Action failed with exit code $LASTEXITCODE."
    }
}

Require-Command "ssh"
Require-Command "scp"

$Temp = Join-Path $env:TEMP "qwen38-hf-publish"
if (Test-Path $Temp) {
    Remove-Item $Temp -Recurse -Force
}
New-Item -ItemType Directory -Path $Temp | Out-Null

$RawBase = "https://raw.githubusercontent.com/$GitHubRepo/main"
$Downloads = @{
    "README.md" = "$RawBase/huggingface/README.md"
    "NOTICE" = "$RawBase/NOTICE"
    "ATTRIBUTION.md" = "$RawBase/ATTRIBUTION.md"
    "publish-huggingface.sh" = "$RawBase/scripts/publish-huggingface.sh"
}

Write-Host "Downloading the validated publication package from GitHub..."
foreach ($Name in $Downloads.Keys) {
    $Destination = Join-Path $Temp $Name
    Invoke-WebRequest -Uri $Downloads[$Name] -OutFile $Destination -UseBasicParsing
    if (-not (Test-Path $Destination)) {
        throw "Download failed: $Name"
    }
}

Write-Host "Preparing VM101 staging directory..."
& ssh $VmHost "rm -rf '$RemoteDir' && mkdir -p '$RemoteDir'"
Assert-Exit "create remote staging directory"

Write-Host "Copying model card, notices, and uploader to VM101..."
foreach ($Name in $Downloads.Keys) {
    & scp (Join-Path $Temp $Name) "${VmHost}:${RemoteDir}/${Name}"
    Assert-Exit "scp $Name"
}

Write-Host ""
Write-Host "Starting validated Hugging Face publication on VM101."
Write-Host "If Hugging Face asks for authentication, enter a WRITE token when prompted."
Write-Host "Large GGUF upload time depends on upstream bandwidth; interrupted hf uploads can be run again."
Write-Host ""

& ssh -t $VmHost "chmod +x '$RemoteDir/publish-huggingface.sh' && WORK_DIR='$RemoteDir' '$RemoteDir/publish-huggingface.sh'"
Assert-Exit "Hugging Face publication"

$HfUrl = (& ssh $VmHost "cat '$RemoteDir/HF_REPO_URL.txt'").Trim()
Assert-Exit "read Hugging Face repository URL"

Write-Host ""
Write-Host "===== SHA256SUMS ====="
& ssh $VmHost "cat '$RemoteDir/SHA256SUMS'"
Assert-Exit "read SHA256SUMS"

Write-Host ""
Write-Host "Publication completed."
Write-Host "GitHub:      https://github.com/$GitHubRepo"
Write-Host "HuggingFace: $HfUrl"
