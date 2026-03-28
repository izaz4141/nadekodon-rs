# Stage 1: Build Flutter web
FROM ghcr.io/cirruslabs/flutter:latest AS flutter-build

WORKDIR /app

COPY pubspec*.yaml ./
RUN flutter pub get

COPY lib ./lib
COPY web ./web
COPY assets ./assets
COPY analysis_options.yaml ./

RUN flutter build web --wasm

# Stage 2: Build Rust server (static binary)
FROM rust:alpine AS rust-build

WORKDIR /app

RUN apk add --no-cache \
    pkgconf \
    openssl-dev \
    perl \
    make \
    musl-dev

ENV RUSTFLAGS="-C target-feature=+crt-static"

COPY Cargo.toml Cargo.lock ./
COPY native/server ./native/server
COPY native/core ./native/core

RUN cargo build --release -p nadekodon-server && \
    strip /app/target/release/nadekodon-server

# Stage 3: Fetch static tools
FROM alpine:latest AS tool-fetcher

WORKDIR /tools

RUN apk add --no-cache curl xz ffmpeg

RUN cp /usr/bin/ffmpeg /tools/ffmpeg && \
    cp /usr/bin/ffprobe /tools/ffprobe

# Stage 4: Final image
FROM alpine:latest

WORKDIR /app

RUN apk add --no-cache \
    bash \
    nginx \
    ca-certificates \
    gettext \
    gosu \
    curl \
    && curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux -o /usr/local/bin/yt-dlp \
    && chmod a+rx /usr/local/bin/yt-dlp

COPY --from=tool-fetcher /tools/ffmpeg /usr/local/bin/ffmpeg
COPY --from=tool-fetcher /tools/ffprobe /usr/local/bin/ffprobe

COPY --from=flutter-build /app/build/web ./web

COPY --from=rust-build /app/target/release/nadekodon-server /usr/local/bin/nadekodon-server

COPY assets ./assets
COPY nginx.conf /etc/nginx/nginx.conf.template

RUN addgroup -g 1000 nadeko && \
    adduser -u 1000 -G nadeko -D -s /bin/bash nadeko

COPY <<'EOF' /entrypoint.sh
#!/bin/bash
set -e

export PUID=${PUID:-1000}
export PGID=${PGID:-1000}
export NADEKO_HOME=${NADEKO_HOME:-/home/nadeko}
export NADEKO_SERVER_HOST=${NADEKO_SERVER_HOST:-0.0.0.0}
export NADEKO_SERVER_PORT=${NADEKO_SERVER_PORT:-8080}
export NADEKO_SERVER_API_KEY=${NADEKO_SERVER_API_KEY:-${NADEKO_API_KEY:-}}
export NADEKO_USERNAME=${NADEKO_USERNAME:-admin}
export NADEKO_PASSWORD=${NADEKO_PASSWORD:-admin}

# Create group and user with configurable PUID/PGID
addgroup -g "$PGID" nadeko 2>/dev/null || true
adduser -u "$PUID" -G "$PGID" -D -s /bin/bash nadeko 2>/dev/null || true

# Ensure data directories exist and have correct ownership
mkdir -p "$NADEKO_HOME/config"
mkdir -p "$NADEKO_HOME/downloads"
mkdir -p "$NADEKO_HOME/logs"
chown -R nadeko:nadeko "$NADEKO_HOME"

mkdir -p /var/lib/nginx/body /var/lib/nginx/proxy /var/lib/nginx/fastcgi /var/lib/nginx/uwsgi /var/lib/nginx/scgi /var/log/nginx /var/cache/nginx
chown -R nadeko:nadeko /var/lib/nginx /var/log/nginx /var/cache/nginx

echo "Starting Nadeko~don..."
echo "NADEKO_HOME: $NADEKO_HOME"
echo "API Server: $NADEKO_SERVER_HOST:$NADEKO_SERVER_PORT"

# Inject environment variables into nginx config
envsubst '${NADEKO_SERVER_PORT}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

# Run all services as non-root user using gosu
cd /app

echo "Starting API server..."
gosu nadeko /usr/local/bin/nadekodon-server &
SERVER_PID=$!

sleep 2

echo "Serving UI and Proxy on port 3000..."
gosu nadeko nginx -g "daemon off;" &
NGINX_PID=$!

echo "Nadeko~don is ready!"
echo "URL: http://localhost:3000"

trap "kill $SERVER_PID $NGINX_PID 2>/dev/null" EXIT
wait
EOF
RUN chmod +x /entrypoint.sh

EXPOSE 3000 8080

ENTRYPOINT ["/entrypoint.sh"]
