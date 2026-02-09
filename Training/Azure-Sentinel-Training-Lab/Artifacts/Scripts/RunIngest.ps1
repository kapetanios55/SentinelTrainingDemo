param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$Location,

    [Parameter(Mandatory = $true)]
    [string]$WorkspaceName,

    [string]$RepoZipUrl = "https://github.com/kapetanios55/SentinelTrainingDemo/archive/refs/heads/demo-only.zip",
    [string]$RepoRootName = "SentinelTrainingDemo-demo-only"
)

$ErrorActionPreference = "Stop"

Import-Module Az.Accounts -ErrorAction Stop
Connect-AzAccount -Identity | Out-Null

$workdir = Join-Path -Path $env:TEMP -ChildPath "sentinel-training-demo"
$repoZip = Join-Path -Path $workdir -ChildPath "repo.zip"
$repoDir = Join-Path -Path $workdir -ChildPath $RepoRootName
$scriptPath = Join-Path -Path $repoDir -ChildPath "Training/Azure-Sentinel-Training-Lab/Artifacts/Scripts/IngestCSV.ps1"

if (-not (Test-Path -Path $workdir)) {
    New-Item -ItemType Directory -Path $workdir | Out-Null
}

Invoke-WebRequest -Uri $RepoZipUrl -OutFile $repoZip
if (Test-Path -Path $repoDir) {
    Remove-Item -Recurse -Force $repoDir
}
Expand-Archive -Path $repoZip -DestinationPath $workdir -Force

$customTelemetryPath = Join-Path -Path $repoDir -ChildPath "Training/Azure-Sentinel-Training-Lab/Artifacts/Telemetry/Custom"
$builtInTelemetryPath = Join-Path -Path $repoDir -ChildPath "Training/Azure-Sentinel-Training-Lab/Artifacts/Telemetry/BuildIn"
$templatesPath = Join-Path -Path $workdir -ChildPath "DCRTemplates"
if (-not (Test-Path -Path $templatesPath)) {
    New-Item -ItemType Directory -Path $templatesPath | Out-Null
}

& $scriptPath \
    -SubscriptionId $SubscriptionId \
    -ResourceGroupName $ResourceGroupName \
    -Location $Location \
    -WorkspaceName $WorkspaceName \
    -TelemetryPath $customTelemetryPath \
    -BuiltInTelemetryPath $builtInTelemetryPath \
    -TemplatesOutputPath $templatesPath \
    -DeployBuiltInDcr \
    -Deploy \
    -Ingest
