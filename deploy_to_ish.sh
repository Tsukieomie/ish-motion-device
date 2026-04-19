#!/bin/bash
# deploy_to_ish.sh  (run from Perplexity side)
# Copies the sensor bridge scripts to iSH via SSH and starts them

ISH_SSH="ssh -i /home/user/workspace/.ssh/ish_key -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p 40188 root@bore.pub"

echo "[deploy] Uploading scripts..."
tar czf /tmp/sensor_scripts.tgz -C /home/user/workspace/ish_hardware_patch \
    sensor_bridge_today.sh gps_logger.sh

$ISH_SSH "cat > /tmp/sensor_scripts.tgz" < /tmp/sensor_scripts.tgz
$ISH_SSH "cd /root && tar xzf /tmp/sensor_scripts.tgz && chmod +x sensor_bridge_today.sh gps_logger.sh"

echo "[deploy] Starting GPS logger..."
$ISH_SSH "pkill -f gps_logger.sh 2>/dev/null; nohup sh /root/gps_logger.sh > /tmp/gps_logger.log 2>&1 &"

echo "[deploy] Starting sensor bridge..."
$ISH_SSH "pkill -f sensor_bridge_today.sh 2>/dev/null; nohup sh /root/sensor_bridge_today.sh > /tmp/sensor_bridge.log 2>&1 &"

echo "[deploy] Done. Daemons running on iSH."
echo "[deploy] GPS log will appear at: /home/user/workspace/ish_mirror/root/perplexity/gps.jsonl"
echo "[deploy] Sensor log: /home/user/workspace/ish_mirror/root/perplexity/sensors.jsonl"
