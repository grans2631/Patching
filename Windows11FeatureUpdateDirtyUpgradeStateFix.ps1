[CmdletBinding()]
param(
    [switch]$RunRestoreHealth = $true,
    [switch]$RunSfc = $true,
    [switch]$ClearWindowsUpdateCache = $true,
    [switch]$ClearUpgradeFolders = $true
)

function Write-Section {
    param([string]$Title)

    Write-Output ""
    Write-Output "============================================================"
    Write-Output $Title
    Write-Output "============================================================"
}

$Issues = @()
$Actions = @()

Write-Section "WINDOWS FEATURE UPDATE REMEDIATION"
Write-Output "Computer: $env:COMPUTERNAME"
Write-Output "Start   : $(Get-Date)"

# =========================
# ENHANCED PENDING REBOOT CHECK
# =========================
try {
    $PendingRebootReasons = @()

    # High-confidence reboot indicators
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
        $PendingRebootReasons += 'CBS RebootPending'
    }

    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootInProgress') {
        $PendingRebootReasons += 'CBS RebootInProgress'
    }

    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
        $PendingRebootReasons += 'Windows Update RebootRequired'
    }

    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\PostRebootReporting') {
        $PendingRebootReasons += 'Windows Update PostRebootReporting'
    }

    if (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\JoinDomain') {
        $PendingRebootReasons += 'Domain Join Pending'
    }

    if (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\AvoidSpnSet') {
        $PendingRebootReasons += 'Domain Join SPN Pending'
    }

    # Computer rename pending
    try {
        $ActiveName = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' -ErrorAction Stop).ComputerName
        $PendingName = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -ErrorAction Stop).ComputerName

        if ($ActiveName -and $PendingName -and $ActiveName -ne $PendingName) {
            $PendingRebootReasons += "Computer Rename Pending ($ActiveName -> $PendingName)"
        }
    }
    catch {}

    # Lower-confidence indicator
    $PendingFileRenameCount = 0
    try {
        $PendingFileRename = (Get-ItemProperty `
            -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' `
            -Name PendingFileRenameOperations `
            -ErrorAction SilentlyContinue).PendingFileRenameOperations

        if ($PendingFileRename) {
            $PendingFileRenameCount = @($PendingFileRename).Count
        }
    }
    catch {}

    # Only count PendingFileRenameOperations as a warning/detail, not automatic failure
    if ($PendingRebootReasons.Count -gt 0) {
        $Issues += "PENDING_REBOOT ($($PendingRebootReasons -join '; '))"
    }
    elseif ($PendingFileRenameCount -gt 0) {
        $Issues += "PENDING_FILE_RENAME_ONLY ($PendingFileRenameCount entries)"
    }
}
catch {
    $Issues += "REBOOT_CHECK_FAILED"
}

# =========================
# Stop Windows Update services
# =========================
Write-Section "STOPPING UPDATE SERVICES"

$Services = @('wuauserv', 'bits', 'cryptsvc', 'msiserver')

foreach ($Service in $Services) {
    try {
        $Svc = Get-Service -Name $Service -ErrorAction SilentlyContinue

        if ($Svc -and $Svc.Status -ne 'Stopped') {
            Write-Output "Stopping service: $Service"
            Stop-Service -Name $Service -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
            $Actions += "Stopped $Service"
        }
        else {
            Write-Output "Service already stopped or not found: $Service"
        }
    }
    catch {
        Write-Output "Failed to stop service $Service : $($_.Exception.Message)"
    }
}

# =========================
# Clear Windows Update cache
# =========================
if ($ClearWindowsUpdateCache) {
    Write-Section "CLEARING WINDOWS UPDATE CACHE"

    $CachePaths = @(
        'C:\Windows\SoftwareDistribution\Download',
        'C:\Windows\SoftwareDistribution\DataStore',
        'C:\Windows\System32\catroot2'
    )

    foreach ($Path in $CachePaths) {
        if (Test-Path $Path) {
            try {
                Write-Output "Clearing: $Path"

                $BackupPath = "$Path.old_$(Get-Date -Format 'yyyyMMddHHmmss')"

                Rename-Item -Path $Path -NewName (Split-Path $BackupPath -Leaf) -Force -ErrorAction Stop

                Write-Output "Renamed to: $BackupPath"
                $Actions += "Renamed $Path"
            }
            catch {
                Write-Output "Failed to rename $Path : $($_.Exception.Message)"
            }
        }
        else {
            Write-Output "Path not found: $Path"
        }
    }
}

# =========================
# Clear previous upgrade folders
# =========================
if ($ClearUpgradeFolders) {
    Write-Section "CLEARING PREVIOUS FEATURE UPDATE FOLDERS"

    $UpgradeFolders = @(
        'C:\$WINDOWS.~BT',
        'C:\$WINDOWS.~WS'
    )

    foreach ($Folder in $UpgradeFolders) {
        if (Test-Path $Folder) {
            try {
                Write-Output "Removing: $Folder"
                Remove-Item -Path $Folder -Recurse -Force -ErrorAction Stop
                Write-Output "Removed: $Folder"
                $Actions += "Removed $Folder"
            }
            catch {
                Write-Output "Failed to remove $Folder : $($_.Exception.Message)"
            }
        }
        else {
            Write-Output "Folder not found: $Folder"
        }
    }
}

# =========================
# Start services back up
# =========================
Write-Section "STARTING UPDATE SERVICES"

foreach ($Service in $Services) {
    try {
        $Svc = Get-Service -Name $Service -ErrorAction SilentlyContinue

        if ($Svc -and $Svc.Status -ne 'Running') {
            Write-Output "Starting service: $Service"
            Start-Service -Name $Service -ErrorAction SilentlyContinue
            $Actions += "Started $Service"
        }
    }
    catch {
        Write-Output "Failed to start service $Service : $($_.Exception.Message)"
    }
}

# =========================
# DISM CheckHealth
# =========================
Write-Section "DISM CHECKHEALTH"

try {
    $DismCheck = DISM /Online /Cleanup-Image /CheckHealth 2>&1
    $DismText = $DismCheck -join "`n"
    $DismCheck | ForEach-Object { Write-Output $_ }

    if ($DismText -match 'The component store is repairable') {
        $Issues += "DISM_REPAIRABLE"
        Write-Output "DISM detected repairable component store corruption."
    }
    elseif ($DismText -match 'The component store cannot be repaired') {
        $Issues += "DISM_NOT_REPAIRABLE"
        Write-Output "DISM detected non-repairable component store corruption."
    }
    elseif ($DismText -match 'No component store corruption detected') {
        Write-Output "DISM CheckHealth passed."
    }
}
catch {
    $Issues += "DISM_CHECK_FAILED"
    Write-Output "DISM CheckHealth failed: $($_.Exception.Message)"
}

# =========================
# DISM RestoreHealth
# =========================
if ($RunRestoreHealth) {
    Write-Section "DISM RESTOREHEALTH"

    try {
        DISM /Online /Cleanup-Image /RestoreHealth
        $Actions += "Ran DISM RestoreHealth"
    }
    catch {
        $Issues += "DISM_RESTOREHEALTH_FAILED"
        Write-Output "DISM RestoreHealth failed: $($_.Exception.Message)"
    }
}

# =========================
# SFC
# =========================
if ($RunSfc) {
    Write-Section "SFC SCANNOW"

    try {
        sfc /scannow
        $Actions += "Ran SFC Scannow"
    }
    catch {
        $Issues += "SFC_FAILED"
        Write-Output "SFC failed: $($_.Exception.Message)"
    }
}

# =========================
# ENHANCED PENDING REBOOT CHECK
# =========================
try {
    $PendingRebootReasons = @()

    # High-confidence reboot indicators
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
        $PendingRebootReasons += 'CBS RebootPending'
    }

    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootInProgress') {
        $PendingRebootReasons += 'CBS RebootInProgress'
    }

    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
        $PendingRebootReasons += 'Windows Update RebootRequired'
    }

    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\PostRebootReporting') {
        $PendingRebootReasons += 'Windows Update PostRebootReporting'
    }

    if (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\JoinDomain') {
        $PendingRebootReasons += 'Domain Join Pending'
    }

    if (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\AvoidSpnSet') {
        $PendingRebootReasons += 'Domain Join SPN Pending'
    }

    # Computer rename pending
    try {
        $ActiveName = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' -ErrorAction Stop).ComputerName
        $PendingName = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -ErrorAction Stop).ComputerName

        if ($ActiveName -and $PendingName -and $ActiveName -ne $PendingName) {
            $PendingRebootReasons += "Computer Rename Pending ($ActiveName -> $PendingName)"
        }
    }
    catch {}

    # Lower-confidence indicator
    $PendingFileRenameCount = 0
    try {
        $PendingFileRename = (Get-ItemProperty `
            -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' `
            -Name PendingFileRenameOperations `
            -ErrorAction SilentlyContinue).PendingFileRenameOperations

        if ($PendingFileRename) {
            $PendingFileRenameCount = @($PendingFileRename).Count
        }
    }
    catch {}

    # Only count PendingFileRenameOperations as a warning/detail, not automatic failure
    if ($PendingRebootReasons.Count -gt 0) {
        $Issues += "PENDING_REBOOT ($($PendingRebootReasons -join '; '))"
    }
    elseif ($PendingFileRenameCount -gt 0) {
        $Issues += "PENDING_FILE_RENAME_ONLY ($PendingFileRenameCount entries)"
    }
}
catch {
    $Issues += "REBOOT_CHECK_FAILED"
}

# =========================
# Summary
# =========================
Write-Section "REMEDIATION SUMMARY"

Write-Output "Actions performed:"
if ($Actions.Count -gt 0) {
    $Actions | Sort-Object -Unique | ForEach-Object {
        Write-Output "- $_"
    }
}
else {
    Write-Output "- No major cleanup actions were performed."
}

Write-Output ""
Write-Output "Remaining / detected issues:"
if ($Issues.Count -gt 0) {
    $Issues | Sort-Object -Unique | ForEach-Object {
        Write-Output "- $_"
    }
}
else {
    Write-Output "- None detected."
}

Write-Output ""
Write-Output "Recommendation:"
if ($StillPendingReboot) {
    Write-Output "- Reboot the machine before retrying the Windows 11 feature update."
}
elseif ($Issues -contains "DISM_NOT_REPAIRABLE") {
    Write-Output "- Do not retry the upgrade yet. Use an ISO source repair or consider in-place repair/reimage."
}
elseif ($Issues -contains "DISM_RESTOREHEALTH_FAILED") {
    Write-Output "- Do not retry the upgrade yet. DISM repair failed."
}
else {
    Write-Output "- Retry the feature update using ISO-based setup instead of Windows Upgrade Assistant."
    Write-Output "- Recommended command: setup.exe /auto upgrade /dynamicupdate disable"
}

Write-Output ""
Write-Output "End: $(Get-Date)"

if ($Issues.Count -gt 0) {
    exit 2
}

exit 0
