#!ps
#timeout=600000
#maxlength=5000000

echo "DIAGNOSTIC-RESPONSE/1"
echo "DiagnosticType: AvailableWindowsUpdates"
echo "ContentType: text"
echo ""

$ErrorActionPreference = "Stop"

$cv = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"

Write-Output "CURRENT WINDOWS"
Write-Output "==============="
Write-Output "Version: $($cv.DisplayVersion)"
Write-Output "Build:   $($cv.CurrentBuild).$($cv.UBR)"
Write-Output ""

try {
    $Session = New-Object -ComObject Microsoft.Update.Session
    $Searcher = $Session.CreateUpdateSearcher()

    Write-Output "Searching Microsoft Update..."
    $Result = $Searcher.Search("IsInstalled=0 and IsHidden=0")

    Write-Output ""
    Write-Output "AVAILABLE UPDATES"
    Write-Output "================="
    Write-Output "Count: $($Result.Updates.Count)"
    Write-Output ""

    $Rows = @()

    for ($i = 0; $i -lt $Result.Updates.Count; $i++) {
        $Update = $Result.Updates.Item($i)

        $Categories = @(
            $Update.Categories |
                ForEach-Object { $_.Name }
        ) -join "; "

        $KBs = @(
            $Update.KBArticleIDs |
                ForEach-Object { "KB$_" }
        ) -join ", "

        $Rows += [PSCustomObject]@{
            Index           = $i
            Title           = $Update.Title
            KB              = $KBs
            Categories      = $Categories
            Downloaded      = $Update.IsDownloaded
            Mandatory       = $Update.IsMandatory
            RebootRequired  = $Update.RebootRequired
            EulaAccepted    = $Update.EulaAccepted
            MaxDownloadMB   = [math]::Round($Update.MaxDownloadSize / 1MB, 2)
        }
    }

    if ($Rows.Count -gt 0) {
        $Rows | Format-List
    }
    else {
        Write-Output "No available updates were returned."
    }

    Write-Output ""
    Write-Output "FEATURE UPDATE CANDIDATES"
    Write-Output "========================="

    $FeatureUpdates = $Rows | Where-Object {
        $_.Title -match "Feature update|Windows 11, version|24H2|25H2" -or
        $_.Categories -match "Upgrades"
    }

    if ($FeatureUpdates) {
        $FeatureUpdates | Format-List
    }
    else {
        Write-Output "No Feature Update is currently being offered through the Windows Update API."
    }
}
catch {
    Write-Output "FAILED: $($_.Exception.Message)"
    exit 1
}
