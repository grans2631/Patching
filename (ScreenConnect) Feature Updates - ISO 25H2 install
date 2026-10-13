#!ps
#timeout=14400000
#maxlength=8000000

echo "DIAGNOSTIC-RESPONSE/1"
echo "DiagnosticType: DownloadAndLaunchWindows1125H2"
echo "ContentType: text"
echo ""

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Temporary Microsoft download URL supplied by administrator.
$IsoUrl = 'https://software.download.prss.microsoft.com/dbazure/Windows11_Client_x64_en-us_26300_9457.iso?t=8aa8826e-da19-45f4-ad90-b0456c2c6aa7&P1=1791995904&P2=602&P3=2&P4=AXyzLMDd0RdODYQuhHbD2c6xerFWh34hWEzhaRMiLnfJf%2bdtFByEHi95xhgeHzHiBoaOkOk4lXqKZqWOnZAxcUAbjYRX%2fnhKXzbDnCXdgNBzjJ3slS7O%2bGEGacuIqkrw%2bc3wh4J7UMK1kAU5vLCVdGW5Z4XCgTTX3lQKhFf9OVE3dy3ta8KjVawHjucDdeqLvv5nwSuR%2bqFD%2fVgIG8YBLY%2b%2fI3dU4c3zgUq1dyY%2ft1JJc9xW%2fqaeQEam5umDYYpUAVUve1CgWvFdb5ybnFTuvFXRngeUNTsbtAK132qarFoeZ6Qb7OcYj2SNm%2fRRIDaYZftoQRsg2ev7S%2bmWmnZsaQ%3d%3d'

$RootPath     = "C:\Windows\LTSvc\Packages\Win11-25H2"
$IsoPath      = Join-Path $RootPath "Win11_25H2_English_x64_v2.iso"
$LauncherPath = Join-Path $RootPath "Launch-25H2Upgrade.ps1"
$StatusPath   = Join-Path $RootPath "UpgradeStatus.txt"
$SetupLogPath = Join-Path $RootPath "SetupLogs"
$TaskName     = "Windows 11 25H2 Feature Update"

function Write-Section {
    param([string]$Title)

    Write-Output ""
    Write-Output ("=" * 84)
    Write-Output $Title
    Write-Output ("=" * 84)
}

function Test-PendingReboot {
    $Reasons = @()

    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") {
        $Reasons += "CBS RebootPending"
    }

    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") {
        $Reasons += "Windows Update RebootRequired"
    }

    $Rename = (
        Get-ItemProperty `
            "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" `
            -Name PendingFileRenameOperations `
            -ErrorAction SilentlyContinue
    ).PendingFileRenameOperations

    if ($Rename) {
        $Reasons += "PendingFileRenameOperations"
    }

    [PSCustomObject]@{
        Pending = $Reasons.Count -gt 0
        Reasons = $Reasons -join "; "
    }
}

Write-Section "CURRENT WINDOWS"

$CV = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
$OS = Get-CimInstance Win32_OperatingSystem

Write-Output "Computer:       $env:COMPUTERNAME"
Write-Output "Product:        $($CV.ProductName)"
Write-Output "Edition:        $($CV.EditionID)"
Write-Output "DisplayVersion: $($CV.DisplayVersion)"
Write-Output "Current build:  $($CV.CurrentBuild).$($CV.UBR)"
Write-Output "Architecture:   $($OS.OSArchitecture)"

if ($OS.OSArchitecture -notmatch "64") {
    throw "This is not a 64-bit Windows installation."
}

if ([int]$CV.CurrentBuild -lt 22000) {
    throw "This script is intended for an existing Windows 11 installation."
}

Write-Section "PRE-FLIGHT CHECKS"

New-Item -Path $RootPath -ItemType Directory -Force | Out-Null
New-Item -Path $SetupLogPath -ItemType Directory -Force | Out-Null

$FreeGB = [math]::Round((Get-PSDrive C).Free / 1GB, 2)
Write-Output "C: free space: $FreeGB GB"

if ($FreeGB -lt 35) {
    throw "At least 35 GB of free C: space is required by this deployment policy."
}

$Pending = Test-PendingReboot

Write-Output "Pending reboot: $($Pending.Pending)"
Write-Output "Reasons:        $($Pending.Reasons)"

if ($Pending.Pending) {
    Write-Output "WARNING: A pending reboot exists. Setup may still stage, but rebooting before launching is preferred."
}

Write-Section "DOWNLOADING ISO"

if (Test-Path $IsoPath) {
    $ExistingSizeGB = [math]::Round((Get-Item $IsoPath).Length / 1GB, 2)
    Write-Output "Existing ISO found: $ExistingSizeGB GB"

    if ((Get-Item $IsoPath).Length -lt 4GB) {
        Write-Output "Existing file is too small and will be replaced."
        Remove-Item $IsoPath -Force
    }
}

if (-not (Test-Path $IsoPath)) {
    $Curl = "$env:SystemRoot\System32\curl.exe"

    if (Test-Path $Curl) {
        Write-Output "Downloading with curl.exe using retry and resume support."

        $CurlArguments = @(
            "--location"
            "--fail"
            "--show-error"
            "--retry", "5"
            "--retry-delay", "10"
            "--connect-timeout", "60"
            "--continue-at", "-"
            "--output", "`"$IsoPath`""
            "`"$IsoUrl`""
        )

        $CurlProcess = Start-Process `
            -FilePath $Curl `
            -ArgumentList ($CurlArguments -join " ") `
            -Wait `
            -PassThru `
            -NoNewWindow

        Write-Output "curl exit code: $($CurlProcess.ExitCode)"

        if ($CurlProcess.ExitCode -ne 0) {
            throw "ISO download failed. The temporary Microsoft URL may have expired. curl exit code: $($CurlProcess.ExitCode)"
        }
    }
    else {
        Write-Output "curl.exe was not found. Trying BITS."

        Start-BitsTransfer `
            -Source $IsoUrl `
            -Destination $IsoPath `
            -DisplayName "Windows 11 25H2 ISO" `
            -Description "Windows 11 25H2 feature-update media" `
            -Priority Foreground
    }
}

if (-not (Test-Path $IsoPath)) {
    throw "ISO download did not create $IsoPath"
}

$IsoFile = Get-Item $IsoPath
$IsoSizeGB = [math]::Round($IsoFile.Length / 1GB, 2)

Write-Output "Downloaded ISO: $IsoPath"
Write-Output "ISO size:       $IsoSizeGB GB"

if ($IsoFile.Length -lt 4GB) {
    throw "Downloaded file is unexpectedly small and is probably an error page or incomplete download."
}

Write-Section "CALCULATING ISO HASH"

$Hash = Get-FileHash -Path $IsoPath -Algorithm SHA256

Write-Output "SHA256:"
Write-Output $Hash.Hash

Write-Section "VALIDATING ISO"

$MountedHere = $false

try {
    $ExistingImage = Get-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue

    if (-not $ExistingImage.Attached) {
        $Image = Mount-DiskImage -ImagePath $IsoPath -PassThru
        $MountedHere = $true
    }
    else {
        $Image = $ExistingImage
    }

    Start-Sleep -Seconds 5

    $Volume = $Image |
        Get-Volume |
        Where-Object DriveLetter |
        Select-Object -First 1

    if (-not $Volume.DriveLetter) {
        throw "Mounted ISO did not receive a drive letter."
    }

    $MediaRoot = "$($Volume.DriveLetter):\"
    $SetupExe = Join-Path $MediaRoot "setup.exe"

    Write-Output "Mounted drive: $MediaRoot"
    Write-Output "Volume label:  $($Volume.FileSystemLabel)"
    Write-Output "Setup path:    $SetupExe"

    if (-not (Test-Path $SetupExe)) {
        throw "setup.exe was not found in the ISO root."
    }

    $InstallImage = @(
        (Join-Path $MediaRoot "sources\install.wim")
        (Join-Path $MediaRoot "sources\install.esd")
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $InstallImage) {
        throw "Neither install.wim nor install.esd was found in the ISO."
    }

    Write-Output "Install image: $InstallImage"
    Write-Output ""
    Write-Output "Image information:"

    & dism.exe /English /Get-WimInfo /WimFile:"$InstallImage" /Index:1 |
        Select-String -Pattern "Name :|Description :|Architecture :|Version :" |
        ForEach-Object { $_.Line }

    $SetupVersion = (Get-Item $SetupExe).VersionInfo.FileVersion
    Write-Output ""
    Write-Output "setup.exe version: $SetupVersion"

    if ($SetupVersion -notmatch "^10\.0\.26200\.") {
        Write-Output "WARNING: setup.exe does not report the expected 25H2 26200 build family."
        Write-Output "Review the ISO before broad deployment."
    }
}
finally {
    if ($MountedHere) {
        Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue
    }
}

Write-Section "CREATING UPGRADE LAUNCHER"

$Launcher = @'
$ErrorActionPreference = "Stop"

$RootPath     = "C:\Windows\LTSvc\Packages\Win11-25H2"
$IsoPath      = Join-Path $RootPath "Win11_25H2_English_x64_v2.iso"
$StatusPath   = Join-Path $RootPath "UpgradeStatus.txt"
$SetupLogPath = Join-Path $RootPath "SetupLogs"

function Set-Status {
    param([string]$Message)

    $Line = "{0} | {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Add-Content -Path $StatusPath -Value $Line
}

try {
    New-Item -Path $SetupLogPath -ItemType Directory -Force | Out-Null

    Set-Status "Launcher started as $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"

    $ExistingImage = Get-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue

    if (-not $ExistingImage.Attached) {
        Set-Status "Mounting ISO"
        $Image = Mount-DiskImage -ImagePath $IsoPath -PassThru
    }
    else {
        Set-Status "ISO already mounted"
        $Image = $ExistingImage
    }

    Start-Sleep -Seconds 5

    $Volume = $Image |
        Get-Volume |
        Where-Object DriveLetter |
        Select-Object -First 1

    if (-not $Volume.DriveLetter) {
        throw "Mounted ISO did not receive a drive letter."
    }

    $SetupExe = "$($Volume.DriveLetter):\setup.exe"

    if (-not (Test-Path $SetupExe)) {
        throw "setup.exe not found at $SetupExe"
    }

    Set-Status "Launching Windows Setup from $SetupExe"

    $Arguments = @(
        "/auto upgrade"
        "/quiet"
        "/eula accept"
        "/dynamicupdate disable"
        "/showoobe none"
        "/telemetry disable"
        "/compat ignorewarning"
        "/priority normal"
        "/copylogs `"$SetupLogPath`""
        "/noreboot"
    ) -join " "

    Set-Status "Arguments: $Arguments"

    $Process = Start-Process `
        -FilePath $SetupExe `
        -ArgumentList $Arguments `
        -Wait `
        -PassThru

    Set-Status "Windows Setup exited with code $($Process.ExitCode)"

    $CV = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    Set-Status "Current build after setup process: $($CV.DisplayVersion) $($CV.CurrentBuild).$($CV.UBR)"

    if ($Process.ExitCode -eq 0) {
        Set-Status "Setup staging completed successfully. A reboot may be required."
    }
    elseif ($Process.ExitCode -eq 3010) {
        Set-Status "Setup completed and explicitly requires a reboot."
    }
    else {
        Set-Status "Setup returned a non-zero exit code. Review Panther and SetupLogs."
    }
}
catch {
    Set-Status "FAILED: $($_.Exception.Message)"
    Set-Status "Stack: $($_.ScriptStackTrace)"
    exit 1
}
'@

Set-Content `
    -Path $LauncherPath `
    -Value $Launcher `
    -Encoding UTF8 `
    -Force

Write-Output "Launcher created:"
Write-Output $LauncherPath

Write-Section "REGISTERING SYSTEM SCHEDULED TASK"

Unregister-ScheduledTask `
    -TaskName $TaskName `
    -Confirm:$false `
    -ErrorAction SilentlyContinue

$Action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$LauncherPath`""

$Trigger = New-ScheduledTaskTrigger `
    -Once `
    -At (Get-Date).AddMinutes(1)

$Principal = New-ScheduledTaskPrincipal `
    -UserId "SYSTEM" `
    -LogonType ServiceAccount `
    -RunLevel Highest

$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Hours 8)

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $Action `
    -Trigger $Trigger `
    -Principal $Principal `
    -Settings $Settings `
    -Force |
    Out-Null

Remove-Item $StatusPath -Force -ErrorAction SilentlyContinue

Start-ScheduledTask -TaskName $TaskName

Start-Sleep -Seconds 5

Write-Output "Scheduled task started:"
Write-Output $TaskName

Write-Output ""
Write-Output "Task status:"

Get-ScheduledTask -TaskName $TaskName |
    Select-Object TaskName, State |
    Format-Table -AutoSize

Write-Output ""
Write-Output "Status file:"
Write-Output $StatusPath

if (Test-Path $StatusPath) {
    Get-Content $StatusPath
}

Write-Output ""
Write-Output "IMPORTANT:"
Write-Output "Setup is running with /noreboot."
Write-Output "Do not reboot until the status/logs show setup staging has completed."
