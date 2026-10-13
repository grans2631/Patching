#!sh
#timeout=120000
#maxlength=200000

echo "DIAGNOSTIC-RESPONSE/1"
echo "DiagnosticType: StopAutomateMacCrashLoop"
echo "ContentType: json"
echo ""

launchctl bootout system /Library/LaunchDaemons/com.labtechsoftware.LTSvc.plist 2>/dev/null || true
launchctl disable system/com.labtechsoftware.LTSvc 2>/dev/null || true
pkill -f '/usr/local/ltechagent/ltechagent' 2>/dev/null || true

echo '{"status":"success","message":"Stopped/disabled com.labtechsoftware.LTSvc crash loop."}'
