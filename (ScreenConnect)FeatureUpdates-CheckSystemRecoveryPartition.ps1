#!ps
#timeout=300000
#maxlength=1000000

echo "DIAGNOSTIC-RESPONSE/1"
echo "DiagnosticType: EFIPartitionCheck"
echo "ContentType: text"
echo ""

$ErrorActionPreference = "Continue"

Write-Output "=== Disk / Partition Layout ==="
Get-Disk | Format-Table Number, FriendlyName, PartitionStyle, Size -AutoSize

Get-Partition |
    Sort-Object DiskNumber, PartitionNumber |
    Format-Table DiskNumber, PartitionNumber, DriveLetter, Type, GptType, Size -AutoSize

Write-Output ""
Write-Output "=== EFI/System Volume Info ==="

try {
    mountvol S: /S | Out-Null
    Start-Sleep -Seconds 2

    if (Test-Path "S:\") {
        Get-Volume -DriveLetter S | Format-List DriveLetter, FileSystemLabel, FileSystem, Size, SizeRemaining

        Write-Output ""
        Write-Output "EFI folder sizes:"
        Get-ChildItem "S:\EFI" -Directory -ErrorAction SilentlyContinue |
            ForEach-Object {
                $size = (Get-ChildItem $_.FullName -Recurse -Force -ErrorAction SilentlyContinue |
                    Measure-Object Length -Sum).Sum
                [PSCustomObject]@{
                    Path = $_.FullName
                    SizeMB = [math]::Round($size / 1MB, 2)
                }
            } | Sort-Object SizeMB -Descending | Format-Table -AutoSize

        Write-Output ""
        Write-Output "Largest EFI files:"
        Get-ChildItem "S:\EFI" -Recurse -Force -File -ErrorAction SilentlyContinue |
            Sort-Object Length -Descending |
            Select-Object -First 30 FullName, @{n="SizeMB";e={[math]::Round($_.Length/1MB,2)}} |
            Format-Table -AutoSize
    }
    else {
        Write-Output "Unable to mount EFI partition as S:"
    }
}
finally {
    mountvol S: /D | Out-Null
}
