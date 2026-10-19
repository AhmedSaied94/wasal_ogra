#!/usr/bin/env bash
# Creates the application role and database on a fresh volume (FR-005, research R1).
# The postgres image runs this once, as the superuser, before the server accepts connections.
# Values reach SQL only as psql variables (:'var'), never by building SQL from strings.
set -euo pipefail

: "${WASSAL_DB_PASSWORD:?WASSAL_DB_PASSWORD is required}"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres \
  -v app_password="$WASSAL_DB_PASSWORD" <<'SQL'
CREATE ROLE wassal LOGIN NOSUPERUSER NOCREATEROLE NOCREATEDB PASSWORD :'app_password';
CREATE DATABASE wassal OWNER wassal;
SQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname wassal <<'SQL'
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
GRANT pg_read_all_stats TO wassal;
SQL
