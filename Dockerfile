FROM debian:buster-slim AS builder
# hadolint ignore=DL3009,DL3008
RUN apt-get update \
  && apt-get install --yes --no-install-recommends \
    build-essential \
    ca-certificates \
    dirmngr \
    file \
    gcc \
    gnupg \
    libc-dev \
    libssl-dev \
    make \
    wget

FROM builder AS upx
RUN wget -nv --compression=gzip -O "upx-3.96-amd64_linux.tar.xz" "https://github.com/upx/upx/releases/download/v3.96/upx-3.96-amd64_linux.tar.xz" \
  && tar xf "upx-3.96-amd64_linux.tar.xz" --strip-components=1 \
  && chmod +x /upx

FROM builder AS libevent
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG LIBEVENT_VERSION=2.1.12
RUN wget -nv --compression=gzip -O "libevent-${LIBEVENT_VERSION}-stable.tar.gz" "https://github.com/libevent/libevent/releases/download/release-${LIBEVENT_VERSION}-stable/libevent-${LIBEVENT_VERSION}-stable.tar.gz" \
  && wget -nv --compression=gzip -O "libevent-${LIBEVENT_VERSION}-stable.tar.gz.asc" "https://github.com/libevent/libevent/releases/download/release-${LIBEVENT_VERSION}-stable/libevent-${LIBEVENT_VERSION}-stable.tar.gz.asc" \
  && GNUPGHOME="$(mktemp -d)" \
  && export GNUPGHOME \
  && gpg --keyserver ha.pool.sks-keyservers.net --recv-keys "9E3AC83A27974B84D1B3401DB86086848EF8686D" \
  && gpg --batch --verify "libevent-${LIBEVENT_VERSION}-stable.tar.gz.asc" "libevent-${LIBEVENT_VERSION}-stable.tar.gz" \
  && tar xzf "libevent-${LIBEVENT_VERSION}-stable.tar.gz"
WORKDIR /libevent-${LIBEVENT_VERSION}-stable
RUN ./configure --prefix=/opt \
  && make -j "$(nproc)" \
  && make install

FROM builder AS memcached
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG MEMCACHED_VERSION=1.6.9
ARG MEMCACHED_SHA1=42ae062094fdf083cfe7b21ff377c781011c2be1
RUN wget -nv -O "memcached-${MEMCACHED_VERSION}.tar.gz" "https://memcached.org/files/memcached-${MEMCACHED_VERSION}.tar.gz" \
  && echo "${MEMCACHED_SHA1} *memcached-${MEMCACHED_VERSION}.tar.gz" | sha1sum -c \
  && tar xzf "memcached-${MEMCACHED_VERSION}.tar.gz"
COPY --from=upx /upx /usr/local/bin
COPY --from=libevent /opt/ /
WORKDIR /memcached-${MEMCACHED_VERSION}
RUN ./configure --prefix=/ --with-libevent=/lib \
  && make -j "$(nproc)" \
  && make install \
  && cp --archive --parents /bin/memcached /opt \
  && cp --archive --parents /etc/passwd /opt \
  && cp --archive --parents /etc/group /opt \
  && cp --archive --parents /etc/shadow /opt \
  # hardening: remove unnecessary accounts \
  && sed --in-place --regexp-extended '/^(root|nobody)/!d' /opt/etc/group \
  && sed --in-place --regexp-extended '/^(root|nobody)/!d' /opt/etc/passwd \
  && sed --in-place --regexp-extended '/^(root|nobody)/!d' /opt/etc/shadow \
  # hardening: remove interactive shell \
  && sed --in-place --regexp-extended 's#^([^:]+):([^:]+):([^:]+):([^:]+):([^:]+):([^:]+):(.+)$#\1:\2:\3:\4:\5:\6:/bin/nologin#' /opt/etc/passwd \
  && cp --archive --parents /lib/libevent-2.1.so.* /opt \
  && cp --archive --parents /lib/x86_64-linux-gnu/libpthread.so.* /opt \
  && cp --archive --parents /lib/x86_64-linux-gnu/libpthread-* /opt \
  && cp --archive --parents /lib/x86_64-linux-gnu/libc.so.* /opt \
  && find /opt/bin/ -type f -executable -exec strip --strip-all '{}' \; \
  && find /opt/bin/ -type f -executable -exec upx '{}' \; \
  && memcached --version

FROM busybox:1.32.1-glibc
ARG MEMCACHED_VERSION=1.6.9
ARG BUILD_DATE
ARG VCS_REF
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.url="https://github.com/bc-interactive/docker-memcached"
LABEL org.opencontainers.image.source="https://github.com/bc-interactive/docker-memcached"
LABEL org.opencontainers.image.version="${MEMCACHED_VERSION}"
LABEL org.opencontainers.image.revision="${VCS_REF}"
LABEL org.opencontainers.image.vendor="bc-interactive"
LABEL org.opencontainers.image.title="memcached"
LABEL org.opencontainers.image.authors="BC INTERACTIVE <contact@bc-interactive.fr>"
COPY --from=memcached /opt /
RUN memcached --version
USER nobody
EXPOSE 11211
ENTRYPOINT ["memcached"]
