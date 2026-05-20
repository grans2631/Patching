# Windows 11 Compatibility Script with Error Handling and Logging

$logFilePath = "C:\Windows11CompatibilityCheck.log"

# Function to write to log
function Write-Log {
    param(
        [string]$message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $message" | Out-File -FilePath $logFilePath -Append
}

try {
    # Check for 64-bit architecture
    $is64Bit = [Environment]::Is64BitOperatingSystem
    $architecture = if ($is64Bit) {"Yes"} else {"No"}
    Write-Host "64-bit architecture: $architecture"
    Write-Log "64-bit architecture: $architecture"

    # Check for 1 GHz or faster processor with 2 or more cores
    $cpu = Get-WmiObject -Class Win32_Processor -ErrorAction Stop
    $cpuCheck = if ($cpu.NumberOfCores -ge 2 -and $cpu.MaxClockSpeed -ge 1000) {"Yes"} else {"No"}
    Write-Host "1 GHz or faster processor with 2 or more cores: $cpuCheck"
    Write-Log "1 GHz or faster processor with 2 or more cores: $cpuCheck"

    # Check for 4 GB or more RAM
    $ram = Get-WmiObject -Class Win32_ComputerSystem -ErrorAction Stop
    $ramCheck = if ($ram.TotalPhysicalMemory / 1GB -ge 4) {"Yes"} else {"No"}
    Write-Host "4 GB or more RAM: $ramCheck"
    Write-Log "4 GB or more RAM: $ramCheck"

    # Check for 64 GB or more storage
    $disk = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction Stop
    $diskCheck = if ($disk.Size / 1GB -ge 64) {"Yes"} else {"No"}
    Write-Host "64 GB or more storage: $diskCheck"
    Write-Log "64 GB or more storage: $diskCheck"

    # Check for DirectX 12 compatible graphics card
    $video = Get-WmiObject -Class Win32_VideoController -ErrorAction Stop
    $videoCheck = if ($video.VideoProcessor -like "*DirectX 12*") {"Yes"} else {"No"}
    Write-Host "DirectX 12 compatible graphics card: $videoCheck"
    Write-Log "DirectX 12 compatible graphics card: $videoCheck"

    # Check for display with 720p resolution
    $display = Get-WmiObject -Class Win32_DesktopMonitor -ErrorAction Stop
    $displayCheck = if ($display.ScreenHeight -ge 720) {"Yes"} else {"No"}
    Write-Host "Display with 720p resolution: $displayCheck"
    Write-Log "Display with 720p resolution: $displayCheck"

    # Check for UEFI firmware with Secure Boot capability
    $firmware = (Get-WmiObject -Class Win32_ComputerSystem -ErrorAction Stop).PCSystemTypeEx
    $firmwareCheck = if ($firmware -eq "UEFISecureBoot") {"Yes"} else {"No"}
    Write-Host "UEFI firmware with Secure Boot capability: $firmwareCheck"
    Write-Log "UEFI firmware with Secure Boot capability: $firmwareCheck"

    # Check for TPM version 2.0
    $tpm = Get-WmiObject -Namespace "Root\CIMv2\Security\MicrosoftTpm" -Class Win32_Tpm -ErrorAction Stop
    $tpmCheck = if ($tpm.SpecVersion -like "*2.0*") {"Yes"} else {"No"}
    Write-Host "TPM version 2.0: $tpmCheck"
    Write-Log "TPM version 2.0: $tpmCheck"

} catch {
    $errorMessage = $_.Exception.Message
    Write-Host "An error occurred: $errorMessage"
    Write-Log "Error: $errorMessage"
}

Write-Host "Windows 11 Compatibility Check Completed. Please review the log file at $logFilePath for details."
Write-Log "Windows 11 Compatibility Check Completed."




##Below is an alternative with some similarities##

# PowerShell script to check Windows 11 compatibility and output system details

# Check for 64-bit architecture
$architecture = (Get-WmiObject -Class Win32_OperatingSystem).OSArchitecture
Write-Output "System Architecture: $architecture"

# Check for 1 GHz or faster processor with 2 or more cores
$cpu = Get-WmiObject -Class Win32_Processor
Write-Output "CPU: $($cpu.Name), Cores: $($cpu.NumberOfCores), Speed: $($cpu.MaxClockSpeed) MHz"

# Check if the processor is 8th generation or later
if ($cpu.Name -match "i[3579]-8" -or $cpu.Name -match "i[3579]-9" -or $cpu.Name -match "i[3579]-10") {
    Write-Output "The processor is 8th generation or later."
} else {
    Write-Output "The processor is not 8th generation or later."
}

# Check for 4 GB RAM or more
$ram = Get-WmiObject -Class Win32_ComputerSystem
$ramGB = [math]::Round($ram.TotalPhysicalMemory / 1GB, 2)
Write-Output "RAM: $ramGB GB"

# Check for 64 GB storage or more
$disk = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='C:'"
$diskGB = [math]::Round($disk.Size / 1GB, 2)
Write-Output "Storage: $diskGB GB"

# Check for DirectX 12 compatible graphics card
$gpu = Get-WmiObject -Class Win32_VideoController
Write-Output "Graphics Card: $($gpu.Name)"

# Check for TPM version 2.0
$tpm = Get-WmiObject -Namespace "Root\CIMv2\Security\MicrosoftTpm" -Class Win32_Tpm -ErrorAction Stop
$tpmCheck = if ($tpm.SpecVersion -like "*2.0*") {"Yes"} else {"No"}
Write-Output "TPM version 2.0: $tpmCheck"
