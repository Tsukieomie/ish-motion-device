#!/bin/sh
# sensor_bridge_today.sh
# 
# Drop this into /root/ on iSH. It reads sensor data from /dev/clipboard,
# which an iOS Shortcut writes to. Logs to /root/perplexity/sensors.jsonl
# so Perplexity can read it via the existing sync tunnel.
#
# iOS Shortcut on the other end should:
#   1. Get Motion Activity (or use Dictate Text with sensor URL scheme)
#   2. Set Clipboard to: {"ax":X,"ay":Y,"az":Z,"lat":LAT,"lon":LON,"ts":EPOCH}
#   3. Run on a 1-second repeat (use "Repeat" action or Personal Automation)
#   4. Optional: also SSH to bore.pub:40188 to trigger this daemon

LOG=/root/perplexity/sensors.jsonl
PIDFILE=/tmp/sensor_bridge.pid
LAST=""

echo "$$" > "$PIDFILE"
echo "[sensor_bridge] started, writing to $LOG"
mkdir -p "$(dirname $LOG)"

while true; do
    # Read current clipboard
    DATA=$(cat /dev/clipboard 2>/dev/null)
    
    # Only log if data changed and looks like JSON
    if [ -n "$DATA" ] && [ "$DATA" != "$LAST" ]; then
        case "$DATA" in
            \{*)
                # Looks like JSON — add timestamp and append
                TS=$(date -u +%s)
                echo "{\"_t\":$TS,$(echo "$DATA" | sed 's/^{//')}" >> "$LOG"
                LAST="$DATA"
                echo "[sensor_bridge] logged: $DATA"
                ;;
        esac
    fi
    
    sleep 1
done
