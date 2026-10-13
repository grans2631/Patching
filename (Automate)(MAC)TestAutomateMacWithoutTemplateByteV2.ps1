#!sh
#timeout=300000
#maxlength=10000000

echo "DIAGNOSTIC-RESPONSE/1"
echo "DiagnosticType: TestAutomateMacWithoutTemplateBytesV2"
echo "ContentType: json"
echo ""

LTSVC_LABEL="com.labtechsoftware.LTSvc"
LTSVC_PLIST="/Library/LaunchDaemons/com.labtechsoftware.LTSvc.plist"
LTECH_DIR="/usr/local/ltechagent"
TEMPLATE="$LTECH_DIR/template_bytes"
AGENT_LOG="$LTECH_DIR/agent.log"
TEST_LOG="/tmp/cwa-mac-no-template-test.log"

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/ /g; s/\r//g'
}

finish_json() {
    STATUS="$1"
    MESSAGE="$2"

    LAUNCHCTL_LIST="$(launchctl list 2>/dev/null | grep "$LTSVC_LABEL" || true)"
    LTSVC_PRINT="$(launchctl print system/$LTSVC_LABEL 2>&1 || true)"
    DISABLED_STATE="$(launchctl print-disabled system 2>/dev/null | grep -i labtech || true)"
    PROCESS_INFO="$(ps aux 2>/dev/null | egrep -i '/usr/local/ltechagent/ltechagent|ltechagent' | grep -v grep | grep -v -- '--version' || true)"
    TEMPLATE_INFO="$(ls -l "$LTECH_DIR"/template_bytes* 2>/dev/null || true)"
    PLIST_INFO="$(ls -la "$LTSVC_PLIST" 2>/dev/null || true)"
    AGENT_LOG_TAIL="$(tail -n 80 "$AGENT_LOG" 2>/dev/null || true)"
    TEST_LOG_TAIL="$(tail -n 200 "$TEST_LOG" 2>/dev/null || true)"
    CRASH_REPORTS="$(find /Library/Logs/DiagnosticReports -maxdepth 1 -type f \( -iname 'ltechagent*.ips' -o -iname 'ltechagent*.crash' \) -print 2>/dev/null | sort | tail -n 5 || true)"

    cat <<EOF
{
  "status": "$(json_escape "$STATUS")",
  "message": "$(json_escape "$MESSAGE")",
  "plistInfo": "$(json_escape "$PLIST_INFO")",
  "templateInfo": "$(json_escape "$TEMPLATE_INFO")",
  "launchctlList": "$(json_escape "$LAUNCHCTL_LIST")",
  "disabledState": "$(json_escape "$DISABLED_STATE")",
  "processInfo": "$(json_escape "$PROCESS_INFO")",
  "ltsvcPrint": "$(json_escape "$LTSVC_PRINT")",
  "agentLogTail": "$(json_escape "$AGENT_LOG_TAIL")",
  "testLogTail": "$(json_escape "$TEST_LOG_TAIL")",
  "crashReports": "$(json_escape "$CRASH_REPORTS")"
}
EOF
}

{
    echo "===== No-template test started: $(date) ====="
    echo "Running as: $(id)"
    sw_vers
    uname -a
} > "$TEST_LOG" 2>&1

if [ "$(id -u)" != "0" ]; then
    finish_json "failed" "Must run as root."
    exit 1
fi

if [ ! -f "$LTSVC_PLIST" ]; then
    finish_json "failed" "$LTSVC_PLIST does not exist. Reinstall package first."
    exit 2
fi

echo "Stopping existing service..." >> "$TEST_LOG"
launchctl bootout system "$LTSVC_PLIST" >> "$TEST_LOG" 2>&1 || true
pkill -f -i '/usr/local/ltechagent/ltechagent|ltechagent' >> "$TEST_LOG" 2>&1 || true
sleep 3

echo "Disabling template_bytes..." >> "$TEST_LOG"
if [ -f "$TEMPLATE" ]; then
    BACKUP="$LTECH_DIR/template_bytes.disabled.$(date +%Y%m%d-%H%M%S)"
    mv "$TEMPLATE" "$BACKUP" >> "$TEST_LOG" 2>&1
    echo "Moved template_bytes to $BACKUP" >> "$TEST_LOG"
else
    echo "template_bytes already absent." >> "$TEST_LOG"
fi

echo "Fixing plist permissions..." >> "$TEST_LOG"
chown root:wheel "$LTSVC_PLIST" >> "$TEST_LOG" 2>&1 || true
chmod 644 "$LTSVC_PLIST" >> "$TEST_LOG" 2>&1 || true

echo "Attempting launchctl bootstrap..." >> "$TEST_LOG"
launchctl bootstrap system "$LTSVC_PLIST" >> "$TEST_LOG" 2>&1
BOOTSTRAP_EXIT=$?
echo "bootstrap exit: $BOOTSTRAP_EXIT" >> "$TEST_LOG"

echo "Attempting launchctl enable..." >> "$TEST_LOG"
launchctl enable system/$LTSVC_LABEL >> "$TEST_LOG" 2>&1
ENABLE_EXIT=$?
echo "enable exit: $ENABLE_EXIT" >> "$TEST_LOG"

echo "Attempting launchctl kickstart..." >> "$TEST_LOG"
launchctl kickstart -kp system/$LTSVC_LABEL >> "$TEST_LOG" 2>&1
KICKSTART_EXIT=$?
echo "kickstart exit: $KICKSTART_EXIT" >> "$TEST_LOG"

sleep 45

LTSVC_LINE="$(launchctl list 2>/dev/null | grep "$LTSVC_LABEL" || true)"
REAL_PROCESS="$(ps aux 2>/dev/null | grep '/usr/local/ltechagent/ltechagent' | grep -v grep | grep -v -- '--version' || true)"
RECENT_LOG="$(tail -n 40 "$AGENT_LOG" 2>/dev/null || true)"

if echo "$LTSVC_LINE" | grep -q -- "-11"; then
    finish_json "failed" "Agent still crashes without template_bytes. This points to binary/OS/package incompatibility."
    exit 11
fi

if [ -n "$REAL_PROCESS" ]; then
    finish_json "warning" "Agent stays running without template_bytes. This confirms template_bytes triggers the crash."
    exit 0
fi

if [ "$BOOTSTRAP_EXIT" -ne 0 ] || [ "$KICKSTART_EXIT" -ne 0 ]; then
    finish_json "failed" "launchctl failed to start LTSvc without template_bytes. Review testLogTail."
    exit 3
fi

finish_json "warning" "No SIGSEGV without template_bytes, but no persistent process was found. Review agentLogTail/testLogTail."
exit 4
