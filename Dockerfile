# Stage 1: Build Flutter web
FROM ghcr.io/cirruslabs/flutter:latest AS flutter-build

WORKDIR /app

# Install Rust for rinf gen
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

COPY pubspec*.yaml ./
RUN flutter pub get

COPY lib ./lib
COPY native ./native
COPY web ./web
COPY assets ./assets
COPY analysis_options.yaml ./

RUN cargo install rinf_cli --version 8.7.2 && rinf gen
RUN flutter build web --wasm

# Stage 2: Build Rust server
FROM rust:alpine AS rust-build

WORKDIR /app

RUN apk add --no-cache \
    pkgconf \
    openssl-dev \
    perl \
    make \
    curl

COPY Cargo.toml Cargo.lock ./
COPY native/server ./native/server
COPY native/core ./native/core

RUN cargo build --release -p nadekodon-server && \
    strip /app/target/release/nadekodon-server

# Stage 3: Final image
FROM alpine:latest

WORKDIR /app

RUN apk add --no-cache \
    bash \
    nginx \
    ca-certificates \
    gettext \
    su-exec \
    curl \
    gcompat \
    tzdata \
    ffmpeg \
    python3 \
    && curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp \
    && chmod a+rx /usr/local/bin/yt-dlp

COPY --from=flutter-build /app/build/web ./web
COPY --from=rust-build /app/target/release/nadekodon-server /usr/local/bin/nadekodon-server

COPY assets ./assets
COPY nginx.conf /etc/nginx/nginx.conf.template

COPY <<'EOF' /entrypoint.sh
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
if [ -n "$RUN_AS" ]; then
    chown -R nadeko:nadeko "$NADEKO_HOME" || { echo "ERROR: Failed to chown $NADEKO_HOME" >&2; exit 1; }
elif [ -n "$PGID" ] && [ "$PGID" -ne 0 ]; then
    chown -R :nadeko "$NADEKO_HOME" || { echo "ERROR: Failed to chown $NADEKO_HOME" >&2; exit 1; }
fi

mkdir -p /var/lib/nginx/body /var/lib/nginx/proxy /var/lib/nginx/fastcgi /var/lib/nginx/uwsgi /var/lib/nginx/scgi /var/log/nginx /var/cache/nginx
if [ -n "$RUN_AS" ]; then
    chown -R nadeko:nadeko /var/lib/nginx /var/log/nginx /var/cache/nginx || { echo "ERROR: Failed to chown nginx directories" >&2; exit 1; }
elif [ -n "$PGID" ] && [ "$PGID" -ne 0 ]; then
    chown -R :nadeko /var/lib/nginx /var/log/nginx /var/cache/nginx || { echo "ERROR: Failed to chown nginx directories" >&2; exit 1; }
fi

echo "Starting Nadeko~don..."
echo "NADEKO_HOME: $NADEKO_HOME"
echo "API Server: $NADEKO_SERVER_HOST:$NADEKO_SERVER_PORT"

if [ -n "$TZ" ]; then
    ln -sf /usr/share/zoneinfo/"$TZ" /etc/localtime 2>/dev/null || true
    echo "$TZ" > /etc/timezone 2>/dev/null || true
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
EOF
RUN chmod +x /entrypoint.sh

HEALTHCHECK --interval=60s --timeout=10s --start-period=10s --retries=3 \
    CMD curl -f -s http://localhost:8080/api/nadeko/system/status || exit 1

EXPOSE 3000 8080

ENTRYPOINT ["/entrypoint.sh"]
