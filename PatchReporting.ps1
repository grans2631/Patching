# Specify the path for the report file
$reportPath = "C:\WindowsUpdateReport.txt"

# Function to append text to the report file
function Write-Report {
    Param (
        [string]$Text
    )

    Add-Content -Path $reportPath -Value $Text
}

# Initialize the report file
"Windows Update Report - $(Get-Date)" | Set-Content $reportPath

try {
    # Retrieve Windows Build Number and Feature Update Version
    $computerInfo = Get-ComputerInfo
    $windowsBuildNumber = $computerInfo.WindowsBuildLabEx -split '\.' | Select-Object -First 1
    $featureUpdateVersion = $computerInfo.WindowsVersion

    # Write Windows Build Number and Feature Update Version to the report
    Write-Report "Windows Build Number: $windowsBuildNumber"
    Write-Report "Feature Update Version: $featureUpdateVersion"
    Write-Report "" # Add a blank line for readability

     # Compliance Calculation
    try {
        # Initialize variables for counting
        $installedUpdatesCount = 0
        $availableUpdatesCount = 0

        # Count installed updates in the last 90 days
        $ninetyDaysAgo = (Get-Date).AddDays(-90)
        $installedUpdatesCount = ($installedUpdates | Where-Object { $_.Date -gt $ninetyDaysAgo }).Count

        # Search for available updates
        $searchResult = $updateSearcher.Search("IsInstalled=0 and IsHidden=0")
        $availableUpdatesCount = $searchResult.Updates.Count

        # Calculate patch compliance percentage
        $totalUpdatesConsidered = $installedUpdatesCount + $availableUpdatesCount
        if ($totalUpdatesConsidered -gt 0) {
            $patchCompliancePercentage = ($installedUpdatesCount / $totalUpdatesConsidered) * 100
        } else {
            $patchCompliancePercentage = 100 # Assume compliant if no updates are found
        }

        # Write the compliance report
        Write-Report "Patch Compliance Report:"
        Write-Report "Installed updates in the last 90 days: $installedUpdatesCount"
        Write-Report "Available (missing) updates: $availableUpdatesCount"
        Write-Report "Estimated Patch Compliance Percentage: $patchCompliancePercentage%"
        Write-Report "" # Add a blank line for readability
    } catch {
        Write-Report "An error occurred during compliance calculation: $_"
    }

    # Create a COM object to interact with Windows Update
    $updateSession = New-Object -ComObject Microsoft.Update.Session
    $updateSearcher = $updateSession.CreateUpdateSearcher()

    # Get the total history count and query all installed updates
    $historyCount = $updateSearcher.GetTotalHistoryCount()
    $installedUpdates = $updateSearcher.QueryHistory(0, $historyCount)

    # Define cutoff dates for filtering
    $now = Get-Date
    $timeFrames = @(
        @{Name = "last 7 days"; Start = $now.AddDays(-7); End = $now},
        @{Name = "8 to 14 days"; Start = $now.AddDays(-14); End = $now.AddDays(-8)},
        @{Name = "15 to 21 days"; Start = $now.AddDays(-21); End = $now.AddDays(-15)},
        @{Name = "22 to 28 days"; Start = $now.AddDays(-28); End = $now.AddDays(-22)},
        @{Name = "30 to 60 days"; Start = $now.AddDays(-60); End = $now.AddDays(-30)},
        @{Name = "60 to 90 days"; Start = $now.AddDays(-90); End = $now.AddDays(-60)}
    )

    foreach ($frame in $timeFrames) {
        Write-Report "Updates installed within $($frame.Name):"
        $filteredUpdates = $installedUpdates | Where-Object { $_.Date -gt $frame.Start -and $_.Date -le $frame.End }
        foreach ($update in $filteredUpdates) {
            Write-Report "$($update.Title) - Installed on $($update.Date)"
        }
        if ($filteredUpdates.Count -eq 0) {
            Write-Report "No updates were installed in this period."
        }
        Write-Report "" # Add a blank line for readability
    }

    # Continue with the existing script content for reboot required check and compliance calculation...

} catch {
    Write-Report "An error occurred: $_"
}

# Existing script content for reboot required check and compliance calculation...

# Output to the console that the report has been created
Write-Host "Windows Update report generated at $reportPath"
