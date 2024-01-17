FROM ghcr.io/intellecta-lk/postgres:dev-latest

# install envdir
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    daemontools \
    && rm -rf /var/lib/apt/lists/* /tmp/*

# wal-g storage setup
RUN umask u=rwx,g=rx,o= && \
    mkdir -p /etc/wal-g.d/env && \
    echo $WALG_S3_SECRET_ACCESS_KEY > /etc/wal-g.d/env/AWS_SECRET_ACCESS_KEY && \
    echo $WALG_S3_ACCESS_KEY > /etc/wal-g.d/env/AWS_ACCESS_KEY_ID && \
    # echo 's3://backup-bucket/intellecta'-$(date) > /etc/wal-g.d/env/WALG_S3_PREFIX && \
    echo 's3://backup-bucket/intellecta' > /etc/wal-g.d/env/WALG_S3_PREFIX && \
    echo $PGPASSWORD > /etc/wal-g.d/env/PGPASSWORD && \
    chown -R root:postgres /etc/wal-g.d

# setup archive
RUN echo "archive_mode = yes" >> /etc/postgresql/postgresql.conf && \
    echo "archive_command = 'envdir /etc/wal-g.d/env /usr/local/bin/wal-g wal-push %p'" >> /etc/postgresql/postgresql.conf && \
    echo "archive_timeout = 60" >> /etc/postgresql/postgresql.conf 

# backup cronjob
RUN echo "0 0 * * * postgres /usr/bin/envdir /etc/wal-g.d/env /usr/local/bin/wal-g backup-push /var/lib/postgresql/data" > /etc/cron.d/pg_backup

# setup restore
RUN echo "restore_command = '/usr/bin/envdir /etc/wal-g.d/env /usr/local/bin/wal-g wal-fetch \"%f\" \"%p\" >> /tmp/wal.log 2>&1'" >> /etc/postgresql/postgresql.conf 

#scripts
COPY scripts/realtime.sql /docker-entrypoint-initdb.d/migrations/99-realtime.sql
COPY scripts/logs.sql /docker-entrypoint-initdb.d/migrations/99-logs.sql
COPY scripts/webhooks.sql /docker-entrypoint-initdb.d/init-scripts/98-webhooks.sql
COPY scripts/roles.sql /docker-entrypoint-initdb.d/init-scripts/99-roles.sql
COPY scripts/jwt.sql /docker-entrypoint-initdb.d/init-scripts/99-jwt.sql

