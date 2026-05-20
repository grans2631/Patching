[CmdletBinding()]
param(
    [switch]$RunDismSfc = $true
)

function Write-Section {
    param([string]$Title)

    Write-Output ""
    Write-Output "============================================================"
    Write-Output $Title
    Write-Output "============================================================"
}

$TargetPackages = @(
    "Microsoft.BioEnrollment",
    "Microsoft.Windows.OOBENetworkConnectionFlow",
    "Microsoft.Windows.OOBENetworkCaptivePortal",
    "Microsoft.UI.Xaml",
    "MicrosoftWindows.Client.Core",
    "MicrosoftWindows.Client.CBS",
    "Microsoft.AccountsControl",
    "Microsoft.AsyncTextService",
    "Microsoft.CredDialogHost",
    "Microsoft.ECApp",
    "Microsoft.LockApp",
    "Microsoft.MicrosoftEdgeDevToolsClient",
    "Microsoft.Windows.AppRep.ChxApp",
    "Microsoft.Windows.AssignedAccessLockApp",
    "Microsoft.Windows.CallingShellApp",
    "Microsoft.Windows.CapturePicker",
    "Microsoft.Windows.ParentalControls",
    "Microsoft.Windows.PinningConfirmationDialog",
    "Microsoft.XboxGameCallableUI",
    "NcsiUwpApp",
    "Microsoft.MicrosoftEdge.Stable",
    "Microsoft.OneDriveSync"
)

Write-Section "WINDOWS APPX REPAIR / RE-REGISTER TARGETED PACKAGES"
Write-Output "Computer: $env:COMPUTERNAME"
Write-Output "Start   : $(Get-Date)"

if ($RunDismSfc) {
    Write-Section "DISM RESTOREHEALTH"
    try {
        DISM /Online /Cleanup-Image /RestoreHealth
    }
    catch {
        Write-Output "DISM failed: $($_.Exception.Message)"
    }

    Write-Section "SFC SCANNOW"
    try {
        sfc /scannow
    }
    catch {
        Write-Output "SFC failed: $($_.Exception.Message)"
    }
}

Write-Section "REGISTER INSTALLED APPX PACKAGES"

$InstalledPackages = @()

try {
    $InstalledPackages = Get-AppxPackage -AllUsers -ErrorAction Stop
}
catch {
    Write-Output "Failed to query installed AppX packages: $($_.Exception.Message)"
}

# Safer AppX targeted re-register with timeout
# Prevents Add-AppxPackage from hanging forever

$RegisterTimeoutSeconds = 120

foreach ($Target in $TargetPackages) {
    Write-Output ""
    Write-Output "Checking installed AppX package: $Target"

    $Matches = $InstalledPackages | Where-Object {
        $_.Name -like "$Target*" -or $_.PackageFullName -like "$Target*"
    }

    if (-not $Matches) {
        Write-Output "NOT FOUND installed: $Target"
        continue
    }

    foreach ($Pkg in $Matches) {
        $Manifest = $null

        if ($Pkg.InstallLocation) {
            $Manifest = Join-Path $Pkg.InstallLocation "AppxManifest.xml"
        }

        if (-not $Manifest -or -not (Test-Path $Manifest)) {
            Write-Output "MISSING MANIFEST: $($Pkg.Name) | $Manifest"
            continue
        }

        # Skip known risky/stale LKG SystemApps
        if ($Pkg.Name -like "MicrosoftWindows.LKG*" -or $Pkg.InstallLocation -like "*\SystemApps\LKG\*") {
            Write-Output "SKIPPED LKG/SystemApps package: $($Pkg.Name)"
            continue
        }

        Write-Output "REGISTERING: $($Pkg.Name)"
        Write-Output "Manifest: $Manifest"

        $EncodedCommand = [Convert]::ToBase64String(
            [Text.Encoding]::Unicode.GetBytes(
                "Add-AppxPackage -DisableDevelopmentMode -Register '$Manifest' -ErrorAction Stop"
            )
        )

        $Process = Start-Process `
            -FilePath "powershell.exe" `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $EncodedCommand" `
            -WindowStyle Hidden `
            -PassThru

        $Completed = $Process.WaitForExit($RegisterTimeoutSeconds * 1000)

        if (-not $Completed) {
            Write-Output "TIMEOUT: $($Pkg.Name) exceeded $RegisterTimeoutSeconds seconds. Killing process."
            try {
                Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
            }
            catch {}
            continue
        }

        if ($Process.ExitCode -eq 0) {
            Write-Output "REGISTERED: $($Pkg.Name)"
        }
        else {
            Write-Output "FAILED REGISTER: $($Pkg.Name) | ExitCode: $($Process.ExitCode)"
        }
    }
}

Write-Section "SUMMARY"
Write-Output "Completed targeted AppX check/re-registration."
Write-Output "End: $(Get-Date)"
exit 0
