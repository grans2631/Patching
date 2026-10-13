#!ps
#timeout=300000
#maxlength=4000000

echo "DIAGNOSTIC-RESPONSE/1"
echo "DiagnosticType: FeatureUpdateHardBlock"
echo "ContentType: text"
echo ""

$ErrorActionPreference = "SilentlyContinue"

$PantherPaths = @(
    "C:\`$WINDOWS.~BT\Sources\Panther",
    "C:\Windows\Panther",
    "C:\Windows\Panther\NewOS\Panther"
)

Write-Output "CURRENT WINDOWS BUILD"
Write-Output "====================="

$CV = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"

$Build = if ($null -ne $CV.UBR) {
    "$($CV.CurrentBuild).$($CV.UBR)"
}
else {
    [string]$CV.CurrentBuild
}

Write-Output "DisplayVersion: $($CV.DisplayVersion)"
Write-Output "CurrentBuild:   $Build"
Write-Output ""

Write-Output "SETUPDIAG RESULT"
Write-Output "================"

$SetupDiagFiles = @(
    "C:\Windows\Logs\SetupDiag\SetupDiagResults.xml",
    "C:\Windows\Logs\SetupDiag\SetupDiagResults.log"
)

foreach ($File in $SetupDiagFiles) {
    if (Test-Path $File) {
        Write-Output ""
        Write-Output "File: $File"
        Get-Content $File -Raw
    }
}

Write-Output ""
Write-Output "SCANRESULT HARD BLOCKS"
Write-Output "======================"

foreach ($Root in $PantherPaths) {
    $ScanResult = Join-Path $Root "ScanResult.xml"

    if (Test-Path $ScanResult) {
        Write-Output ""
        Write-Output "File: $ScanResult"

        Select-String -Path $ScanResult `
            -Pattern "Hard|Block|Compat|Requirement|Insufficient|DiskSpace|SystemPartition|TPM|SecureBoot|CPU|Memory|Driver|Application" `
            -CaseSensitive:$false |
            ForEach-Object {
                $_.Line.Trim()
            }
    }
}

Write-Output ""
Write-Output "COMPATDATA HARD BLOCKS"
Write-Output "======================"

$CompatFiles = foreach ($Root in $PantherPaths) {
    if (Test-Path $Root) {
        Get-ChildItem $Root -Filter "CompatData*.xml" -File
    }
}

$CompatFiles = $CompatFiles |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 10

foreach ($File in $CompatFiles) {
    Write-Output ""
    Write-Output "File: $($File.FullName)"
    Write-Output "Modified: $($File.LastWriteTime)"

    try {
        [xml]$Xml = Get-Content $File.FullName -Raw

        $Nodes = $Xml.SelectNodes(
            "//*[@BlockingType='Hard' or " +
            "@Block='True' or " +
            "@Block='true' or " +
            "@HardBlock='True' or " +
            "@HardBlock='true' or " +
            "contains(@Name,'Block') or " +
            "contains(@Name,'Requirement')]"
        )

        if ($Nodes.Count -gt 0) {
            foreach ($Node in $Nodes) {
                Write-Output $Node.OuterXml
            }
        }
        else {
            Select-String -Path $File.FullName `
                -Pattern "HardBlock|BlockingType=.Hard.|CompatBlock|Insufficient|SystemPartition|DiskSpace|Requirement|BlockMigration" `
                -CaseSensitive:$false |
                ForEach-Object {
                    $_.Line.Trim()
                }
        }
    }
    catch {
        Select-String -Path $File.FullName `
            -Pattern "HardBlock|BlockingType=.Hard.|CompatBlock|Insufficient|SystemPartition|DiskSpace|Requirement" `
            -CaseSensitive:$false |
            ForEach-Object {
                $_.Line.Trim()
            }
    }
}

Write-Output ""
Write-Output "PENDING REBOOT"
Write-Output "=============="

$Reasons = @()

if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") {
    $Reasons += "CBS RebootPending"
}

if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") {
    $Reasons += "Windows Update RebootRequired"
}

$PendingRename = (
    Get-ItemProperty `
        "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" `
        -Name PendingFileRenameOperations
).PendingFileRenameOperations

if ($PendingRename) {
    $Reasons += "PendingFileRenameOperations"
}

if ($Reasons.Count -gt 0) {
    Write-Output "Pending: Yes"
    Write-Output "Reasons: $($Reasons -join '; ')"
}
else {
    Write-Output "Pending: No"
}
