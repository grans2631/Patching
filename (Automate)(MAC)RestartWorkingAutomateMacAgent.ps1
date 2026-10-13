#!sh
#timeout=300000
#maxlength=10000000

echo "DIAGNOSTIC-RESPONSE/1"
echo "DiagnosticType: RestartWorkingAutomateMacAgent"
echo "ContentType: json"
echo ""

LTSVC_LABEL="com.labtechsoftware.LTSvc"
LTSVC_PLIST="/Library/LaunchDaemons/com.labtechsoftware.LTSvc.plist"
LTECH_DIR="/usr/local/ltechagent"
AGENT_LOG="$LTECH_DIR/agent.log"
LOG="/tmp/cwa-restart-working-agent.log"

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/ /g; s/\r//g'
}

finish_json() {
    STATUS="$1"
    MESSAGE="$2"

    LAUNCHCTL_LIST="$(launchctl list 2>/dev/null | grep "$LTSVC_LABEL" || true)"
    LTSVC_PRINT="$(launchctl print system/$LTSVC_LABEL 2>&1 || true)"
    DISABLED_STATE="$(launchctl print-disabled system 2>/dev/null | grep "$LTSVC_LABEL" || true)"
    PROCESS_INFO="$(ps aux 2>/dev/null | awk '/\/usr\/local\/ltechagent\/ltechagent/ && !/awk/ {print}' || true)"
    TEMPLATE_INFO="$(ls -la "$LTECH_DIR"/template_bytes* 2>/dev/null || true)"
    AGENT_LOG_TAIL="$(tail -n 160 "$AGENT_LOG" 2>/dev/null || true)"
    LOG_TAIL="$(tail -n 160 "$LOG" 2>/dev/null || true)"

    cat <<EOF
{
  "status": "$(json_escape "$STATUS")",
  "message": "$(json_escape "$MESSAGE")",
  "launchctlList": "$(json_escape "$LAUNCHCTL_LIST")",
  "disabledState": "$(json_escape "$DISABLED_STATE")",
  "processInfo": "$(json_escape "$PROCESS_INFO")",
  "templateInfo": "$(json_escape "$TEMPLATE_INFO")",
  "ltsvcPrint": "$(json_escape "$LTSVC_PRINT")",
  "agentLogTail": "$(json_escape "$AGENT_LOG_TAIL")",
  "logTail": "$(json_escape "$LOG_TAIL")"
}
EOF
}

{
    echo "===== Restart working Automate Mac agent: $(date) ====="
    echo "Running as: $(id)"
    sw_vers
    uname -a
} > "$LOG" 2>&1

if [ "$(id -u)" != "0" ]; then
    finish_json "failed" "Must run as root."
    exit 1
fi

if [ ! -f "$LTSVC_PLIST" ]; then
    finish_json "failed" "$LTSVC_PLIST does not exist."
    exit 2
fi

echo "Fixing plist permissions..." >> "$LOG"
chown root:wheel "$LTSVC_PLIST" >> "$LOG" 2>&1 || true
chmod 644 "$LTSVC_PLIST" >> "$LOG" 2>&1 || true

echo "Clearing disabled state..." >> "$LOG"
launchctl enable system/$LTSVC_LABEL >> "$LOG" 2>&1 || true

echo "Trying bootstrap..." >> "$LOG"
launchctl bootstrap system "$LTSVC_PLIST" >> "$LOG" 2>&1 || true

sleep 3

echo "Trying kickstart..." >> "$LOG"
launchctl kickstart -kp system/$LTSVC_LABEL >> "$LOG" 2>&1 || true

sleep 90

LTSVC_LINE="$(launchctl list 2>/dev/null | grep "$LTSVC_LABEL" || true)"
PROCESS_INFO="$(ps aux 2>/dev/null | awk '/\/usr\/local\/ltechagent\/ltechagent/ && !/awk/ {print}' || true)"
RECENT_LOG="$(tail -n 200 "$AGENT_LOG" 2>/dev/null || true)"

if [ -n "$PROCESS_INFO" ] && echo "$RECENT_LOG" | egrep -qi 'Connected to server|Successfully sent server command|Checking in|Saving agent state'; then
    finish_json "success" "Automate Mac agent is running and checking in."
    exit 0
fi

if [ -n "$PROCESS_INFO" ]; then
    finish_json "warning" "Automate Mac agent process is running, but recent check-in confirmation was not found yet."
    exit 10
fi

if echo "$LTSVC_LINE" | grep -q -- "-11"; then
    finish_json "failed" "LTSvc is crashing with SIGSEGV 11."
    exit 11
fi

finish_json "failed" "LTSvc did not start. Review logTail/ltsvcPrint."
exit 20
