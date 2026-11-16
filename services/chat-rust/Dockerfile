FROM rust:1.86-slim AS builder
WORKDIR /app

COPY services/chat-rust/Cargo.toml ./Cargo.toml
COPY services/chat-rust/src ./src
RUN cargo build --release

FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /app/target/release/the-match-chat-service /usr/local/bin/the-match-chat-service

ENV PORT=8080
EXPOSE 8080
CMD ["the-match-chat-service"]
