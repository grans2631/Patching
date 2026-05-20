[CmdletBinding()]
param()

function Write-Section {
    param([string]$Title)
    Write-Output ""
    Write-Output "============================================================"
    Write-Output $Title
    Write-Output "============================================================"
}

$Issues = @()

Write-Section "WINDOWS 11 FEATURE UPDATE PRE-CHECK"
Write-Output "Computer: $env:COMPUTERNAME"
Write-Output "Time    : $(Get-Date)"

# OS Info
Write-Section "OS INFORMATION"
$OSReg = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$OSInfo = [PSCustomObject]@{
    ProductName        = $OSReg.ProductName
    DisplayVersion     = $OSReg.DisplayVersion
    CurrentBuild       = $OSReg.CurrentBuild
    CurrentBuildNumber = $OSReg.CurrentBuildNumber
    UBR                = $OSReg.UBR
}
$OSInfo | Format-List

# Disk Space
Write-Section "DISK SPACE"
$CDrive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$FreeGB = [math]::Round($CDrive.FreeSpace / 1GB, 2)
$SizeGB = [math]::Round($CDrive.Size / 1GB, 2)

Write-Output "C: Size GB : $SizeGB"
Write-Output "C: Free GB : $FreeGB"

if ($FreeGB -lt 64) {
    $Issues += "LOW_DISK_SPACE: Less than 64GB free on C:"
    Write-Output "FAIL: Less than 64GB free."
}
else {
    Write-Output "PASS: Disk space looks acceptable."
}

# Pending Reboot
Write-Section "PENDING REBOOT CHECK"

$PendingReboot = $false
$RebootKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
    'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
)

if (Test-Path $RebootKeys[0]) { $PendingReboot = $true }
if (Test-Path $RebootKeys[1]) { $PendingReboot = $true }

try {
    $PendingFileRename = (Get-ItemProperty $RebootKeys[2] -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
    if ($PendingFileRename) { $PendingReboot = $true }
}
catch {}

if ($PendingReboot) {
    $Issues += "PENDING_REBOOT: System has pending reboot indicators."
    Write-Output "FAIL: Pending reboot detected."
}
else {
    Write-Output "PASS: No common pending reboot indicators found."
}

# BitLocker
Write-Section "BITLOCKER STATUS"
try {
    $BitLocker = Get-BitLockerVolume -MountPoint "C:" -ErrorAction Stop
    $BitLocker | Select-Object MountPoint, VolumeStatus, ProtectionStatus, LockStatus | Format-List

    if ($BitLocker.ProtectionStatus -eq 'On') {
        Write-Output "WARN: BitLocker is enabled. Suspend before upgrade."
        $Issues += "BITLOCKER_ENABLED: Suspend BitLocker before feature update."
    }
}
catch {
    Write-Output "Could not query BitLocker: $($_.Exception.Message)"
}

# MoSetup / Previous Upgrade State
Write-Section "SETUP / MOSETUP STATE"
$MoSetupPath = 'HKLM:\SYSTEM\Setup\MoSetup\Volatile'

if (Test-Path $MoSetupPath) {
    $MoSetup = Get-ItemProperty $MoSetupPath
    $MoSetup | Format-List

    if ($MoSetup.BoxResult -and $MoSetup.BoxResult -ne 0) {
        $Issues += "PREVIOUS_SETUP_FAILURE: MoSetup BoxResult = $($MoSetup.BoxResult)"
    }

    if ($MoSetup.SetupProgress -and $MoSetup.SetupProgress -lt 100) {
        $Issues += "INCOMPLETE_SETUP_STATE: SetupProgress = $($MoSetup.SetupProgress)"
    }
}
else {
    Write-Output "No MoSetup Volatile key found."
}

# DISM Health
Write-Section "DISM HEALTH CHECK"
try {
    $DismOutput = DISM /Online /Cleanup-Image /CheckHealth 2>&1
    $DismOutput | ForEach-Object { Write-Output $_ }

    if ($DismOutput -match "repairable|corruption|corrupt") {
        $Issues += "DISM_HEALTH: Component store corruption detected or suspected."
    }
}
catch {
    $Issues += "DISM_FAILED: DISM CheckHealth failed."
    Write-Output "DISM failed: $($_.Exception.Message)"
}

# SFC Quick Check via recent CBS indicators, not full scan
Write-Section "CBS / COMPONENT STORE RECENT ERRORS"
$CBSLog = 'C:\Windows\Logs\CBS\CBS.log'

if (Test-Path $CBSLog) {
    try {
        $CBSMatches = Select-String -Path $CBSLog -Pattern 'corrupt|repair|failed|CBS_E_INVALID_PACKAGE|0x800f0805' -CaseSensitive:$false |
            Select-Object -Last 50

        if ($CBSMatches) {
            $Issues += "CBS_WARNINGS: Recent CBS errors or repair indicators found."
            $CBSMatches | ForEach-Object { Write-Output $_.Line }
        }
        else {
            Write-Output "No recent CBS corruption indicators found in filtered search."
        }
    }
    catch {
        Write-Output "Could not read CBS log: $($_.Exception.Message)"
    }
}
else {
    Write-Output "CBS.log not found."
}

# AppX Provisioned Packages
Write-Section "APPX / PROVISIONED PACKAGE CHECK"
try {
    $Provisioned = Get-AppxProvisionedPackage -Online -ErrorAction Stop
    Write-Output "Provisioned package count: $($Provisioned.Count)"

    $SuspiciousProvisioned = $Provisioned | Where-Object {
        $_.PackageName -match 'MicrosoftWindows.Client|Microsoft.UI.Xaml|OOBE|BioEnrollment|AccountsControl|LockApp|CapturePicker'
    }

    if ($SuspiciousProvisioned) {
        Write-Output "Key provisioned packages found:"
        $SuspiciousProvisioned | Select-Object DisplayName, PackageName | Format-Table -AutoSize
    }
    else {
        $Issues += "APPX_PROVISIONING: Expected core provisioned packages not found or not visible."
        Write-Output "WARN: Expected core provisioned packages not found in provisioned package list."
    }
}
catch {
    $Issues += "APPX_PROVISIONING_QUERY_FAILED: Could not query provisioned packages."
    Write-Output "Failed to query provisioned packages: $($_.Exception.Message)"
}

# AppX Manifest Path Check
Write-Section "APPX MANIFEST PATH CHECK"
try {
    $AppxPackages = Get-AppxPackage -AllUsers -ErrorAction Stop

    $BrokenAppx = foreach ($Pkg in $AppxPackages) {
        if ($Pkg.InstallLocation) {
            $Manifest = Join-Path $Pkg.InstallLocation 'AppxManifest.xml'
            if (-not (Test-Path $Manifest)) {
                [PSCustomObject]@{
                    Name            = $Pkg.Name
                    PackageFullName = $Pkg.PackageFullName
                    InstallLocation = $Pkg.InstallLocation
                    MissingManifest = $Manifest
                }
            }
        }
    }

    if ($BrokenAppx) {
        $Issues += "BROKEN_APPX_MANIFESTS: One or more AppX packages have missing manifests."
        $BrokenAppx | Select-Object -First 50 | Format-Table -AutoSize
    }
    else {
        Write-Output "PASS: No missing AppX manifests detected from installed AppX packages."
    }
}
catch {
    $Issues += "APPX_QUERY_FAILED: Get-AppxPackage -AllUsers failed."
    Write-Output "Failed to query AppX packages: $($_.Exception.Message)"
}

# Panther Log Indicators
Write-Section "PANTHER LOG FAILURE INDICATORS"
$PantherLogs = @(
    'C:\$WINDOWS.~BT\Sources\Panther\setuperr.log',
    'C:\$WINDOWS.~BT\Sources\Panther\setupact.log',
    'C:\Windows\Panther\setuperr.log',
    'C:\Windows\Panther\setupact.log'
)

$Patterns = 'SYSPRP Failed to pre-register|CBS_E_INVALID_PACKAGE|0x800f0805|0x80070002|0xC0000400|MIG|rollback|failed|error'

foreach ($Log in $PantherLogs) {
    if (Test-Path $Log) {
        Write-Output "--- $Log ---"
        try {
            $Matches = Select-String -Path $Log -Pattern $Patterns -CaseSensitive:$false |
                Select-Object -Last 50

            if ($Matches) {
                $Issues += "PANTHER_WARNINGS: Failure indicators found in $Log"
                $Matches | ForEach-Object { Write-Output $_.Line }
            }
            else {
                Write-Output "No matching failure indicators found."
            }
        }
        catch {
            Write-Output "Could not read $Log : $($_.Exception.Message)"
        }
    }
}

# Drivers - Basic suspicious list
Write-Section "DRIVER INVENTORY - RECENT OEM DRIVERS"
try {
    $Drivers = pnputil /enum-drivers 2>&1
    $Drivers | Select-Object -Last 120 | ForEach-Object { Write-Output $_ }
}
catch {
    Write-Output "Could not enumerate drivers: $($_.Exception.Message)"
}

# Windows 11 basic hardware checks
Write-Section "BASIC WINDOWS 11 HARDWARE CHECKS"

try {
    $TPM = Get-Tpm -ErrorAction Stop
    Write-Output "TPM Present : $($TPM.TpmPresent)"
    Write-Output "TPM Ready   : $($TPM.TpmReady)"

    if (-not $TPM.TpmPresent -or -not $TPM.TpmReady) {
        $Issues += "TPM_NOT_READY: TPM missing or not ready."
    }
}
catch {
    $Issues += "TPM_QUERY_FAILED: Could not query TPM."
    Write-Output "Could not query TPM: $($_.Exception.Message)"
}

try {
    $SecureBoot = Confirm-SecureBootUEFI -ErrorAction Stop
    Write-Output "Secure Boot Enabled: $SecureBoot"

    if (-not $SecureBoot) {
        $Issues += "SECURE_BOOT_DISABLED: Secure Boot not enabled."
    }
}
catch {
    Write-Output "Could not query Secure Boot. System may be legacy BIOS or command unsupported."
    $Issues += "SECURE_BOOT_QUERY_FAILED: Secure Boot could not be confirmed."
}

# Summary
Write-Section "PRE-CHECK SUMMARY"

if ($Issues.Count -eq 0) {
    Write-Output "RESULT: PASS"
    Write-Output "No major pre-check issues detected."
    exit 0
}
else {
    Write-Output "RESULT: REVIEW_REQUIRED"
    Write-Output "Issue count: $($Issues.Count)"
    Write-Output ""

    $Issues | Sort-Object -Unique | ForEach-Object {
        Write-Output " - $_"
    }

    exit 2
}


