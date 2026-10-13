#!ps
#timeout=300000
#maxlength=2000000
echo "DIAGNOSTIC-RESPONSE/1"
echo "DiagnosticType: CleanupHPFirmwareFromEFI"
echo "ContentType: text"
echo ""
$ErrorActionPreference = "Continue"
Write-Output "Mounting EFI partition as S:"
mountvol S: /S
Start-Sleep -Seconds 2
if (-not (Test-Path "S:\EFI")) {
    Write-Output "FAILED: EFI partition did not mount as S:"
    exit 1
}
Write-Output ""
Write-Output "Before cleanup:"
Get-ChildItem "S:\EFI" -Directory -ErrorAction SilentlyContinue |
    ForEach-Object {
        $size = (Get-ChildItem $_.FullName -Recurse -Force -ErrorAction SilentlyContinue |
            Measure-Object Length -Sum).Sum
        [PSCustomObject]@{
            Path = $_.FullName
            SizeMB = [math]::Round($size / 1MB, 2)
        }
    } | Sort-Object SizeMB -Descending | Format-Table -AutoSize
$HPDevFw = "S:\EFI\HP\DEVFW"
if (Test-Path $HPDevFw) {
    Write-Output ""
    Write-Output "Backing up HP DEVFW file list before removal:"
    Get-ChildItem $HPDevFw -Recurse -Force -ErrorAction SilentlyContinue |
        Select-Object FullName, Length, LastWriteTime |
        Format-Table -AutoSize
    Write-Output ""
    Write-Output "Removing HP firmware staging folder: $HPDevFw"
    Remove-Item $HPDevFw -Recurse -Force -ErrorAction SilentlyContinue
}
else {
    Write-Output "HP DEVFW folder not found. Nothing removed."
}
Write-Output ""
Write-Output "After cleanup:"
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
Write-Output "Unmounting EFI partition."
mountvol S: /D
Write-Output ""
Write-Output "DONE. Reboot the machine, then retry the Feature Update."
