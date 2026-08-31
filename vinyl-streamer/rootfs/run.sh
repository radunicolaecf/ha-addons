#!/usr/bin/with-contenv bashio
# ==============================================================================
# Vinyl Streamer - Run Script
# Starts Icecast server and FFmpeg encoder
# Start/stop streaming by starting/stopping this app
# ==============================================================================

set -e

# XML escape function for security
xml_escape() {
    echo "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&apos;/g'
}

# Read configuration
STATION_NAME_RAW=$(bashio::config 'station_name')
STATION_DESC_RAW=$(bashio::config 'station_description')
STATION_NAME=$(xml_escape "${STATION_NAME_RAW}")
STATION_DESC=$(xml_escape "${STATION_DESC_RAW}")
MOUNT_POINT=$(bashio::config 'mount_point')
ICECAST_PASSWORD=$(bashio::config 'icecast_password')
LOW_LATENCY=$(bashio::config 'low_latency')

# Audio quality settings - strip "(Default)" suffix from list values
AUDIO_FORMAT=$(bashio::config 'audio_quality.format' | sed 's/ (Default)//')
AUDIO_SAMPLERATE=$(bashio::config 'audio_quality.samplerate' | sed 's/ (Default)//')
AUDIO_CHANNELS=$(bashio::config 'audio_quality.channels' | sed 's/ (Default)//')
AUDIO_BITRATE=$(bashio::config 'audio_quality.bitrate' | sed 's/ (Default)//')

# Audio processing settings
VOLUME_DB_RAW=$(bashio::config 'audio_processing.volume_db' | sed 's/ dB.*//;s/+//')
VOLUME_DB="${VOLUME_DB_RAW}"
COMPRESSOR_ENABLED=$(bashio::config 'audio_processing.compressor_enabled')
COMPRESSOR_THRESHOLD=$(bashio::config 'audio_processing.compressor_threshold' | sed 's/ dB.*//;s/ (Default)//')
COMPRESSOR_RATIO=$(bashio::config 'audio_processing.compressor_ratio' | sed 's/:1.*//;s/ (Default)//')

# Noise reduction settings
HIGHPASS_ENABLED=$(bashio::config 'noise_reduction.highpass_enabled')
HIGHPASS_FREQ=$(bashio::config 'noise_reduction.highpass_freq')
LOWPASS_ENABLED=$(bashio::config 'noise_reduction.lowpass_enabled')
LOWPASS_FREQ=$(bashio::config 'noise_reduction.lowpass_freq')
DENOISE_ENABLED=$(bashio::config 'noise_reduction.denoise_enabled')
DENOISE_STRENGTH=$(bashio::config 'noise_reduction.denoise_strength')

# Icecast settings
MAX_LISTENERS=$(bashio::config 'icecast.max_listeners')
GENRE_RAW=$(bashio::config 'icecast.genre')
GENRE=$(xml_escape "${GENRE_RAW}")

# MQTT settings
MQTT_ENABLED=$(bashio::config 'mqtt.enabled')
MQTT_HOST=$(bashio::config 'mqtt.host')
MQTT_USERNAME=$(bashio::config 'mqtt.username')
MQTT_PASSWORD=$(bashio::config 'mqtt.password')

# Recording settings
RECORDING_FORMAT=$(bashio::config 'recording.format' | sed 's/ (Default)//')
RECORDING_PATH=$(bashio::config 'recording.path')
RECORDING_ACTIVE=false
RECORDING_PID=""
RECORDING_FILE=""

# Get audio input from HA's built-in audio selector
if bashio::var.has_value "$(bashio::addon.audio_input)"; then
    AUDIO_DEVICE=$(bashio::addon.audio_input)
else
    AUDIO_DEVICE="default"
fi

bashio::log.info "Starting Vinyl Streamer..."
bashio::log.info "Station: ${STATION_NAME_RAW}"
bashio::log.info "Mount: ${MOUNT_POINT}"
bashio::log.info "Audio input: ${AUDIO_DEVICE}"
bashio::log.info "Format: ${} @ ${AUDIO_BITRATE}kbps"

# Create directories
mkdir -p /share/vinyl-streamer
mkdir -p "${RECORDING_PATH}"
START_TIME=$(date +%s)

# Restart tracking for exponential backoff
RESTART_COUNT=0
LAST_STABLE_TIME=${START_TIME}

# Create icecast user
addgroup -S icecast 2>/dev/null || true
adduser -S -G icecast -h /usr/share/icecast -s /sbin/nologin icecast 2>/dev/null || true

# Ensure directories exist
mkdir -p /var/log/icecast /etc/icecast
chown -R icecast:icecast /var/log/icecast /etc/icecast

# List available PulseAudio sources
bashio::log.info "Available PulseAudio sources:"
pactl list sources short 2>/dev/null | while read -r line; do
    bashio::log.info "  $line"
done || true

# Get HA IP address for hostname
HA_IP=$(bashio::network.ipv4_address | head -n1 | cut -d'/' -f1)
if [ -z "$HA_IP" ]; then
    HA_IP="localhost"
fi

# Set Icecast buffer sizes based on latency mode
if bashio::var.true "${LOW_LATENCY}"; then
    QUEUE_SIZE=131072
    BURST_SIZE=8192
    bashio::log.info "Low latency mode: enabled (may cause stuttering on slow networks)"
else
    QUEUE_SIZE=524288
    BURST_SIZE=65535
fi

# Generate Icecast configuration
cat > /etc/icecast/icecast.xml << EOF
<icecast>
    <location>Home</location>
    <admin>admin@localhost</admin>
    <limits>
        <clients>${MAX_LISTENERS}</clients>
        <sources>2</sources>
        <queue-size>${QUEUE_SIZE}</queue-size>
        <client-timeout>30</client-timeout>
        <header-timeout>15</header-timeout>
        <source-timeout>10</source-timeout>
        <burst-on-connect>1</burst-on-connect>
        <burst-size>${BURST_SIZE}</burst-size>
    </limits>
    <authentication>
        <source-password>${ICECAST_PASSWORD}</source-password>
        <relay-password>${ICECAST_PASSWORD}</relay-password>
        <admin-user>admin</admin-user>
        <admin-password>${ICECAST_PASSWORD}</admin-password>
    </authentication>
    <hostname>${HA_IP}</hostname>
    <listen-socket>
        <port>8000</port>
    </listen-socket>
    <mount>
        <mount-name>${MOUNT_POINT}</mount-name>
        <stream-name>${STATION_NAME}</stream-name>
        <stream-description>${STATION_DESC}</stream-description>
        <genre>${GENRE}</genre>
        <public>0</public>
    </mount>
    <fileserve>1</fileserve>
    <paths>
        <basedir>/usr/share/icecast</basedir>
        <logdir>/var/log/icecast</logdir>
        <webroot>/usr/share/icecast/web</webroot>
        <adminroot>/usr/share/icecast/admin</adminroot>
    </paths>
    <logging>
        <accesslog>access.log</accesslog>
        <errorlog>error.log</errorlog>
        <loglevel>3</loglevel>
        <logsize>10000</logsize>
    </logging>
    <security>
        <chroot>0</chroot>
        <changeowner>
            <user>icecast</user>
            <group>icecast</group>
        </changeowner>
    </security>
</icecast>
EOF
chmod 600 /etc/icecast/icecast.xml

# Start Icecast
bashio::log.info "Starting Icecast server..."
icecast -c /etc/icecast/icecast.xml &
ICECAST_PID=$!

# Wait for Icecast to be ready (port check)
for i in $(seq 1 10); do
    if nc -z localhost 8000 2>/dev/null; then
        break
    fi
    sleep 1
done

if ! nc -z localhost 8000 2>/dev/null; then
    bashio::log.error "Icecast failed to start (port 8000 not open)!"
    exit 1
fi
bashio::log.info "Icecast started on port 8000"

# Setup MQTT if enabled (after HA_IP is set)
if bashio::var.true "${MQTT_ENABLED}"; then
    if setup_mqtt; then
        mqtt_discovery
        mqtt_subscribe_commands &
    fi
fi

# Determine input format
if [ "${AUDIO_DEVICE}" = "default" ]; then
    INPUT_FORMAT="pulse"
    INPUT_DEVICE="default"
elif echo "${AUDIO_DEVICE}" | grep -q "^alsa_input\|^alsa_output"; then
    INPUT_FORMAT="pulse"
    INPUT_DEVICE="${AUDIO_DEVICE}"
else
    INPUT_FORMAT="alsa"
    INPUT_DEVICE="${AUDIO_DEVICE}"
fi

# Set channel layout based on channel count
if [ "${AUDIO_CHANNELS}" = "1" ]; then
    CHANNEL_LAYOUT="mono"
else
    CHANNEL_LAYOUT="stereo"
fi

bashio::log.info "Using ${INPUT_FORMAT} input: ${INPUT_DEVICE} (${CHANNEL_LAYOUT})"
bashio::log.info "Stream URL: http://${HA_IP}:8000${MOUNT_POINT}"

# Build audio filter chain
AUDIO_FILTERS=""

if bashio::var.true "${HIGHPASS_ENABLED}"; then
    AUDIO_FILTERS="highpass=f=${HIGHPASS_FREQ}"
    bashio::log.info "Highpass filter: ${HIGHPASS_FREQ} Hz (removes rumble)"
fi

if bashio::var.true "${LOWPASS_ENABLED}"; then
    if [ -n "${AUDIO_FILTERS}" ]; then
        AUDIO_FILTERS="${AUDIO_FILTERS},lowpass=f=${LOWPASS_FREQ}"
    else
        AUDIO_FILTERS="lowpass=f=${LOWPASS_FREQ}"
    fi
    bashio::log.info "Lowpass filter: ${LOWPASS_FREQ} Hz (removes hiss)"
fi

if bashio::var.true "${DENOISE_ENABLED}"; then
    if [ -n "${AUDIO_FILTERS}" ]; then
        AUDIO_FILTERS="${AUDIO_FILTERS},afftdn=nf=-25:nr=${DENOISE_STRENGTH}:nt=w"
    else
        AUDIO_FILTERS="afftdn=nf=-25:nr=${DENOISE_STRENGTH}:nt=w"
    fi
    bashio::log.info "Noise reduction: strength ${DENOISE_STRENGTH}"
fi

# Volume adjustment
if [ "${VOLUME_DB}" != "0" ]; then
    if [ -n "${AUDIO_FILTERS}" ]; then
        AUDIO_FILTERS="${AUDIO_FILTERS},volume=${VOLUME_DB}dB"
    else
        AUDIO_FILTERS="volume=${VOLUME_DB}dB"
    fi
    bashio::log.info "Volume adjustment: ${VOLUME_DB} dB"
fi

# Compressor
if bashio::var.true "${COMPRESSOR_ENABLED}"; then
    if [ -n "${AUDIO_FILTERS}" ]; then
        AUDIO_FILTERS="${AUDIO_FILTERS},acompressor=threshold=${COMPRESSOR_THRESHOLD}dB:ratio=${COMPRESSOR_RATIO}:attack=5:release=50"
    else
        AUDIO_FILTERS="acompressor=threshold=${COMPRESSOR_THRESHOLD}dB:ratio=${COMPRESSOR_RATIO}:attack=5:release=50"
    fi
    bashio::log.info "Audio compressor: enabled (threshold: ${COMPRESSOR_THRESHOLD} dB, ratio: ${COMPRESSOR_RATIO}:1)"
fi

if [ -z "${AUDIO_FILTERS}" ]; then
    bashio::log.info "Audio filters: none"
fi

bashio::log.info ""
bashio::log.info "Recording path: ${RECORDING_PATH}"
if bashio::var.true "${MQTT_ENABLED}"; then
    bashio::log.info "MQTT commands: vinyl_streamer/command (start_recording, stop_recording)"
fi

# Write status file for HA integration
write_status() {
    local streaming=$1
    local current_time=$(date +%s)
    local uptime=$((current_time - START_TIME))

    cat > /share/vinyl-streamer/status.json << EOF
{
  "streaming": ${streaming},
  "recording": ${RECORDING_ACTIVE},
  "recording_file": "${RECORDING_FILE}",
  "uptime_seconds": ${uptime},
  "format": "${AUDIO_FORMAT}",
  "bitrate": ${AUDIO_BITRATE},
  "samplerate": ${AUDIO_SAMPLERATE},
  "channels": ${AUDIO_CHANNELS},
  "station_name": "${STATION_NAME_RAW}",
  "mount_point": "${MOUNT_POINT}",
  "stream_url": "http://${HA_IP}:8000${MOUNT_POINT}"
}
EOF
}

# Recording functions
start_recording() {
    if [ "${RECORDING_ACTIVE}" = "true" ]; then
        bashio::log.warning "Recording already active"
        return 1
    fi

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local extension="mp3"
    local codec_args="-acodec libmp3lame -ab ${AUDIO_BITRATE}k"

    if [ "${RECORDING_FORMAT}" = "FLAC" ]; then
        extension="flac"
        codec_args="-acodec flac"
    fi

    RECORDING_FILE="${RECORDING_PATH}/vinyl_${timestamp}.${extension}"

    bashio::log.info "Starting recording: ${RECORDING_FILE}"

    # Start separate FFmpeg for recording
    ffmpeg -hide_banner -loglevel warning \
        -f ${INPUT_FORMAT} -channel_layout ${CHANNEL_LAYOUT} -i ${INPUT_DEVICE} \
        ${AUDIO_FILTERS:+-af ${AUDIO_FILTERS}} \
        ${codec_args} -ac ${AUDIO_CHANNELS} -ar ${AUDIO_SAMPLERATE} \
        "${RECORDING_FILE}" &

    RECORDING_PID=$!
    RECORDING_ACTIVE=true

    write_status true
    if bashio::var.true "${MQTT_ENABLED}"; then
        mqtt_publish_state true
    fi

    bashio::log.info "Recording started (PID: ${RECORDING_PID})"
}

stop_recording() {
    if [ "${RECORDING_ACTIVE}" != "true" ]; then
        bashio::log.warning "No recording active"
        return 1
    fi

    bashio::log.info "Stopping recording..."

    if [ -n "${RECORDING_PID}" ] && kill -0 ${RECORDING_PID} 2>/dev/null; then
        kill -SIGINT ${RECORDING_PID} 2>/dev/null || true
        sleep 2
        kill -9 ${RECORDING_PID} 2>/dev/null || true
    fi

    RECORDING_PID=""
    RECORDING_ACTIVE=false

    write_status true
    if bashio::var.true "${MQTT_ENABLED}"; then
        mqtt_publish_state true
    fi

    bashio::log.info "Recording stopped: ${RECORDING_FILE}"
    RECORDING_FILE=""
}

# MQTT functions
setup_mqtt() {
    # Try to auto-detect MQTT broker from Mosquitto app
    if [ -z "${MQTT_HOST}" ] && bashio::services.available "mqtt"; then
        MQTT_HOST=$(bashio::services "mqtt" "host")
        MQTT_PORT=$(bashio::services "mqtt" "port")
        if [ -z "${MQTT_USERNAME}" ]; then
            MQTT_USERNAME=$(bashio::services "mqtt" "username")
        fi
        if [ -z "${MQTT_PASSWORD}" ]; then
            MQTT_PASSWORD=$(bashio::services "mqtt" "password")
        fi
        bashio::log.info "MQTT: Auto-detected Mosquitto at ${MQTT_HOST}:${MQTT_PORT}"
    else
        MQTT_PORT=1883
        bashio::log.info "MQTT: Using configured host ${MQTT_HOST}:${MQTT_PORT}"
    fi

    if [ -z "${MQTT_HOST}" ]; then
        bashio::log.warning "MQTT: No broker found. Disable MQTT or install Mosquitto app."
        MQTT_ENABLED=false
        return 1
    fi
    return 0
}

mqtt_publish() {
    local topic=$1
    local payload=$2
    local retain=${3:-false}

    local mqtt_args="-h ${MQTT_HOST} -p ${MQTT_PORT}"
    if [ -n "${MQTT_USERNAME}" ]; then
        mqtt_args="${mqtt_args} -u ${MQTT_USERNAME}"
    fi
    if [ -n "${MQTT_PASSWORD}" ]; then
        mqtt_args="${mqtt_args} -P ${MQTT_PASSWORD}"
    fi
    if [ "${retain}" = "true" ]; then
        mqtt_args="${mqtt_args} -r"
    fi

    mosquitto_pub ${mqtt_args} -t "${topic}" -m "${payload}" 2>/dev/null || true
}

mqtt_subscribe_commands() {
    local mqtt_args="-h ${MQTT_HOST} -p ${MQTT_PORT}"
    if [ -n "${MQTT_USERNAME}" ]; then
        mqtt_args="${mqtt_args} -u ${MQTT_USERNAME}"
    fi
    if [ -n "${MQTT_PASSWORD}" ]; then
        mqtt_args="${mqtt_args} -P ${MQTT_PASSWORD}"
    fi

    bashio::log.info "MQTT: Listening for commands on vinyl_streamer/command"

    mosquitto_sub ${mqtt_args} -t "vinyl_streamer/command" 2>/dev/null | while read -r command; do
        bashio::log.info "MQTT command received: ${command}"
        case "${command}" in
            "start_recording")
                start_recording
                ;;
            "stop_recording")
                stop_recording
                ;;
            *)
                bashio::log.warning "Unknown MQTT command: ${command}"
                ;;
        esac
    done
}

mqtt_discovery() {
    local device_id="vinyl_streamer"
    local discovery_prefix="homeassistant"

    # Device info (shared by all entities)
    local device_info='"device":{"identifiers":["vinyl_streamer"],"name":"Vinyl Streamer","manufacturer":"owanvik","model":"HA App","sw_version":"2.0.3"}'

    # Binary sensor: Streaming status
    local config_topic="${discovery_prefix}/binary_sensor/${device_id}/streaming/config"
    local state_topic="vinyl_streamer/state"
    local config_payload="{\"name\":\"Streaming\",\"unique_id\":\"vinyl_streamer_streaming\",\"state_topic\":\"${state_topic}\",\"value_template\":\"{{ value_json.streaming }}\",\"payload_on\":\"true\",\"payload_off\":\"false\",\"device_class\":\"running\",${device_info}}"
    mqtt_publish "${config_topic}" "${config_payload}" true

    # Binary sensor: Recording status
    config_topic="${discovery_prefix}/binary_sensor/${device_id}/recording/config"
    config_payload="{\"name\":\"Recording\",\"unique_id\":\"vinyl_streamer_recording\",\"state_topic\":\"${state_topic}\",\"value_template\":\"{{ value_json.recording }}\",\"payload_on\":\"true\",\"payload_off\":\"false\",\"icon\":\"mdi:record-circle\",${device_info}}"
    mqtt_publish "${config_topic}" "${config_payload}" true

    # Sensor: Format
    config_topic="${discovery_prefix}/sensor/${device_id}/format/config"
    config_payload="{\"name\":\"Format\",\"unique_id\":\"vinyl_streamer_format\",\"state_topic\":\"${state_topic}\",\"value_template\":\"{{ value_json.format }}\",\"icon\":\"mdi:file-music\",${device_info}}"
    mqtt_publish "${config_topic}" "${config_payload}" true

    # Sensor: Bitrate
    config_topic="${discovery_prefix}/sensor/${device_id}/bitrate/config"
    config_payload="{\"name\":\"Bitrate\",\"unique_id\":\"vinyl_streamer_bitrate\",\"state_topic\":\"${state_topic}\",\"value_template\":\"{{ value_json.bitrate }}\",\"unit_of_measurement\":\"kbps\",\"icon\":\"mdi:speedometer\",${device_info}}"
    mqtt_publish "${config_topic}" "${config_payload}" true

    # Sensor: Uptime
    config_topic="${discovery_prefix}/sensor/${device_id}/uptime/config"
    config_payload="{\"name\":\"Uptime\",\"unique_id\":\"vinyl_streamer_uptime\",\"state_topic\":\"${state_topic}\",\"value_template\":\"{{ value_json.uptime_seconds }}\",\"unit_of_measurement\":\"s\",\"device_class\":\"duration\",\"icon\":\"mdi:timer\",${device_info}}"
    mqtt_publish "${config_topic}" "${config_payload}" true

    # Sensor: Stream URL
    config_topic="${discovery_prefix}/sensor/${device_id}/stream_url/config"
    config_payload="{\"name\":\"Stream URL\",\"unique_id\":\"vinyl_streamer_url\",\"state_topic\":\"${state_topic}\",\"value_template\":\"{{ value_json.stream_url }}\",\"icon\":\"mdi:link\",${device_info}}"
    mqtt_publish "${config_topic}" "${config_payload}" true

    # Button: Start Recording
    config_topic="${discovery_prefix}/button/${device_id}/start_recording/config"
    config_payload="{\"name\":\"Start Recording\",\"unique_id\":\"vinyl_streamer_start_rec\",\"command_topic\":\"vinyl_streamer/command\",\"payload_press\":\"start_recording\",\"icon\":\"mdi:record\",${device_info}}"
    mqtt_publish "${config_topic}" "${config_payload}" true

    # Button: Stop Recording
    config_topic="${discovery_prefix}/button/${device_id}/stop_recording/config"
    config_payload="{\"name\":\"Stop Recording\",\"unique_id\":\"vinyl_streamer_stop_rec\",\"command_topic\":\"vinyl_streamer/command\",\"payload_press\":\"stop_recording\",\"icon\":\"mdi:stop\",${device_info}}"
    mqtt_publish "${config_topic}" "${config_payload}" true

    bashio::log.info "MQTT: Discovery messages published"
}

mqtt_publish_state() {
    local streaming=$1
    local current_time=$(date +%s)
    local uptime=$((current_time - START_TIME))

    local state_payload="{\"streaming\":${streaming},\"recording\":${RECORDING_ACTIVE},\"recording_file\":\"${RECORDING_FILE}\",\"uptime_seconds\":${uptime},\"format\":\"${AUDIO_FORMAT}\",\"bitrate\":${AUDIO_BITRATE},\"samplerate\":${AUDIO_SAMPLERATE},\"channels\":${AUDIO_CHANNELS},\"station_name\":\"${STATION_NAME_RAW}\",\"stream_url\":\"http://${HA_IP}:8000${MOUNT_POINT}\"}"

    mqtt_publish "vinyl_streamer/state" "${state_payload}" true
}

# Cleanup on exit
cleanup() {
    bashio::log.info "Shutting down..."

    # Stop recording if active
    if [ "${RECORDING_ACTIVE}" = "true" ]; then
        stop_recording
    fi

    write_status false
    if bashio::var.true "${MQTT_ENABLED}"; then
        mqtt_publish_state false
    fi

    kill $FFMPEG_PID 2>/dev/null || true
    kill $ICECAST_PID 2>/dev/null || true
    exit 0
}
trap cleanup SIGTERM SIGINT

# Start FFmpeg with auto-restart and exponential backoff
while true; do
    bashio::log.info "Starting FFmpeg encoder..."

    # Build FFmpeg command
    FFMPEG_CMD="ffmpeg -hide_banner -loglevel warning"

    # Add low latency flags if enabled
    if bashio::var.true "${LOW_LATENCY}"; then
        FFMPEG_CMD="${FFMPEG_CMD} -fflags nobuffer -flags low_delay"
    fi

    FFMPEG_CMD="${FFMPEG_CMD} -f ${INPUT_FORMAT} -channel_layout ${CHANNEL_LAYOUT} -i ${INPUT_DEVICE}"

    # Add audio filters if any
    if [ -n "${AUDIO_FILTERS}" ]; then
        FFMPEG_CMD="${FFMPEG_CMD} -af ${AUDIO_FILTERS}"
    fi

    # Set encoder based on audio format
    case "${AUDIO_FORMAT}" in
        "FLAC")
            FFMPEG_CMD="${FFMPEG_CMD} -acodec flac -compression_level 10 -ac ${AUDIO_CHANNELS} -ar ${AUDIO_SAMPLERATE} -content_type application/ogg -f ogg"
            ;;
        "AAC")
            FFMPEG_CMD="${FFMPEG_CMD} -acodec aac -ab ${AUDIO_BITRATE}k -ac ${AUDIO_CHANNELS} -ar ${AUDIO_SAMPLERATE} -content_type audio/aac -f adts"
            ;;
        "Opus")
            FFMPEG_CMD="${FFMPEG_CMD} -acodec libopus -ab ${AUDIO_BITRATE}k -ac ${AUDIO_CHANNELS} -ar ${AUDIO_SAMPLERATE} -content_type audio/ogg -f opus"
            ;;
        *)
            # Default to MP3
            FFMPEG_CMD="${FFMPEG_CMD} -acodec libmp3lame -ab ${AUDIO_BITRATE}k -ac ${AUDIO_CHANNELS} -ar ${AUDIO_SAMPLERATE} -content_type audio/mpeg -f mp3"
            ;;
    esac

    # Write status before starting
    write_status true
    if bashio::var.true "${MQTT_ENABLED}"; then
        mqtt_publish_state true
    fi

    ${FFMPEG_CMD} "icecast://source:${ICECAST_PASSWORD}@localhost:8000${MOUNT_POINT}" &

    FFMPEG_PID=$!
    FFMPEG_START_TIME=$(date +%s)

    # Wait for FFmpeg to exit
    wait $FFMPEG_PID || true

    # Check if we should restart
    if ! kill -0 $ICECAST_PID 2>/dev/null; then
        bashio::log.error "Icecast died, exiting"
        exit 1
    fi

    # Calculate backoff
    CURRENT_TIME=$(date +%s)
    RUNTIME=$((CURRENT_TIME - FFMPEG_START_TIME))

    # Reset counter if FFmpeg ran for more than 5 minutes
    if [ ${RUNTIME} -gt 300 ]; then
        RESTART_COUNT=0
    else
        RESTART_COUNT=$((RESTART_COUNT + 1))
    fi

    # Exponential backoff: 5, 10, 20, 40, 60 (max)
    BACKOFF=$((5 * (2 ** (RESTART_COUNT - 1))))
    if [ ${BACKOFF} -gt 60 ]; then
        BACKOFF=60
    fi
    if [ ${BACKOFF} -lt 5 ]; then
        BACKOFF=5
    fi

    bashio::log.warning "FFmpeg exited after ${RUNTIME}s, restarting in ${BACKOFF} seconds... (restart #${RESTART_COUNT})"
    sleep ${BACKOFF}
done
