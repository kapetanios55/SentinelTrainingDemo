param(
    [string]$SubscriptionId,

    [string]$ResourceGroupName,

    [string]$WorkspaceName,

    [string]$RepoZipUrl = "https://github.com/kapetanios55/SentinelTrainingDemo/archive/refs/heads/master.zip",
    [string]$RepoRootName = "SentinelTrainingDemo-master"
)

$ErrorActionPreference = "Stop"

Import-Module Az.Accounts -ErrorAction Stop
Connect-AzAccount -Identity | Out-Null

function Get-OptionalAutomationVariableValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    try {
        return Get-AutomationVariable -Name $Name
    }
    catch {
        return $null
    }
}

function ConvertTo-RunbookStringValue {
    param(
        [AllowNull()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return $null
    }

    $trimmed = $Value.Trim()
    return $trimmed.Trim('"')
}

if (-not $SubscriptionId) {
    $SubscriptionId = Get-OptionalAutomationVariableValue -Name 'SentinelTrainingSubscriptionId'
}
if (-not $ResourceGroupName) {
    $ResourceGroupName = Get-OptionalAutomationVariableValue -Name 'SentinelTrainingResourceGroupName'
}
if (-not $WorkspaceName) {
    $WorkspaceName = Get-OptionalAutomationVariableValue -Name 'SentinelTrainingWorkspaceName'
}

if (-not $SubscriptionId) {
    $context = Get-AzContext
    if ($context -and $context.Subscription -and $context.Subscription.Id) {
        $SubscriptionId = $context.Subscription.Id
    }
}

$SubscriptionId = ConvertTo-RunbookStringValue -Value $SubscriptionId
$ResourceGroupName = ConvertTo-RunbookStringValue -Value $ResourceGroupName
$WorkspaceName = ConvertTo-RunbookStringValue -Value $WorkspaceName

if (-not $SubscriptionId -or -not $ResourceGroupName -or -not $WorkspaceName) {
    throw "Missing required runbook parameters. Provide SubscriptionId/ResourceGroupName/WorkspaceName via jobSchedule parameters or set Automation variables: SentinelTrainingSubscriptionId, SentinelTrainingResourceGroupName, SentinelTrainingWorkspaceName."
}

$workdir = Join-Path -Path $env:TEMP -ChildPath "sentinel-training-demo"
$repoZip = Join-Path -Path $workdir -ChildPath "repo.zip"
$repoDir = Join-Path -Path $workdir -ChildPath $RepoRootName
$scriptPath = Join-Path -Path $repoDir -ChildPath "Training/Azure-Sentinel-Training-Lab/Artifacts/Scripts/IngestCSV.ps1"

if (-not (Test-Path -Path $workdir)) {
    New-Item -ItemType Directory -Path $workdir | Out-Null
}

$maxAttempts = 4
for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    try {
        Invoke-WebRequest -Uri $RepoZipUrl -OutFile $repoZip -UseBasicParsing
        break
    } catch {
        if ($attempt -eq $maxAttempts) {
            throw "Failed to download repo ZIP after $maxAttempts attempts. Last error: $_"
        }
        $delay = [math]::Min(30, [math]::Pow(2, $attempt))
        Write-Warning "Download attempt $attempt failed: $($_.Exception.Message). Retrying in ${delay}s..."
        Start-Sleep -Seconds $delay
    }
}
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

$ingestArgs = @{
    SubscriptionId = $SubscriptionId
    ResourceGroupName = $ResourceGroupName
    WorkspaceName = $WorkspaceName
    TelemetryPath = $customTelemetryPath
    BuiltInTelemetryPath = $builtInTelemetryPath
    TemplatesOutputPath = $templatesPath
    DeployBuiltInDcr = $true
    Deploy = $true
    Ingest = $true
}

& $scriptPath @ingestArgs
