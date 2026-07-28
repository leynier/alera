FROM rust:1.96-bookworm AS build
WORKDIR /opt/alera-cloud
COPY Cargo.toml Cargo.lock rust-toolchain.toml ./
COPY src ./src
COPY migrations ./migrations
RUN cargo build --release --locked

FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install --yes --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /opt/alera-cloud/target/release/alera-cloud /usr/local/bin/alera-cloud
USER 65532:65532
ENV ALERA_BIND=0.0.0.0:8080
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/alera-cloud"]
