#!/bin/sh
# gps_logger.sh
#
# Reads /dev/location continuously and logs to /root/perplexity/gps.jsonl
# Each line: {"ts":1234567890,"lat":37.123456,"lon":-122.123456}
# Syncs to Perplexity via the existing tar-over-SSH daemon.

LOG=/root/perplexity/gps.jsonl
PIDFILE=/tmp/gps_logger.pid

echo "$$" > "$PIDFILE"
echo "[gps_logger] started PID $$, logging to $LOG"
mkdir -p "$(dirname $LOG)"

while true; do
    LINE=$(cat /dev/location 2>/dev/null)
    if [ -n "$LINE" ]; then
        LAT=$(echo "$LINE" | cut -d',' -f1)
        LON=$(echo "$LINE" | cut -d',' -f2 | tr -d '\n')
        TS=$(date -u +%s)
        echo "{\"ts\":$TS,\"lat\":$LAT,\"lon\":$LON}" >> "$LOG"
        echo "[gps_logger] $TS $LAT $LON"
    fi
done
