[CmdletBinding()]
param()

$Issues = @()
$script:PantherDetails = @()
$script:BrokenAppxDetails = @()
$script:PendingFileRenameDetails = @()

# Disk space
try {
    $CDrive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction Stop
    $FreeGB = [math]::Round($CDrive.FreeSpace / 1GB, 2)

    if ($FreeGB -lt 64) {
        $Issues += "LOW_DISK_SPACE ($FreeGB GB free)"
    }
}
catch {
    $Issues += "DISK_CHECK_FAILED"
}

# Enhanced pending reboot check
try {
    $PendingRebootReasons = @()

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

    try {
        $ActiveName = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' -ErrorAction Stop).ComputerName
        $PendingName = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -ErrorAction Stop).ComputerName

        if ($ActiveName -and $PendingName -and $ActiveName -ne $PendingName) {
            $PendingRebootReasons += "Computer Rename Pending ($ActiveName -> $PendingName)"
        }
    }
    catch {}

    try {
        $PendingFileRename = (Get-ItemProperty `
            -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' `
            -Name PendingFileRenameOperations `
            -ErrorAction SilentlyContinue).PendingFileRenameOperations

        if ($PendingFileRename) {
            $script:PendingFileRenameDetails = @($PendingFileRename)
        }
    }
    catch {}

    if ($PendingRebootReasons.Count -gt 0) {
        $Issues += "PENDING_REBOOT ($($PendingRebootReasons -join '; '))"
    }
    elseif ($script:PendingFileRenameDetails.Count -gt 0) {
        $Issues += "PENDING_FILE_RENAME_ONLY ($($script:PendingFileRenameDetails.Count) entries)"
    }
}
catch {
    $Issues += "REBOOT_CHECK_FAILED"
}

# MoSetup / failed upgrade state
try {
    $MoSetupPath = 'HKLM:\SYSTEM\Setup\MoSetup\Volatile'

    if (Test-Path $MoSetupPath) {
        $MoSetup = Get-ItemProperty $MoSetupPath -ErrorAction Stop

        if ($MoSetup.BoxResult -and $MoSetup.BoxResult -ne 0) {
            $Issues += "PREVIOUS_SETUP_FAILURE ($($MoSetup.BoxResult))"
        }

        if ($MoSetup.SetupProgress -and $MoSetup.SetupProgress -lt 100) {
            $Issues += "INCOMPLETE_SETUP_STATE ($($MoSetup.SetupProgress)%)"
        }
    }
}
catch {
    $Issues += "MOSETUP_CHECK_FAILED"
}

# DISM health
try {
    $Dism = DISM /Online /Cleanup-Image /CheckHealth 2>&1
    $DismText = $Dism -join "`n"

    if ($DismText -match 'The component store is repairable') {
        $Issues += "DISM_CORRUPTION_REPAIRABLE"
    }
    elseif ($DismText -match 'The component store cannot be repaired') {
        $Issues += "DISM_CORRUPTION_NOT_REPAIRABLE"
    }
    elseif ($DismText -match 'Error:\s*\d+') {
        $Issues += "DISM_CHECK_ERROR"
    }
}
catch {
    $Issues += "DISM_CHECK_FAILED"
}

# AppX manifest check with details
try {
    $BrokenAppx = @()
    $AppxPackages = Get-AppxPackage -AllUsers -ErrorAction Stop

    foreach ($Pkg in $AppxPackages) {
        if ($Pkg.InstallLocation) {
            $Manifest = Join-Path $Pkg.InstallLocation 'AppxManifest.xml'

            if (-not (Test-Path $Manifest)) {
                $BrokenAppx += [PSCustomObject]@{
                    Name            = $Pkg.Name
                    PackageFullName = $Pkg.PackageFullName
                    InstallLocation = $Pkg.InstallLocation
                }
            }
        }
    }

    if ($BrokenAppx.Count -gt 0) {
        $Issues += "BROKEN_APPX ($($BrokenAppx.Count) packages)"
        $script:BrokenAppxDetails = $BrokenAppx
    }
}
catch {
    $Issues += "APPX_CHECK_FAILED"
}

# Panther log check - failures only
try {
    $PantherLogs = @(
        'C:\$WINDOWS.~BT\Sources\Panther\setuperr.log',
        'C:\$WINDOWS.~BT\Sources\Panther\setupact.log',
        'C:\Windows\Panther\setuperr.log',
        'C:\Windows\Panther\setupact.log'
    )

    $FailurePatternMap = @{
        'SYSPRP Failed to pre-register' = 'APPX/SYSPREP failure - Windows failed to pre-register built-in app packages during upgrade.'
        'CbsExecuteStateFailed'         = 'CBS execution failure - component servicing failed during setup.'
        'CBS_E_INVALID_PACKAGE'         = 'Component store failure - Windows servicing found an invalid package.'
        '0x800f0805'                    = 'Invalid package - CBS/component store package could not be opened or validated.'
        '0xC0000400'                    = 'Setup abort/crash - setup exited unexpectedly or hit a fatal internal condition.'
        'CSetupManager::Execute'        = 'Setup execution failure - setup manager returned an error.'
        'CSetupHost::Execute'           = 'Setup host failure - Windows setup host returned an error.'
        'Failed to download updates'    = 'Dynamic Update failure - setup could not download required updates.'
        'DUImage: Failed'               = 'Dynamic Update/driver search failure.'
        'Failure while calling'         = 'Migration/plugin failure during apply or finalize.'
        'Error READ'                    = 'Migration/apply failure while reading or applying setup objects.'
    }

    foreach ($Log in $PantherLogs) {
        if (Test-Path $Log) {
            foreach ($Pattern in $FailurePatternMap.Keys) {
                $Matches = Select-String `
                    -Path $Log `
                    -Pattern $Pattern `
                    -CaseSensitive:$false `
                    -ErrorAction SilentlyContinue |
                    Select-Object -First 3

                if ($Matches) {
                    $script:PantherDetails += [PSCustomObject]@{
                        LogFile    = $Log
                        Pattern    = $Pattern
                        Meaning    = $FailurePatternMap[$Pattern]
                        SampleLine = $Matches[0].Line.Trim()
                    }
                }
            }
        }
    }

    if ($script:PantherDetails.Count -gt 0) {
        $Issues += "PANTHER_FAILURE_DETECTED"
        $script:PantherDetails = $script:PantherDetails | Sort-Object Pattern -Unique
    }
}
catch {
    $Issues += "PANTHER_CHECK_FAILED"
}

# TPM
try {
    $TPM = Get-Tpm -ErrorAction Stop

    if (-not $TPM.TpmReady) {
        $Issues += "TPM_NOT_READY"
    }
}
catch {
    $Issues += "TPM_CHECK_FAILED"
}

# Secure Boot
try {
    $SecureBoot = Confirm-SecureBootUEFI -ErrorAction Stop

    if (-not $SecureBoot) {
        $Issues += "SECURE_BOOT_DISABLED"
    }
}
catch {
    $Issues += "SECURE_BOOT_UNKNOWN"
}

# Final summary
Write-Output "============================================================"
Write-Output "PRE-CHECK SUMMARY"
Write-Output "============================================================"

if ($Issues.Count -eq 0) {
    Write-Output "RESULT: PASS"
    Write-Output "No issues detected."
    exit 0
}

Write-Output "RESULT: REVIEW REQUIRED"
Write-Output "Issue Count: $($Issues.Count)"
Write-Output ""

$Issues | Sort-Object -Unique | ForEach-Object {
    Write-Output "- $_"
}

if ($script:PantherDetails.Count -gt 0) {
    Write-Output ""
    Write-Output "Panther Failure Details:"

    foreach ($Finding in $script:PantherDetails) {
        Write-Output "- $($Finding.Pattern): $($Finding.Meaning)"
        Write-Output "  Log: $($Finding.LogFile)"
        Write-Output "  Example: $($Finding.SampleLine)"
    }
}

if ($script:BrokenAppxDetails.Count -gt 0) {
    Write-Output ""
    Write-Output "Broken AppX Details:"

    foreach ($App in $script:BrokenAppxDetails) {
        Write-Output "- $($App.Name)"
        Write-Output "  Package: $($App.PackageFullName)"
        Write-Output "  Path: $($App.InstallLocation)"
    }
}

if ($script:PendingFileRenameDetails.Count -gt 0) {
    Write-Output ""
    Write-Output "Pending File Rename Details:"
    Write-Output "Source: HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations"
    Write-Output "Count : $($script:PendingFileRenameDetails.Count)"
    Write-Output ""

    $Index = 1
    foreach ($Entry in $script:PendingFileRenameDetails) {
        Write-Output "$Index. $Entry"
        $Index++
    }
}

exit 2
