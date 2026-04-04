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

RUN addgroup -g 1000 nadeko && \
    adduser -u 1000 -G nadeko -D -s /bin/bash nadeko && \
    mkdir -p /home/nadeko/{config,downloads,logs} && \
    mkdir -p /var/lib/nginx /var/log/nginx /var/cache/nginx /etc/nginx && \
    chown -R nadeko:nadeko /home/nadeko /var/lib/nginx /var/log/nginx /var/cache/nginx /etc/nginx

COPY --from=flutter-build --chown=nadeko:nadeko /app/build/web ./web
COPY --from=rust-build --chown=nadeko:nadeko /app/target/release/nadekodon-server /usr/local/bin/nadekodon-server

COPY --chown=nadeko:nadeko assets ./assets
COPY --chown=nadeko:nadeko nginx.conf /etc/nginx/nginx.conf.template

COPY --chown=nadeko:nadeko entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

HEALTHCHECK --interval=60s --timeout=10s --start-period=10s --retries=3 \
    CMD curl -f -s http://localhost:8080/api/nadeko/system/status || exit 1

EXPOSE 3000 8080

USER nadeko
ENTRYPOINT ["/entrypoint.sh"]
