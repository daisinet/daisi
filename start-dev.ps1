<#
.SYNOPSIS
    Starts the Daisi dev environment services in separate PowerShell windows.

.DESCRIPTION
    Launches ORC, Host, and Manager as core services, with optional CRM and Public web apps.
    Each service runs in its own PowerShell window with HTTPS configured via environment variables.

.PARAMETER crm
    Also start the Daisi Business CRM app.

.PARAMETER booksmarts
    Also start the Daisi BookSmarts app.

.PARAMETER herald
    Also start the Daisi Herald app.

.PARAMETER public
    Also start the Daisi Web Public app.

.EXAMPLE
    .\start-dev.ps1
    # Starts ORC, Host, and Manager

.EXAMPLE
    .\start-dev.ps1 -crm -booksmarts -herald -public
    # Starts all services
#>

param(
    [switch]$crm,
    [switch]$booksmarts,
    [switch]$herald,
    [switch]$public
)

$root = Resolve-Path "$PSScriptRoot/.."

function Start-DaisiApp {
    param(
        [string]$Name,
        [string]$ExeRelPath,
        [string]$Urls,
        [string]$WorkingDirRel
    )

    $exe = Join-Path $root $ExeRelPath
    $workDir = Join-Path $root $WorkingDirRel

    if (-not (Test-Path $exe)) {
        Write-Warning "Executable not found: $exe - skipping $Name. Build the project first."
        return
    }

    Write-Host "Starting $Name..." -ForegroundColor Cyan

    $cmd = "`$host.UI.RawUI.WindowTitle = '$Name'; " +
           "`$env:ASPNETCORE_ENVIRONMENT = 'Development'; " +
           "`$env:ASPNETCORE_URLS = '$Urls'; " +
           "Set-Location '$workDir'; " +
           "& '$exe'"

    Start-Process powershell -ArgumentList "-Command", $cmd
}

# Core services - always started
Start-DaisiApp -Name "Daisi ORC" `
    -ExeRelPath "daisi-orc-dotnet/Daisi.Orc.Grpc/bin/Debug/net10.0/Daisi.Orc.Grpc.exe" `
    -Urls "https://*:5001;http://*:5000" `
    -WorkingDirRel "daisi-orc-dotnet/Daisi.Orc.Grpc"

Start-Sleep -Seconds 3

Start-DaisiApp -Name "Daisi Host" `
    -ExeRelPath "daisi-hosts-dotnet/Daisi.Host.Console/bin/Debug/net10.0/Daisi.Host.Console.exe" `
    -Urls "https://localhost:4242;http://localhost:4200" `
    -WorkingDirRel "daisi-hosts-dotnet/Daisi.Host.Console"

Start-Sleep -Seconds 3

Start-DaisiApp -Name "Daisi Manager" `
    -ExeRelPath "daisi-manager-dotnet/Daisi.Manager.Web/bin/Debug/net10.0/Daisi.Manager.Web.exe" `
    -Urls "https://localhost:7150;http://localhost:5092" `
    -WorkingDirRel "daisi-manager-dotnet/Daisi.Manager.Web"

# Optional services
if ($crm) {
    Start-DaisiApp -Name "Daisi CRM" `
        -ExeRelPath "daisi-business-crm/Daisi.Business.CRM/bin/Debug/net10.0/Daisi.Business.CRM.exe" `
        -Urls "https://localhost:7200;http://localhost:5200" `
        -WorkingDirRel "daisi-business-crm/Daisi.Business.CRM"
}

if ($booksmarts) {
    Start-DaisiApp -Name "Daisi BookSmarts" `
        -ExeRelPath "daisi-business-booksmarts/BookSmarts.Web/bin/Debug/net10.0/BookSmarts.Web.exe" `
        -Urls "https://localhost:7210;http://localhost:5210" `
        -WorkingDirRel "daisi-business-booksmarts/BookSmarts.Web"
}

if ($herald) {
    Start-DaisiApp -Name "Daisi Herald" `
        -ExeRelPath "daisi-business-herald/Herald.Web/bin/Debug/net10.0/Herald.Web.exe" `
        -Urls "https://localhost:7300;http://localhost:5300" `
        -WorkingDirRel "daisi-business-herald/Herald.Web"
}

if ($public) {
    Start-DaisiApp -Name "Daisi Public" `
        -ExeRelPath "daisi-web-public/Daisi.Web.Public/bin/Debug/net10.0/Daisi.Web.Public.exe" `
        -Urls "https://localhost:7153;http://localhost:5294" `
        -WorkingDirRel "daisi-web-public/Daisi.Web.Public"
}

# Open browser tabs for web apps after a short delay for startup
Start-Sleep -Seconds 3
Write-Host "Opening browser tabs..." -ForegroundColor Cyan

Start-Process "https://localhost:7150"

if ($crm) {
    Start-Process "https://localhost:7200"
}

if ($booksmarts) {
    Start-Process "https://localhost:7210"
}

if ($herald) {
    Start-Process "https://localhost:7300"
}

if ($public) {
    Start-Process "https://localhost:7153"
}

Write-Host ""
Write-Host "Dev environment started. Close individual windows or Ctrl+C in each to stop services." -ForegroundColor Green
