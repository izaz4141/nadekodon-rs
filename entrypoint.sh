#!/bin/bash
set -e

export NADEKO_HOME=${NADEKO_HOME:-/home/nadeko}
export NADEKO_SERVER_HOST=${NADEKO_SERVER_HOST:-0.0.0.0}
export NADEKO_SERVER_PORT=${NADEKO_SERVER_PORT:-8080}
export NADEKO_SERVER_API_KEY=${NADEKO_SERVER_API_KEY:-}
export NADEKO_SERVER_MASTER_KEY=${NADEKO_SERVER_MASTER_KEY:-}
export NADEKO_USERNAME=${NADEKO_USERNAME:-admin}
export NADEKO_PASSWORD=${NADEKO_PASSWORD:-admin}

CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)

if [ -z "$NADEKO_SERVER_API_KEY" ]; then
    echo "ERROR: NADEKO_SERVER_API_KEY is not set!" >&2
    echo "Please set NADEKO_SERVER_API_KEY environment variable." >&2
    exit 1
fi

if [ -z "$NADEKO_SERVER_MASTER_KEY" ]; then
    echo "ERROR: NADEKO_SERVER_MASTER_KEY is not set!" >&2
    echo "Please set NADEKO_SERVER_MASTER_KEY environment variable." >&2
    exit 1
fi

if ! echo "$NADEKO_SERVER_MASTER_KEY" | grep -Eq '^[a-fA-F0-9]{64}$'; then
    echo "ERROR: NADEKO_SERVER_MASTER_KEY must be exactly 64 hex characters!" >&2
    exit 1
fi

is_root() { [ "$CURRENT_UID" -eq 0 ]; }

RUN_AS=""
if is_root; then
    if [ -n "$PUID" ]; then
        GID=${PGID:-$PUID}
        addgroup -g "$GID" nadeko 2>/dev/null || true
        adduser -u "$PUID" -G nadeko -D -s /bin/bash nadeko 2>/dev/null || true
        RUN_AS="su-exec nadeko"
    elif [ -n "$PGID" ] && [ "$PGID" -ne 0 ]; then
        addgroup -g "$PGID" nadeko 2>/dev/null || true
    fi
fi

if ! is_root; then
    echo "Running as non-root user (UID=$CURRENT_UID, GID=$CURRENT_GID)"
fi

mkdir -p "$NADEKO_HOME/config"
mkdir -p "$NADEKO_HOME/downloads"
mkdir -p "$NADEKO_HOME/logs"
if is_root; then
    if [ -n "$RUN_AS" ]; then
        chown -R nadeko:nadeko "$NADEKO_HOME" || { echo "ERROR: Failed to chown $NADEKO_HOME" >&2; exit 1; }
        chown -R nadeko:nadeko /var/lib/nginx /var/log/nginx /var/cache/nginx || { echo "ERROR: Failed to chown nginx directories" >&2; exit 1; }
    elif [ -n "$PGID" ] && [ "$PGID" -ne 0 ]; then
        chown -R :nadeko "$NADEKO_HOME" || { echo "ERROR: Failed to chown $NADEKO_HOME" >&2; exit 1; }
        chown -R :nadeko /var/lib/nginx /var/log/nginx /var/cache/nginx || { echo "ERROR: Failed to chown nginx directories" >&2; exit 1; }
    fi
fi

echo "Starting Nadeko~don..."
echo "NADEKO_HOME: $NADEKO_HOME"
echo "API Server: $NADEKO_SERVER_HOST:$NADEKO_SERVER_PORT"

if [ -n "$TZ" ]; then
    ln -sf /usr/share/zoneinfo/"$TZ" /etc/localtime 2>/dev/null || true
fi

envsubst '${NADEKO_SERVER_PORT}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

cd /app

echo "Starting API server..."
$RUN_AS /usr/local/bin/nadekodon-server &
SERVER_PID=$!

sleep 2

echo "Serving UI and Proxy on port 3000..."
$RUN_AS nginx -g "daemon off;" &
NGINX_PID=$!

echo "Nadeko~don is ready!"
echo "URL: http://localhost:3000"

trap "kill $SERVER_PID $NGINX_PID 2>/dev/null" EXIT
wait
