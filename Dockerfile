FROM ghcr.io/intellect-lk/postgres:dev-latest

#scripts
COPY scripts/realtime.sql /docker-entrypoint-initdb.d/migrations/99-realtime.sql
COPY scripts/logs.sql /docker-entrypoint-initdb.d/migrations/99-logs.sql
COPY scripts/webhooks.sql /docker-entrypoint-initdb.d/init-scripts/98-webhooks.sql
COPY scripts/roles.sql /docker-entrypoint-initdb.d/init-scripts/99-roles.sql
COPY scripts/jwt.sql /docker-entrypoint-initdb.d/init-scripts/99-jwt.sql

