Start-Transcript -Path "C:\automation\logs\WindowsUpdateFix.log" -Force

$dlls = @('atl.dll','urlmon.dll','mshtml.dll','shdocvw.dll','browseui.dll','jscript.dll','vbscript.dll','scrrun.dll','msxml.dll','msxml3.dll','msxml6.dll ','actxprxy.dll','softpub.dll','wintrust.dll','dssenh.dll','rsaenh.dll','gpkcsp.dll','sccbase.dll','slbcsp.dll','cryptdlg.dll','oleaut32.dll','ole32.dll','shell32.dll','initpki.dll','wuapi.dll','wuaueng.dll','wuaueng1.dll','wucltui.dll','wups.dll','wups2.dll','wuweb.dll','qmgr.dll','qmgrprxy.dll','wucltux.dll','muweb.dll','wuwebv.dll ')

Write-Output "Windows Update Repair Script"

<#
Write-Output "`nReinstalling Windows update."
if ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64') {
    Start-Process -FilePath "wusa.exe" -ArgumentList "Windows8-RT-KB2937636-x64 /quiet" -Wait
} else {
    Start-Process -FilePath "wusa.exe" -ArgumentList "Windows8-RT-KB2937636-x86 /quiet" -Wait
}
#>

Write-Output "Checking Windows Update Service"
If (Get-Service -Name wuauserv -ErrorAction SilentlyContinue) {
    Write-Host "Windows Update Service is installed."
} else {
    Write-Output "The Windows Update Service is not installed, installing."
    $result = Start-Process -FilePath "sc.exe" -ArgumentList 'create wuauserv DisplayName= "Windows Update" binpath= "C:\WINDOWS\system32\svchost.exe -k netsvcs -p" Start= delayed-auto depend= RpcSs'
}

Write-Output "`nStopping services."
Stop-Service -Name "wuauserv" -Force
Stop-Service -Name "BITS" -Force
Stop-Service -Name "cryptSvc" -Force
Stop-Service -Name "appidsvc" -Force

Write-Output "`nRegistering dll files."
foreach ($dll in $dlls) {
    Start-Process -FilePath 'regsvr32.exe' -ArgumentList "/s $dll" -Wait
}

Write-Output "`nRepairing System Volume Information permissions."
Start-Process -FilePath "takeown.exe" -ArgumentList '/f "C:\System Volume Information\*" /R /D /Y'
Start-Process -FilePath "icacls.exe" -ArgumentList '"C:\System Volume Information\*" /grant:R SYSTEM:F /T /C /L'

Write-Output "`nClearing Windows Update Databases."
Remove-Item -Path "$env:SystemRoot\SoftwareDistribution\*" -Recurse -Force
Remove-Item -Path "$env:SystemRoot\System32\catroot2\*" -Recurse -Force

Write-Output "`nChecking for Windows Update registry issue."
$regval = Get-ItemProperty -Path "REGISTRY::HKEY_USERS\S-1-5-18\Software\Microsoft\Windows\CurrentVersion\Policies\WindowsUpdate" -Name "DisableWindowsUpdateAccess" -ErrorAction SilentlyContinue
If ($regval) {
    Write-Host "Removing Registry value that can prevent Windows Update from running."
    Remove-ItemProperty -Path "REGISTRY::HKEY_USERS\S-1-5-18\Software\Microsoft\Windows\CurrentVersion\Policies\WindowsUpdate" -Name "DisableWindowsUpdateAccess" -Force
}

Write-Output "`nStarting services."
Start-Service -Name "BITS"
Start-Service -Name "appidsvc"
Start-Service -Name "cryptSvc"
Try {
    Start-Service -Name "wuauserv"
} Catch {
    Write-Output "Windows Update Failed to start... trying again."
    Start-Sleep -Seconds 30
    Start-Service -Name "wuauserv"
}

Write-Output "`nForcing Windows Update discovery."
Start-Process -FilePath 'wuauclt.exe' -ArgumentList "/resetauthorization /detectnow"

Stop-Transcript
