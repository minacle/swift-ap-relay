# Build stage
FROM swift:6.3-noble AS build

WORKDIR /build

# Resolve dependencies first (cached layer).
COPY Package.swift Package.resolved ./
RUN swift package resolve

# Copy source and build.
COPY . .
RUN swift build -c release --static-swift-stdlib

# Runtime stage
FROM ubuntu:noble

RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update \
    && apt-get -q dist-upgrade -y \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        tzdata \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=build /build/.build/release/APRelay ./

ENV RELAY_HOST=0.0.0.0
ENV RELAY_PORT=8080

EXPOSE 8080

ENTRYPOINT ["./APRelay"]
CMD ["serve"]
