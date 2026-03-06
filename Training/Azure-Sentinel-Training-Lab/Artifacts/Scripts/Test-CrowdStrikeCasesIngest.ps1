<#
.SYNOPSIS
Test script to ingest CrowdStrikeCases CSV into the workspace using
the stream name Microsoft-Sentinel-CrowdStrikeCases.

.DESCRIPTION
Deploys a DCR with outputStream = Microsoft-Sentinel-CrowdStrikeCases
and ingests the CrowdStrikeCases.csv data via the Logs Ingestion API.

.PARAMETER StreamVariant
Which output stream name to use:
  "Sentinel"  -> Microsoft-Sentinel-CrowdStrikeCases  (default)
  "Plain"     -> Microsoft-CrowdStrikeCases           (previously failed)

.EXAMPLE
.\Test-CrowdStrikeCasesIngest.ps1
.\Test-CrowdStrikeCasesIngest.ps1 -StreamVariant Plain
#>
[CmdletBinding()]
param(
    [ValidateSet("Sentinel", "Plain")]
    [string]$StreamVariant = "Sentinel"
)

# â”€â”€ Config â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
$SubscriptionId      = "4cc2b540-c855-4eef-b689-a669d97dd70d"
$ResourceGroupName   = "ak-demo"
$WorkspaceName       = "ak-secops"
$Location            = "eastus"
$DceName             = "sentinel-training-dce"
$TableName           = "CrowdStrikeCases"
$DcrName             = "test-crowdstrikecases-dcr"

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Definition
$CsvPath     = Join-Path $ScriptDir "..\Telemetry\BuildIn\CrowdStrikeCases.csv"

# â”€â”€ Output stream â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
$inputStream  = "Custom-$TableName"
$outputStream = if ($StreamVariant -eq "Sentinel") {
    "Microsoft-Sentinel$TableName"
} else {
    "Microsoft-$TableName"
}

Write-Host "=== CrowdStrikeCases Ingestion Test ===" -ForegroundColor Cyan
Write-Host "Stream variant : $StreamVariant"
Write-Host "Input stream   : $inputStream"
Write-Host "Output stream  : $outputStream"
Write-Host ""

# â”€â”€ Helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
function Assert-AzCli {
    $null = Get-Command az -ErrorAction Stop
    $account = az account show --query id -o tsv 2>$null
    if (-not $account) { throw "Not logged in. Run 'az login' first." }
    az account set --subscription $SubscriptionId | Out-Null
}

function Get-WorkspaceResourceId {
    $ws = az monitor log-analytics workspace show `
        --resource-group $ResourceGroupName `
        --workspace-name $WorkspaceName `
        --query id -o tsv
    if (-not $ws) { throw "Workspace '$WorkspaceName' not found." }
    return $ws
}

function Get-DceEndpoint {
    $dce = az monitor data-collection endpoint show `
        --name $DceName `
        --resource-group $ResourceGroupName `
        --query '{id:id, endpoint:logsIngestion.endpoint}' -o json | ConvertFrom-Json
    if (-not $dce) { throw "DCE '$DceName' not found." }
    return $dce
}

function Get-TableSchema {
    param([string]$WorkspaceResourceId, [string]$Table)
    $uri = "${WorkspaceResourceId}/tables/${Table}?api-version=2022-10-01"
    $raw = az rest --method GET --uri $uri -o json 2>$null | ConvertFrom-Json
    if (-not $raw) { return @() }
    return $raw.properties.schema.columns
}

# â”€â”€ Main â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Assert-AzCli

Write-Host "Resolving workspace..." -ForegroundColor Yellow
$workspaceResourceId = Get-WorkspaceResourceId
Write-Host "  $workspaceResourceId"

Write-Host "Resolving DCE..." -ForegroundColor Yellow
$dce = Get-DceEndpoint
$dceId = $dce.id
$ingestionEndpoint = $dce.endpoint
Write-Host "  Endpoint: $ingestionEndpoint"

# â”€â”€ Read CSV â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host "Reading CSV..." -ForegroundColor Yellow
if (-not (Test-Path $CsvPath)) { throw "CSV not found: $CsvPath" }
$data = @(Import-Csv -Path $CsvPath)
Write-Host "  $($data.Count) records"

# â”€â”€ Build column definitions from first record â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
$firstRecord = $data[0]
$columnDefs = @()
foreach ($prop in $firstRecord.PSObject.Properties) {
    $columnDefs += @{ name = $prop.Name; type = "string" }
}

# Also fetch the real table schema to build a transform
Write-Host "Fetching table schema for '$TableName'..." -ForegroundColor Yellow
$schemaColumns = Get-TableSchema -WorkspaceResourceId $workspaceResourceId -Table $TableName
if ($schemaColumns.Count -gt 0) {
    Write-Host "  Schema has $($schemaColumns.Count) columns"
    $schemaNames = $schemaColumns | ForEach-Object { $_.name }
} else {
    Write-Host "  No schema found - using passthrough transform"
    $schemaNames = @()
}

# Build transform KQL: project only columns that exist in schema
$csvColumnNames = $firstRecord.PSObject.Properties.Name
if ($schemaNames.Count -gt 0) {
    $projectCols = @()
    foreach ($col in $csvColumnNames) {
        if ($schemaNames -contains $col) {
            $projectCols += $col
        }
    }
    if ($projectCols.Count -gt 0) {
        $transformKql = "source | project " + ($projectCols -join ", ")
    } else {
        $transformKql = "source"
    }
} else {
    $transformKql = "source"
}

Write-Host "  Transform: $transformKql"

# â”€â”€ Build DCR template â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
$template = @{
    location   = $Location
    kind       = "Direct"
    properties = @{
        dataCollectionEndpointId = $dceId
        streamDeclarations       = @{
            $inputStream = @{
                columns = $columnDefs
            }
        }
        destinations = @{
            logAnalytics = @(
                @{
                    name                = "la"
                    workspaceResourceId = $workspaceResourceId
                }
            )
        }
        dataFlows = @(
            @{
                streams      = @($inputStream)
                destinations = @("la")
                transformKql = $transformKql
                outputStream = $outputStream
            }
        )
    }
}

# â”€â”€ Deploy DCR â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host "Deploying DCR '$DcrName' with outputStream='$outputStream'..." -ForegroundColor Yellow
$templateJson = $template | ConvertTo-Json -Depth 20

$dcrResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Insights/dataCollectionRules/$DcrName"
$apiVersion = "2022-06-01"
$uri = "https://management.azure.com${dcrResourceId}?api-version=$apiVersion"

$tempFile = [System.IO.Path]::GetTempFileName() + ".json"
$templateJson | Out-File -FilePath $tempFile -Encoding utf8

$dcrId = $null
try {
    $result = az rest --method PUT --uri $uri --body "@$tempFile" --headers "Content-Type=application/json" --query id -o tsv 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Host "  DCR deployment FAILED:" -ForegroundColor Red
        Write-Host "  $result"
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        exit 1
    }
    $dcrId = ($result | Select-Object -Last 1).Trim()
    Write-Host "  DCR deployed: $dcrId" -ForegroundColor Green
} catch {
    Write-Host "  DCR deployment FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    exit 1
}
Remove-Item $tempFile -Force -ErrorAction SilentlyContinue

# Get immutable ID
$immutableId = az rest --method GET --uri $uri --headers "Content-Type=application/json" --query immutableId -o tsv
Write-Host "  Immutable ID: $immutableId"

# â”€â”€ Wait for propagation â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host "Waiting 30 seconds for DCR propagation..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

# â”€â”€ Get access token â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host "Acquiring access token..." -ForegroundColor Yellow
$token = az account get-access-token --resource https://monitor.azure.com --query accessToken -o tsv

# â”€â”€ Ingest â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host "Ingesting $($data.Count) records into '$inputStream'..." -ForegroundColor Yellow

$apiVersion = "2023-01-01"
$uri = "$ingestionEndpoint/dataCollectionRules/$immutableId/streams/${inputStream}?api-version=$apiVersion"

$headers = @{
    Authorization  = "Bearer $token"
    "Content-Type" = "application/json"
}

# Convert CSV objects to plain hashtables
$records = @()
foreach ($row in $data) {
    $record = @{}
    foreach ($prop in $row.PSObject.Properties) {
        $record[$prop.Name] = $prop.Value
    }
    $records += $record
}

$payload = $records | ConvertTo-Json -Depth 20 -Compress

$maxAttempts = 3
$attempt = 0
$success = $false

while ($attempt -lt $maxAttempts) {
    $attempt++
    try {
        $null = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $payload
        Write-Host "  Ingestion SUCCEEDED!" -ForegroundColor Green
        $success = $true
        break
    } catch {
        $errMsg = $_.Exception.Message
        $responseBody = $null
        try {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $responseBody = $reader.ReadToEnd()
        } catch {}

        Write-Host "  Attempt $attempt/$maxAttempts FAILED:" -ForegroundColor Red
        Write-Host "    Error: $errMsg"
        if ($responseBody) {
            Write-Host "    Response: $responseBody"
        }

        if ($attempt -lt $maxAttempts) {
            $delay = [math]::Pow(2, $attempt) * 5
            Write-Host "    Retrying in $delay seconds..."
            Start-Sleep -Seconds $delay
        }
    }
}

if (-not $success) {
    Write-Host ""
    Write-Host "=== RESULT: FAILED ===" -ForegroundColor Red
    Write-Host "Output stream '$outputStream' did not work."
} else {
    Write-Host ""
    Write-Host "=== RESULT: SUCCESS ===" -ForegroundColor Green
    Write-Host "Output stream '$outputStream' works for CrowdStrikeCases!"
}

Write-Host ""
Write-Host "To clean up the test DCR, run:"
Write-Host "  az monitor data-collection rule delete --name $DcrName --resource-group $ResourceGroupName --yes"
