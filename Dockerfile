ARG postgres_dev_version=15
ARG postgres_version=15.1.0.148
ARG timescaledb_release=2.13.0

####################
# Setup Postgres PPA
####################
FROM ubuntu:focal as ppa
# Redeclare args for use in subsequent stages
ARG postgresql_major
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    gnupg \
    ca-certificates \
    lsb-core \
    wget \
    && rm -rf /var/lib/apt/lists/*
RUN sh -c 'echo "deb https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list' && \
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - 

####################
# Download postgres dev
####################
FROM ppa as pg-dev
ARG postgres_dev_version
# Download .deb packages
RUN apt-get update && apt-get install -y --no-install-recommends --download-only \
    postgresql-server-dev-${postgres_dev_version} \
    && rm -rf /var/lib/apt/lists/*
RUN mv /var/cache/apt/archives/*.deb /tmp/

FROM ubuntu:focal as builder
# Install build dependencies
COPY --from=pg-dev /tmp /tmp
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    /tmp/*.deb \
    build-essential \
    checkinstall \
    cmake \
    && rm -rf /var/lib/apt/lists/* /tmp/*

FROM builder as ccache
# Cache large build artifacts
RUN apt-get update && apt-get install -y --no-install-recommends \
    clang \
    ccache \
    libkrb5-dev \
    && rm -rf /var/lib/apt/lists/*
ENV CCACHE_DIR=/ccache
ENV PATH=/usr/lib/ccache:$PATH
# Used to update ccache
ARG CACHE_EPOCH

####################
# 10-timescaledb.yml
####################
FROM ccache as timescaledb-source
# Download and extract
ARG timescaledb_release
ADD "https://github.com/timescale/timescaledb/archive/refs/tags/${timescaledb_release}.tar.gz" \
    /tmp/timescaledb.tar.gz
RUN tar -xvf /tmp/timescaledb.tar.gz -C /tmp && \
    rm -rf /tmp/timescaledb.tar.gz
# Build from source
WORKDIR /tmp/timescaledb-${timescaledb_release}/build
RUN cmake ..
RUN --mount=type=cache,target=/ccache,from=public.ecr.aws/supabase/postgres:ccache \
    make -j$(nproc)
# Create debian package
RUN checkinstall -D --install=no --fstrans=no --backup=no --pakdir=/tmp --pkgname=timescaledb --pkgversion=${timescaledb_release} --nodoc


####################
# Build final image
####################
FROM supabase/postgres:${postgres_version} as production

COPY --from=timescaledb-source /tmp/*.deb /tmp/

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    /tmp/*.deb \
    # Needed for anything using libcurl
    # https://github.com/supabase/postgres/issues/573
    ca-certificates \
    && rm -rf /var/lib/apt/lists/* /tmp/*

#scripts
COPY scripts/realtime.sql /docker-entrypoint-initdb.d/migrations/99-realtime.sql
COPY scripts/logs.sql /docker-entrypoint-initdb.d/migrations/99-logs.sql
COPY scripts/webhooks.sql /docker-entrypoint-initdb.d/init-scripts/98-webhooks.sql
COPY scripts/roles.sql /docker-entrypoint-initdb.d/init-scripts/99-roles.sql
COPY scripts/jwt.sql /docker-entrypoint-initdb.d/init-scripts/99-jwt.sql