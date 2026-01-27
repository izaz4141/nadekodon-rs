# Stage 1: Build Flutter web
FROM ghcr.io/cirruslabs/flutter:latest AS flutter-build

WORKDIR /app

# Install minimal Rust for rinf CLI
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# Copy pub dependencies
COPY pubspec*.yaml ./
RUN flutter pub get

# Copy source code and native code (rinf gen needs native/)
COPY lib ./lib
COPY web ./web
COPY assets ./assets
COPY native ./native
COPY analysis_options.yaml ./

# Generate Rinf signals
RUN cargo install rinf_cli --version 8.7.2 && rinf gen

# Build Flutter web
RUN flutter build web --release

# Stage 2: Build Rust server
FROM rust:slim-bookworm AS rust-build

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config libssl-dev perl make \
    && rm -rf /var/lib/apt/lists/*

# Copy workspace Cargo files
COPY Cargo.toml Cargo.lock ./
COPY native native

# Build Rust server (release) and strip symbols
RUN cargo build --release -p nadekodon-server && \
    strip /app/target/release/nadekodon-server

# Stage 3: Fetch static tools
FROM debian:bookworm-slim AS tool-fetcher

WORKDIR /tools

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl xz-utils ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Download static ffmpeg
# Using a specific version for reproducibility, but latest is also fine.
RUN curl -L https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz -o ffmpeg.tar.xz \
    && tar xvf ffmpeg.tar.xz --strip-components=1 \
    && chmod a+rx ffmpeg ffprobe

# Stage 4: Final image
FROM debian:bookworm-slim

WORKDIR /app

# Install minimal runtime dependencies and download yt-dlp
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    nginx \
    gettext-base \
    ca-certificates \
    libssl3 \
    curl \
    && curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux -o /usr/local/bin/yt-dlp \
    && chmod a+rx /usr/local/bin/yt-dlp \
    && apt-get purge -y --auto-remove curl \
    && rm -rf /var/lib/apt/lists/*

# Copy tools from fetcher
COPY --from=tool-fetcher /tools/ffmpeg /usr/local/bin/ffmpeg
COPY --from=tool-fetcher /tools/ffprobe /usr/local/bin/ffprobe

# Copy Flutter web build
COPY --from=flutter-build /app/build/web ./web

# Copy Rust server binary
COPY --from=rust-build /app/target/release/nadekodon-server /usr/local/bin/nadekodon-server

# Copy assets for the server
COPY assets ./assets

# Copy nginx configuration template
COPY nginx.conf /etc/nginx/nginx.conf.template

# Create data directories
ENV NADEKO_HOME=/home/nadeko
RUN mkdir -p ${NADEKO_HOME}/config ${NADEKO_HOME}/downloads

# Create entrypoint script
COPY <<'EOF' /entrypoint.sh
#!/bin/bash
set -e

export NADEKO_HOME=${NADEKO_HOME:-/home/nadeko}
export NADEKO_SERVER_HOST=${NADEKO_SERVER_HOST:-0.0.0.0}
export NADEKO_SERVER_PORT=${NADEKO_SERVER_PORT:-8080}
export NADEKO_SERVER_API_KEY=${NADEKO_SERVER_API_KEY:-${NADEKO_API_KEY:-}}
export NADEKO_USERNAME=${NADEKO_USERNAME:-admin}
export NADEKO_PASSWORD=${NADEKO_PASSWORD:-admin}

mkdir -p "$NADEKO_HOME/config"
mkdir -p "$NADEKO_HOME/downloads"

echo "Starting Nadeko~don..."
echo "NADEKO_HOME: $NADEKO_HOME"
echo "API Server: $NADEKO_SERVER_HOST:$NADEKO_SERVER_PORT"

# Inject environment variables into nginx config
envsubst '${NADEKO_SERVER_PORT}' < /etc/nginx/nginx.conf.template > /etc/nginx/sites-available/default

# Start Rust backend server in background
cd /app
/usr/local/bin/nadekodon-server &
SERVER_PID=$!

# Give server time to start
sleep 2

# Start Nginx in background
echo "Serving UI and Proxy on port 80..."
nginx -g "daemon off;" &
NGINX_PID=$!

echo "Nadeko~don is ready!"
echo "URL: http://localhost:80"

# Handle shutdown
trap "kill $SERVER_PID $NGINX_PID 2>/dev/null" EXIT
wait
EOF
RUN chmod +x /entrypoint.sh

EXPOSE 80 8080

ENTRYPOINT ["/entrypoint.sh"]
