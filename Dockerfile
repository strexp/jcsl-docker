# syntax=docker/dockerfile:1
#
# Oracle Java Card Development Kit Simulator (jcsl) in a Debian slim image.
#
# jcsl is a 32-bit i386 glibc binary, so the image is linux/amd64 only and
# needs libc6-i386. JCSL_ACCEPT_LICENSE=yes must be supplied explicitly both
# when building and when running the container.

FROM --platform=linux/amd64 debian:stable-slim AS download

ARG JCSL_ACCEPT_LICENSE
ARG JCSL_URL=https://download.oracle.com/otn-pub/java/java_card_kit/3.2/java_card_devkit_simulator-linux-bin-v26.0-b_788-05-MAY-2026.tar.gz

RUN set -eux; \
    if [ "${JCSL_ACCEPT_LICENSE:-}" != "yes" ]; then \
        echo "ERROR: accept the Oracle license with --build-arg JCSL_ACCEPT_LICENSE=yes" >&2; \
        exit 1; \
    fi; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    mkdir -p /src /opt/jcsl; \
    curl -fL --retry 3 --retry-delay 2 --connect-timeout 30 --max-time 600 \
         --cookie 'oraclelicense=accept-securebackup-cookie' \
         -o /tmp/jcsl.tar.gz "$JCSL_URL"; \
    if ! tar -xzf /tmp/jcsl.tar.gz -C /src; then \
        echo "ERROR: $JCSL_URL did not return a valid tar.gz archive" >&2; \
        echo "       check JCSL_URL and the Oracle license cookie" >&2; \
        exit 1; \
    fi; \
    rm -f /tmp/jcsl.tar.gz; \
    jcsl_path=$(find /src -type f -path '*/runtime/bin/jcsl' | head -n 1); \
    if [ -z "$jcsl_path" ]; then \
        echo "ERROR: runtime/bin/jcsl not found in the archive" >&2; \
        exit 1; \
    fi; \
    root=${jcsl_path%/runtime/bin/jcsl}; \
    cp -a "$root/." /opt/jcsl/; \
    test -x /opt/jcsl/runtime/bin/jcsl; \
    test -f /opt/jcsl/tools/Configurator.jar


FROM --platform=linux/amd64 debian:stable-slim

LABEL org.opencontainers.image.title="Oracle Java Card Simulator (jcsl)" \
      org.opencontainers.image.description="Oracle Java Card Development Kit 3.2 simulator"

# libc6-i386 provides the 32-bit loader/libc required by jcsl.
# openjdk-21-jre-headless runs Configurator.jar at startup.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libc6-i386 \
        openjdk-21-jre-headless \
        socat; \
    rm -rf /var/lib/apt/lists/*; \
    useradd --uid 10001 --user-group \
        --home-dir /var/lib/jcsl --create-home \
        --shell /usr/sbin/nologin jcsl

COPY --from=download /opt/jcsl/runtime /opt/jcsl/runtime
COPY --from=download /opt/jcsl/tools/Configurator.jar /opt/jcsl/Configurator.jar
COPY entrypoint.sh /usr/local/bin/jcsl-entrypoint
RUN chmod 0755 /usr/local/bin/jcsl-entrypoint

WORKDIR /var/lib/jcsl
USER jcsl

EXPOSE 9025
ENTRYPOINT ["/usr/local/bin/jcsl-entrypoint"]
