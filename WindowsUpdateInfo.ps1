# PowerShell Script to Gather Comprehensive Patching Information

# Define paths for log, report, and last check files
$logFilePath = "C:\PatchingInfoLog.log"
$reportFilePath = "C:\PatchingInfoReport.txt"
$lastCheckFilePath = "C:\LastPatchingInfoReport.txt"

# Function to write to the log
function Write-Log {
    param([string]$message)
    Add-Content -Path $logFilePath -Value "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss") - $message"
}

# Function to append to the report
function Append-ToReport {
    param([string]$message)
    Add-Content -Path $reportFilePath -Value $message
}

# Function to read the last check file
function Read-LastCheckFile {
    if (Test-Path -Path $lastCheckFilePath) {
        return Get-Content -Path $lastCheckFilePath
    }
    return @()
}

# Initial log entry
Write-Log "Starting comprehensive patching information retrieval."

# Read the last check's update list
$lastCheckUpdates = Read-LastCheckFile

# Main script logic with error handling
try {
    # Get installed updates using Get-HotFix
    $installedUpdates = Get-HotFix
    $installedUpdatesCount = $installedUpdates.Count
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem

    # Append basic system info to the report
    $systemInfoReport = @"
System Information:
-------------------
OS Name: $($osInfo.CSName)
OS Version: $($osInfo.Version)
OS Build Number: $($osInfo.BuildNumber)
Installed Updates Count: $installedUpdatesCount

"@
    Append-ToReport $systemInfoReport

    # Determine updates installed since the last check
    $newUpdates = $installedUpdates | Where-Object { $_.InstalledOn -and ($_.InstalledOn.ToString("yyyy-MM-dd") -notin $lastCheckUpdates) }
    $newUpdatesCount = $newUpdates.Count
    $criticalOrSevereUpdatesCount = 0 # Placeholder, as we cannot determine severity without an external database or API

    # Append updates since last check to the report
    Append-ToReport "Updates Since Last Check:"
    foreach ($update in $newUpdates) {
        $updateInfo = "ID: $($update.HotFixID), Description: $($update.Description), Installed On: $($update.InstalledOn)"
        Append-ToReport $updateInfo

        # Placeholder: Check if the update is Critical or Severe
        # This would require looking up each update in a security database or using an API that provides this information
        # $criticalOrSevereUpdatesCount++ if the update is determined to be Critical or Severe
    }

    # Append summary of new updates to the report
    $updatesSummary = @"
Total New Updates Since Last Check: $newUpdatesCount
Total Critical/Severe Updates Since Last Check: $criticalOrSevereUpdatesCount

"@
    Append-ToReport $updatesSummary

    # Save the current list of updates for the next check
    $installedUpdates | ForEach-Object { $_.InstalledOn.ToString("yyyy-MM-dd") } | Out-File -FilePath $lastCheckFilePath -Force

    # Append final message to the report
    $finalReport = "Comprehensive patching information retrieval completed successfully."
    Append-ToReport $finalReport
    Write-Log $finalReport

} catch {
    # General error handling for the entire script
    $errorMessage = "An unexpected error occurred: $($_.Exception.Message)"
    Write-Log $errorMessage
    Append-ToReport $errorMessage
}

# Output completion message
Write-Host "Patching information retrieval has completed. Please check the report at $reportFilePath"

