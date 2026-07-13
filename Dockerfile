# BlueOS extension: blueos-site-stack
# Mosquitto (MQTT) + InfluxDB 1.8 + Telegraf, pre-wired, in a single image.
# Platforms: linux/arm/v7 (Pi 3B+/4 32-bit), linux/arm64/v8 (Pi 4 64-bit / Pi 5), linux/amd64
#
# InfluxDB 1.8 is intentional: Influx 2.x has no arm/v7 image. This is the
# combined "operator-facing" product extension — the engineering split
# (blueos-mosquitto / blueos-influxdb) stays separate for development, but
# this image is what actually gets installed on a site.

# Use the Debian-based telegraf image (not alpine): alpine only publishes
# amd64/arm64, while telegraf:1.32 also includes linux/arm/v7 for Pi 3B+/4 32-bit.
FROM telegraf:1.32 AS telegraf

FROM influxdb:1.8.10

ARG IMAGE_NAME=site-stack
ARG AUTHOR="Tony White"
ARG AUTHOR_EMAIL="tony@bluerobotics.com"
ARG MAINTAINER="Tony White"
ARG MAINTAINER_EMAIL="tony@bluerobotics.com"
ARG REPO=vshie/blueos-site-stack
ARG OWNER=vshie

COPY --from=telegraf /usr/bin/telegraf /usr/bin/telegraf

# Preserve upstream Influx entrypoint (creates DB from env, starts influxd).
# Add Mosquitto from Debian apt (same base as blueos-influxdb) so one image
# covers all three services on every published architecture.
RUN cp /entrypoint.sh /influxdb-entrypoint.sh \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      mosquitto \
      mosquitto-clients \
      python3 \
      ca-certificates \
      curl \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /etc/telegraf /www /mosquitto/config /mosquitto/data /mosquitto/log

COPY config/telegraf.conf /etc/telegraf/telegraf.conf
COPY config/influxdb.conf /etc/influxdb/influxdb.conf
COPY config/mosquitto.conf /mosquitto/config/mosquitto.conf
COPY www/ /www/
COPY entrypoint.sh /blueos-entrypoint.sh
COPY scripts/time_from_rtc.py /opt/blueos/time_from_rtc.py
RUN chmod +x /blueos-entrypoint.sh /influxdb-entrypoint.sh /opt/blueos/time_from_rtc.py

# Zero-config defaults — Mosquitto, InfluxDB, and Telegraf all run in this
# one container, so Telegraf talks to both over localhost. No cross-container
# networking is required for the stack to work.
ENV INFLUXDB_DB=esphome \
    INFLUXDB_HTTP_AUTH_ENABLED=false \
    INFLUXDB_REPORTING_DISABLED=true \
    MQTT_HOST=127.0.0.1 \
    MQTT_PORT=1883 \
    MQTT_TOPIC_PREFIX=blueos/ \
    MOSQUITTO_DATA=/mosquitto/data \
    STATUS_PORT=80 \
    TIME_SYNC_ENABLE=true \
    TIME_SYNC_DRIFT_THRESHOLD_S=5 \
    TIME_SYNC_CHECK_INTERVAL_S=30

EXPOSE 80/tcp 1883/tcp 9001/tcp 8086/tcp

LABEL version="0.3.1"
LABEL type="other"
LABEL tags='["mqtt","broker","influxdb","telegraf","esphome","timeseries","automation","iot"]'
LABEL requirements="core >= 1.1"

LABEL permissions='\
{\
  "ExposedPorts": {\
    "80/tcp": {},\
    "1883/tcp": {},\
    "9001/tcp": {},\
    "8086/tcp": {}\
  },\
  "HostConfig": {\
    "ExtraHosts": ["host.docker.internal:host-gateway"],\
    "CapAdd": ["SYS_TIME"],\
    "PortBindings": {\
      "80/tcp": [{"HostPort": ""}],\
      "1883/tcp": [{"HostPort": "1883"}],\
      "9001/tcp": [{"HostPort": "9001"}],\
      "8086/tcp": [{"HostPort": "8086"}]\
    },\
    "Binds": [\
      "/usr/blueos/extensions/site-stack/mosquitto:/mosquitto/data",\
      "/usr/blueos/extensions/site-stack/influxdb:/var/lib/influxdb"\
    ]\
  }\
}'

LABEL authors='[{"name": "Tony White", "email": "tony@bluerobotics.com"}]'
LABEL company='{\
  "about": "Mosquitto + InfluxDB 1.8 + Telegraf, pre-wired for ESPHome/BlueOS MQTT telemetry",\
  "name": "Community",\
  "email": "tony@bluerobotics.com"\
}'
LABEL readme="https://raw.githubusercontent.com/${REPO}/{tag}/README.md"
LABEL links='{\
  "source": "https://github.com/vshie/blueos-site-stack",\
  "documentation": "https://github.com/vshie/blueos-site-stack/blob/main/README.md"\
}'

# Build-arg metadata (Deploy-BlueOS-Extension injects these)
LABEL org.blueos.image-name="${IMAGE_NAME}"
LABEL org.blueos.authors="[{\"name\": \"${AUTHOR}\", \"email\": \"${AUTHOR_EMAIL}\"}]"
LABEL org.blueos.company="{\"about\": \"MQTT + InfluxDB + Telegraf stack for ESPHome on BlueOS\", \"name\": \"${MAINTAINER}\", \"email\": \"${MAINTAINER_EMAIL}\"}"

ENTRYPOINT ["/blueos-entrypoint.sh"]
