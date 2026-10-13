#!ps
#timeout=300000
#maxlength=5000000

echo "DIAGNOSTIC-RESPONSE/1"
echo "DiagnosticType: WindowsFeatureUpdateProgress"
echo "ContentType: text"
echo ""

$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

function Write-Section {
    param([string]$Title)

    Write-Output ""
    Write-Output ("=" * 88)
    Write-Output $Title
    Write-Output ("=" * 88)
}

function Get-PendingReboot {
    $Reasons = @()

    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") {
        $Reasons += "CBS RebootPending"
    }

    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") {
        $Reasons += "Windows Update RebootRequired"
    }

    $SessionManager = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
    $PendingRename = (Get-ItemProperty $SessionManager -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations

    if ($PendingRename) {
        $Reasons += "PendingFileRenameOperations"
    }

    [PSCustomObject]@{
        Pending = ($Reasons.Count -gt 0)
        Reasons = ($Reasons -join "; ")
    }
}

function Get-SetupPhase {
    param([string[]]$Lines)

    $Joined = $Lines -join "`n"

    if ($Joined -match "Rollback|SPExecuteFirstBootApply.*failed|SetupPlatform.*rollback") {
        return "Rollback or failed setup detected"
    }

    if ($Joined -match "OOBE|FirstBoot|FIRST_BOOT") {
        return "First boot / OOBE phase"
    }

    if ($Joined -match "SecondBoot|SECOND_BOOT") {
        return "Second boot phase"
    }

    if ($Joined -match "SafeOS|SAFE_OS") {
        return "Safe OS phase"
    }

    if ($Joined -match "Install.*image|Apply.*image|ImageDeploy") {
        return "Applying Windows image"
    }

    if ($Joined -match "Dynamic Update|DUSetup|Download.*update") {
        return "Dynamic Update / downloading setup updates"
    }

    if ($Joined -match "Compat|Appraiser|Compatibility scan|CONX") {
        return "Compatibility scan"
    }

    if ($Joined -match "MOUPG|SetupHost|SetupPlatform") {
        return "Windows Setup initialization or staging"
    }

    return "Unable to determine exact setup phase"
}

Write-Section "CURRENT WINDOWS BUILD"

$CurrentVersion = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
$OS = Get-CimInstance Win32_OperatingSystem

$Build = [string]$CurrentVersion.CurrentBuild
$UBR = [string]$CurrentVersion.UBR
$FullBuild = if ($UBR) { "$Build.$UBR" } else { $Build }

[PSCustomObject]@{
    ComputerName   = $env:COMPUTERNAME
    ProductName    = $CurrentVersion.ProductName
    Edition        = $CurrentVersion.EditionID
    DisplayVersion = $CurrentVersion.DisplayVersion
    CurrentBuild   = $Build
    UBR            = $UBR
    FullBuild      = $FullBuild
    BuildLabEx     = $CurrentVersion.BuildLabEx
    InstallDate    = $OS.InstallDate
    LastBoot       = $OS.LastBootUpTime
} | Format-List

Write-Output "CURRENT BUILD NUMBER: $FullBuild"

Write-Section "TARGET FEATURE RELEASE POLICY"

$WUPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"

$TargetReleaseEnabled = (Get-ItemProperty $WUPath -Name TargetReleaseVersion -ErrorAction SilentlyContinue).TargetReleaseVersion
$TargetReleaseInfo = (Get-ItemProperty $WUPath -Name TargetReleaseVersionInfo -ErrorAction SilentlyContinue).TargetReleaseVersionInfo
$ProductVersion = (Get-ItemProperty $WUPath -Name ProductVersion -ErrorAction SilentlyContinue).ProductVersion

[PSCustomObject]@{
    TargetReleaseVersion     = $TargetReleaseEnabled
    TargetReleaseVersionInfo = $TargetReleaseInfo
    ProductVersion           = $ProductVersion
} | Format-List

if ($TargetReleaseEnabled -eq 1 -and $TargetReleaseInfo) {
    Write-Output "Configured target release: $ProductVersion $TargetReleaseInfo"
}
else {
    Write-Output "No TargetReleaseVersion policy is currently configured."
}

Write-Section "WINDOWS SETUP PROCESSES"

$SetupProcessNames = @(
    "setup",
    "setuphost",
    "setupprep",
    "SetupPlatform",
    "SetupPlatformHost",
    "Windows10UpgraderApp",
    "Windows11InstallationAssistant",
    "MoUsoCoreWorker",
    "TiWorker",
    "TrustedInstaller"
)

$RunningSetupProcesses = Get-Process -ErrorAction SilentlyContinue |
    Where-Object {
        $SetupProcessNames -contains $_.ProcessName
    } |
    Select-Object ProcessName,
        Id,
        StartTime,
        @{Name="CPUSeconds";Expression={[math]::Round($_.CPU,2)}},
        @{Name="MemoryMB";Expression={[math]::Round($_.WorkingSet64 / 1MB,2)}}

if ($RunningSetupProcesses) {
    $RunningSetupProcesses | Format-Table -AutoSize
}
else {
    Write-Output "No active Windows Setup processes detected."
}

Write-Section "FEATURE UPDATE WORKING FOLDERS"

$WorkingPaths = @(
    "C:\`$WINDOWS.~BT",
    "C:\`$WINDOWS.~WS",
    "C:\Windows\Panther",
    "C:\Windows\Panther\NewOS",
    "C:\Windows\SoftwareDistribution\Download"
)

foreach ($Path in $WorkingPaths) {
    if (Test-Path $Path) {
        $Latest = Get-ChildItem $Path -Recurse -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1

        $TotalSize = (
            Get-ChildItem $Path -Recurse -File -ErrorAction SilentlyContinue |
            Measure-Object Length -Sum
        ).Sum

        [PSCustomObject]@{
            Path             = $Path
            Exists           = $true
            SizeGB           = [math]::Round($TotalSize / 1GB, 2)
            LatestChange     = $Latest.LastWriteTime
            LatestChangedFile = $Latest.FullName
        } | Format-List
    }
    else {
        Write-Output "$Path : Not present"
    }
}

Write-Section "SETUP PROGRESS AND CURRENT PHASE"

$SetupActCandidates = @(
    "C:\`$WINDOWS.~BT\Sources\Panther\setupact.log",
    "C:\`$WINDOWS.~BT\Sources\Rollback\setupact.log",
    "C:\Windows\Panther\setupact.log",
    "C:\Windows\Panther\NewOS\Panther\setupact.log"
)

$SetupErrCandidates = @(
    "C:\`$WINDOWS.~BT\Sources\Panther\setuperr.log",
    "C:\`$WINDOWS.~BT\Sources\Rollback\setuperr.log",
    "C:\Windows\Panther\setuperr.log",
    "C:\Windows\Panther\NewOS\Panther\setuperr.log"
)

$SetupAct = $SetupActCandidates |
    Where-Object { Test-Path $_ } |
    Sort-Object {
        (Get-Item $_).LastWriteTime
    } -Descending |
    Select-Object -First 1

$SetupErr = $SetupErrCandidates |
    Where-Object { Test-Path $_ } |
    Sort-Object {
        (Get-Item $_).LastWriteTime
    } -Descending |
    Select-Object -First 1

if ($SetupAct) {
    $SetupActFile = Get-Item $SetupAct
    $Tail = Get-Content $SetupAct -Tail 1500 -ErrorAction SilentlyContinue
    $Phase = Get-SetupPhase -Lines $Tail

    Write-Output "Active setup log: $SetupAct"
    Write-Output "Last modified: $($SetupActFile.LastWriteTime)"
    Write-Output "Inferred current phase: $Phase"

    Write-Output ""
    Write-Output "Recent percentage/progress indicators:"

    $ProgressLines = $Tail |
        Select-String -Pattern "\b[0-9]{1,3}%|percent|progress|phase|operation|installing|applying|downloading|compatibility|SafeOS|FirstBoot|SecondBoot|OOBE" |
        Select-Object -Last 30

    if ($ProgressLines) {
        $ProgressLines | ForEach-Object {
            $_.Line.Trim()
        }
    }
    else {
        Write-Output "No explicit percentage was found in the current setup log."
    }

    Write-Output ""
    Write-Output "Most recent meaningful setup activity:"

    $RecentActivity = $Tail |
        Select-String -Pattern "MOUPG|CONX|SetupHost|SetupPlatform|SafeOS|FirstBoot|SecondBoot|OOBE|Install|Apply|Download|Compat|Rollback|Error|Fail" |
        Select-Object -Last 40

    if ($RecentActivity) {
        $RecentActivity | ForEach-Object {
            $_.Line.Trim()
        }
    }
}
else {
    Write-Output "No setupact.log was found."
}

Write-Section "LATEST SETUP ERRORS"

if ($SetupErr) {
    Write-Output "Error log: $SetupErr"
    Write-Output "Last modified: $((Get-Item $SetupErr).LastWriteTime)"
    Write-Output ""

    $Errors = Get-Content $SetupErr -Tail 80 -ErrorAction SilentlyContinue

    if ($Errors) {
        $Errors
    }
    else {
        Write-Output "The error log is empty."
    }
}
else {
    Write-Output "No setuperr.log was found."
}

Write-Section "SETUP RESULT REGISTRY"

$SetupRegistryPaths = @(
    "HKLM:\SYSTEM\Setup",
    "HKLM:\SYSTEM\Setup\Status\SysprepStatus",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update",
    "HKLM:\SYSTEM\Setup\MoSetup\Volatile"
)

foreach ($Path in $SetupRegistryPaths) {
    Write-Output ""
    Write-Output "----- $Path -----"

    if (Test-Path $Path) {
        Get-ItemProperty $Path |
            Select-Object * -ExcludeProperty PSPath,PSParentPath,PSChildName,PSDrive,PSProvider |
            Format-List
    }
    else {
        Write-Output "Not present"
    }
}

Write-Section "PENDING REBOOT"

$Pending = Get-PendingReboot
$Pending | Format-List

Write-Section "FEATURE UPDATE STATUS SUMMARY"

$SetupRunning = [bool]$RunningSetupProcesses
$BTExists = Test-Path "C:\`$WINDOWS.~BT"
$SetupRecentlyChanged = $false

if ($SetupAct) {
    $SetupRecentlyChanged = ((Get-Date) - (Get-Item $SetupAct).LastWriteTime).TotalMinutes -lt 15
}

$RollbackDetected = $false

if ($SetupAct) {
    $RollbackDetected = Select-String `
        -Path $SetupAct `
        -Pattern "Rollback|SetupRollback|rollback initiated" `
        -Quiet `
        -ErrorAction SilentlyContinue
}

$RecentFatalError = $false

if ($SetupErr) {
    $RecentFatalError = (Get-Item $SetupErr).Length -gt 0
}

if ($SetupRunning -or $SetupRecentlyChanged) {
    Write-Output "STATUS: Feature Update appears to be actively running."
}
elseif ($RollbackDetected) {
    Write-Output "STATUS: Feature Update rollback activity was detected."
}
elseif ($RecentFatalError -and $BTExists) {
    Write-Output "STATUS: Feature Update staging exists, but setup errors were detected."
}
elseif ($BTExists) {
    Write-Output "STATUS: Feature Update files are staged, but no active setup process was detected."
}
else {
    Write-Output "STATUS: No active or staged Feature Update was detected."
}

Write-Output "CURRENT WINDOWS VERSION: $($CurrentVersion.DisplayVersion)"
Write-Output "CURRENT WINDOWS BUILD: $FullBuild"

if ($TargetReleaseInfo) {
    Write-Output "CONFIGURED TARGET RELEASE: $TargetReleaseInfo"
}

if ($Pending.Pending) {
    Write-Output "REBOOT PENDING: Yes - $($Pending.Reasons)"
}
else {
    Write-Output "REBOOT PENDING: No"
}
