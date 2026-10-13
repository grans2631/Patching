#!sh
#timeout=1800000
#maxlength=10000000

echo "DIAGNOSTIC-RESPONSE/1"
echo "DiagnosticType: ReinstallAutomateMac"
echo "ContentType: json"
echo ""

AUTOMATE_SERVER="AutomateServer"
INSTALLER_TOKEN="InstallerToken"
MAC_AGENT_URL="$AUTOMATE_SERVER/LabTech/Deployment.aspx?InstallerToken=$INSTALLER_TOKEN"

WORKDIR="/tmp/cwa-mac-install"
ZIPFILE="$WORKDIR/MacAgent.zip"
EXTRACTDIR="$WORKDIR/extracted"
LOGFILE="$WORKDIR/install.log"

rm -rf "$WORKDIR"
mkdir -p "$EXTRACTDIR"

echo "Downloading Mac Automate installer..." >&2
curl -fL --connect-timeout 30 --max-time 300 -o "$ZIPFILE" "$MAC_AGENT_URL"

if [ "$?" -ne 0 ] || [ ! -s "$ZIPFILE" ]; then
    echo '{"status":"failed","message":"Download failed or package was empty."}'
    exit 1
fi

unzip -q "$ZIPFILE" -d "$EXTRACTDIR"

if find "$EXTRACTDIR" \( -name '*.msi' -o -name '*.mst' -o -name 'install.bat' \) | grep -q .; then
    echo '{"status":"failed","message":"Downloaded Windows installer, not Mac installer."}'
    exit 2
fi

PKG_PATH="$(find "$EXTRACTDIR" \( -name 'LTSvc.mpkg' -o -name '*.mpkg' -o -name '*.pkg' \) -type f | head -n 1)"

if [ -z "$PKG_PATH" ]; then
    echo '{"status":"failed","message":"No Mac package found. Expected LTSvc.mpkg."}'
    exit 3
fi

installer -pkg "$PKG_PATH" -target / > "$LOGFILE" 2>&1
INSTALL_EXIT=$?

if [ "$INSTALL_EXIT" -ne 0 ]; then
    echo '{"status":"failed","message":"macOS installer failed."}'
    cat "$LOGFILE"
    exit "$INSTALL_EXIT"
fi

sleep 60

LTSVC_LINE="$(launchctl list 2>/dev/null | grep 'com.labtechsoftware.LTSvc' || true)"
AGENT_PROCESS="$(ps aux 2>/dev/null | grep '/usr/local/ltechagent/ltechagent' | grep -v grep || true)"
AGENT_LOG="$(tail -n 80 /usr/local/ltechagent/agent.log 2>/dev/null || true)"

if echo "$LTSVC_LINE" | grep -q -- "-11"; then
    launchctl bootout system /Library/LaunchDaemons/com.labtechsoftware.LTSvc.plist 2>/dev/null || true
    launchctl disable system/com.labtechsoftware.LTSvc 2>/dev/null || true
    echo '{"status":"failed","message":"Install completed, but Mac agent is crashing with SIGSEGV 11. Crash loop stopped."}'
    exit 11
fi

if [ -n "$AGENT_PROCESS" ]; then
    echo '{"status":"success","message":"Mac Automate agent installed and ltechagent is running."}'
    exit 0
fi

if [ -n "$LTSVC_LINE" ]; then
    echo '{"status":"warning","message":"Mac Automate agent installed and LTSvc is loaded, but no persistent process was found yet."}'
    exit 10
fi

echo '{"status":"failed","message":"Install completed, but LTSvc is not loaded."}'
exit 12
