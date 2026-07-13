#!/bin/bash
set -euo pipefail

STATUS_PORT="${STATUS_PORT:-80}"
MQTT_HOST="${MQTT_HOST:-127.0.0.1}"
MQTT_PORT="${MQTT_PORT:-1883}"
MQTT_TOPIC_PREFIX="${MQTT_TOPIC_PREFIX:-blueos/}"
INFLUX_DB="${INFLUXDB_DB:-esphome}"
MOSQUITTO_DATA="${MOSQUITTO_DATA:-/mosquitto/data}"
MOSQUITTO_CONF="${MOSQUITTO_CONF:-/mosquitto/config/mosquitto.conf}"

export MQTT_HOST MQTT_PORT MQTT_TOPIC_PREFIX

mkdir -p "$MOSQUITTO_DATA" /mosquitto/log

TELEGRAF_CONF=/tmp/telegraf.conf
sed \
  -e "s|\${MQTT_HOST}|${MQTT_HOST}|g" \
  -e "s|\${MQTT_PORT}|${MQTT_PORT}|g" \
  -e "s|\${MQTT_TOPIC_PREFIX}|${MQTT_TOPIC_PREFIX}|g" \
  /etc/telegraf/telegraf.conf > "$TELEGRAF_CONF"

cat > /www/runtime.json <<EOF
{
  "service": "blueos-site-stack",
  "version": "0.1.0",
  "influx_version": "1.8",
  "influx_ui": "http://<blueos-ip>:8086",
  "database": "${INFLUX_DB}",
  "auth": false,
  "mqtt_tcp": ${MQTT_PORT},
  "mqtt_websockets": 9001,
  "mqtt_anonymous": true,
  "mqtt_topic_prefix": "${MQTT_TOPIC_PREFIX}"
}
EOF

echo "Starting Mosquitto with ${MOSQUITTO_CONF}..."
mosquitto -c "$MOSQUITTO_CONF" &
MQTT_PID=$!

echo "Waiting for Mosquitto on ${MQTT_HOST}:${MQTT_PORT}..."
for _ in $(seq 1 30); do
  if mosquitto_sub -h 127.0.0.1 -p "$MQTT_PORT" -t '$SYS/broker/version' -C 1 -W 2 >/dev/null 2>&1; then
    echo "Mosquitto is up"
    break
  fi
  if ! kill -0 "$MQTT_PID" 2>/dev/null; then
    echo "Mosquitto exited early" >&2
    wait "$MQTT_PID" || true
    exit 1
  fi
  sleep 1
done

echo "Starting InfluxDB 1.8 (database=${INFLUX_DB})..."
INFLUXDB_CONFIG_PATH=/etc/influxdb/influxdb.conf \
  /influxdb-entrypoint.sh influxd -config /etc/influxdb/influxdb.conf &
INFLUX_PID=$!

echo "Waiting for InfluxDB..."
for _ in $(seq 1 60); do
  if curl -sf "http://127.0.0.1:8086/ping" >/dev/null 2>&1; then
    echo "InfluxDB is up"
    break
  fi
  if ! kill -0 "$INFLUX_PID" 2>/dev/null; then
    echo "InfluxDB exited early" >&2
    wait "$INFLUX_PID" || true
    exit 1
  fi
  sleep 2
done

if ! curl -sf "http://127.0.0.1:8086/ping" >/dev/null 2>&1; then
  echo "InfluxDB failed to become ready" >&2
  exit 1
fi

# Ensure database exists (entrypoint usually creates it; belt-and-suspenders).
curl -sf "http://127.0.0.1:8086/query" --data-urlencode "q=CREATE DATABASE ${INFLUX_DB}" >/dev/null || true

echo "Starting Telegraf → MQTT ${MQTT_HOST}:${MQTT_PORT} (${MQTT_TOPIC_PREFIX}#) → InfluxDB ${INFLUX_DB}..."
telegraf --config "$TELEGRAF_CONF" &
TELEGRAF_PID=$!

echo "Starting status UI on :${STATUS_PORT}"
python3 -m http.server "$STATUS_PORT" --bind 0.0.0.0 --directory /www &
HTTP_PID=$!

echo "Starting time-from-RTC sidecar (enable=${TIME_SYNC_ENABLE:-true})..."
MQTT_HOST=127.0.0.1 MQTT_PORT="$MQTT_PORT" MQTT_TOPIC_PREFIX="$MQTT_TOPIC_PREFIX" \
  python3 /opt/blueos/time_from_rtc.py &
TIME_SYNC_PID=$!

shutdown() {
  echo "Shutting down..."
  kill "$TELEGRAF_PID" "$HTTP_PID" "$INFLUX_PID" "$MQTT_PID" "$TIME_SYNC_PID" 2>/dev/null || true
  wait "$TELEGRAF_PID" "$HTTP_PID" "$INFLUX_PID" "$MQTT_PID" "$TIME_SYNC_PID" 2>/dev/null || true
}
trap shutdown INT TERM

while kill -0 "$MQTT_PID" 2>/dev/null \
  && kill -0 "$INFLUX_PID" 2>/dev/null \
  && kill -0 "$TELEGRAF_PID" 2>/dev/null \
  && kill -0 "$HTTP_PID" 2>/dev/null; do
  sleep 2
done

echo "A child process exited; shutting down." >&2
shutdown
exit 1
