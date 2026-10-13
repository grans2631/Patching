#!ps
#timeout=300000
#maxlength=1000000

echo "DIAGNOSTIC-RESPONSE/1"
echo "DiagnosticType: WindowsEditionCheck"
echo "ContentType: text"
echo ""

$CV = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"

Write-Output "ProductName:    $($CV.ProductName)"
Write-Output "EditionID:      $($CV.EditionID)"
Write-Output "DisplayVersion: $($CV.DisplayVersion)"
Write-Output "Build:          $($CV.CurrentBuild).$($CV.UBR)"

Write-Output ""
Write-Output "DISM edition:"
dism.exe /Online /Get-CurrentEdition
