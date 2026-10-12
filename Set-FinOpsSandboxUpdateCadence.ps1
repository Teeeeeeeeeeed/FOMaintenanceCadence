<#
.SYNOPSIS
    Interactively signs in to a Power Platform tenant, lists every Finance &
    Operations environment and its maintenance settings, then lets you set the
    major-version update cadence for all F&O sandbox environments.

.DESCRIPTION
    Uses the pac CLI (https://aka.ms/PowerPlatformCLI) to:
      1. Sign in interactively (pac auth create) - a browser window opens so you
         can authenticate with whatever user/MFA method and tenant you need.
      2. pac admin list --application msdyn_FinanceAndOperationsProvisioningAppAnchor
            (find every F&O-provisioned environment in the signed-in tenant)
      3. pac dynamics get-fin-ops-maintenance-settings --environment <id>
            (read current maintenance cadence / days-of-week per environment)
      4. Prompt you to choose: close without changes, set cadence to
         "EveryOtherUpdate", or set cadence to "EveryUpdate" - applied to every
         F&O Sandbox environment found.
      5. pac dynamics update-fin-ops-maintenance-settings (if you chose to apply)
         then re-list all environments so you can confirm the new values.

    NOTE: the F&O maintenance-settings API only exposes cadence and days-of-week.
    There is no "maintenance window hours" field in the API/CLI, so that column
    is shown as "n/a".

    This script contains no tenant-specific URLs, IDs, or credentials - every
    value is discovered live from whichever tenant you sign in to.

.PARAMETER TenantId
    Optional Microsoft Entra ID tenant ID or domain to sign in to. If omitted,
    the sign-in dialog lets you pick/enter the account and tenant yourself.

.PARAMETER DeviceCode
    Use the device-code sign-in flow instead of the interactive browser popup.
    Useful on remote/headless machines.

.EXAMPLE
    .\Set-FinOpsSandboxUpdateCadence.ps1

.EXAMPLE
    .\Set-FinOpsSandboxUpdateCadence.ps1 -TenantId contoso.onmicrosoft.com

.EXAMPLE
    .\Set-FinOpsSandboxUpdateCadence.ps1 -DeviceCode
#>
[CmdletBinding()]
param(
    [string]$TenantId,

    [switch]$DeviceCode
)

$ErrorActionPreference = 'Stop'

# The F&O Provisioning App's anchor solution - present only on F&O-enabled environments.
$FinOpsAppUniqueName = 'msdyn_FinanceAndOperationsProvisioningAppAnchor'

function Invoke-Pac {
    param([string[]]$PacArgs)

    # Capture stdout/stderr separately - native-command stderr lines come back as
    # ErrorRecord objects when merged, so they can be told apart from real stdout.
    $raw = & pac @PacArgs --json 2>&1
    $exitCode = $LASTEXITCODE
    $stdOut = ($raw | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } | Out-String).Trim()
    $stdErr = ($raw | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { $_.ToString() }) -join "`n"

    if ($exitCode -ne 0) {
        throw "pac $($PacArgs -join ' ') failed (exit $exitCode):`n$stdOut`n$stdErr"
    }
    if ([string]::IsNullOrWhiteSpace($stdOut) -or ($stdOut[0] -ne '{' -and $stdOut[0] -ne '[')) {
        # pac returned exit 0 but the body isn't JSON - surface whatever it actually printed.
        throw "pac $($PacArgs -join ' ') did not return JSON. Raw output:`n$stdOut`n$stdErr"
    }
    return $stdOut | ConvertFrom-Json
}

function Connect-PacInteractive {
    if (-not (Get-Command pac -ErrorAction SilentlyContinue)) {
        throw "The pac CLI was not found on PATH. Install it from https://aka.ms/PowerPlatformCLI and try again."
    }

    Write-Host "== Sign in ==" -ForegroundColor Cyan
    Write-Host "A sign-in window will open. Authenticate with whichever user/MFA method and tenant you want to inspect." -ForegroundColor Yellow

    $authArgs = @('auth', 'create')
    if ($TenantId) { $authArgs += @('--tenant', $TenantId) }
    if ($DeviceCode) { $authArgs += '--deviceCode' }

    & pac @authArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Sign-in failed or was cancelled."
    }
}

function Assert-PacSupportsFinOps {
    # The 'dynamics' command group is a newer preview addition - older installed
    # pac CLI builds parse it as an invalid token instead of a command.
    $helpText = (& pac help 2>&1 | Out-String)
    if ($helpText -notmatch '(?m)^\s*dynamics\s') {
        throw @"
Your installed pac CLI does not include the 'dynamics' command group this script needs.
Run 'pac install latest' to update, then open a NEW terminal (so the updated binary is picked up) and re-run this script.
"@
    }
}

function Get-FinOpsEnvironmentReport {
    Write-Host "== Finding F&O environments in the tenant ==" -ForegroundColor Cyan
    $envs = Invoke-Pac @('admin', 'list', '--application', $FinOpsAppUniqueName)

    if (-not $envs -or $envs.Count -eq 0) {
        Write-Host "No F&O-provisioned environments found for the signed-in tenant." -ForegroundColor Yellow
        return @()
    }

    foreach ($e in $envs) {
        $settings = $null
        $readError = $null
        try {
            $settings = Invoke-Pac @('dynamics', 'get-fin-ops-maintenance-settings', '--environment', $e.EnvironmentId)
        }
        catch {
            $readError = $_.Exception.Message
            Write-Warning "Could not read maintenance settings for $($e.DisplayName):`n$readError"
        }

        [pscustomobject]@{
            DisplayName   = $e.DisplayName
            Type          = $e.Type
            EnvironmentId = $e.EnvironmentId
            Cadence       = if ($readError) { 'Error reading' } elseif ($settings.maintenanceWindowCadence) { $settings.maintenanceWindowCadence } else { 'Not set' }
            DaysOfWeek    = if ($readError) { 'Error reading' } elseif ($settings.maintenanceWindowDaysOfWeek) { $settings.maintenanceWindowDaysOfWeek -join ', ' } else { 'Not set' }
            Hours         = 'n/a (not exposed by API)'
        }
    }
}

function Show-FinOpsEnvironmentReport {
    param([Parameter(Mandatory)][array]$Report)
    $Report | Format-Table DisplayName, Type, Cadence, DaysOfWeek, Hours, EnvironmentId -AutoSize -Wrap
}

function Set-FinOpsSandboxCadence {
    param(
        [Parameter(Mandatory)][array]$Report,
        [Parameter(Mandatory)][ValidateSet('EveryUpdate', 'EveryOtherUpdate')][string]$Cadence
    )

    $sandboxes = $Report | Where-Object { $_.Type -eq 'Sandbox' }
    if (-not $sandboxes) {
        Write-Host "No F&O sandbox environments to update." -ForegroundColor Yellow
        return
    }

    foreach ($e in $sandboxes) {
        Write-Host "Setting cadence to '$Cadence' on $($e.DisplayName) ..." -ForegroundColor Cyan
        try {
            Invoke-Pac @('dynamics', 'update-fin-ops-maintenance-settings', '--environment', $e.EnvironmentId, '--updated-maintenance-window-cadence', $Cadence) | Out-Null
            Write-Host "  Done." -ForegroundColor Green
        }
        catch {
            Write-Warning "  Failed for $($e.DisplayName): $_"
        }
    }
}

# 1. Interactive sign-in (MFA handled by the browser/device-code flow).
Connect-PacInteractive
Assert-PacSupportsFinOps

# 2+3. List every F&O environment with its current maintenance settings.
$report = Get-FinOpsEnvironmentReport
if (-not $report -or $report.Count -eq 0) { return }
Show-FinOpsEnvironmentReport -Report $report

$cadenceByChoice = @{
    '2' = 'EveryOtherUpdate'
    '3' = 'EveryUpdate'
}

# 4+5. Repeat the menu after every refresh until the user chooses to close.
do {
    Write-Host ""
    Write-Host "What do you want to do for all F&O Sandbox environments listed above?" -ForegroundColor Cyan
    Write-Host "  1) Close (no changes)"
    Write-Host "  2) Set maintenance window cadence to 'Every other Update'"
    Write-Host "  3) Set maintenance window cadence to 'Every Update'"
    $choice = Read-Host "Enter 1, 2, or 3"

    if ($choice -in $cadenceByChoice.Keys) {
        Set-FinOpsSandboxCadence -Report $report -Cadence $cadenceByChoice[$choice]

        Write-Host ""
        Write-Host "== Refreshed F&O environment list ==" -ForegroundColor Cyan
        $report = Get-FinOpsEnvironmentReport
        Show-FinOpsEnvironmentReport -Report $report
    }
} while ($choice -in $cadenceByChoice.Keys)

Write-Host "Closing - no further changes made." -ForegroundColor Yellow
