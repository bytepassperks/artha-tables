#!/bin/bash
# Artha Tables (Baserow) launcher for Scalingo.
# Maps Scalingo-managed Postgres/Redis URLs into Baserow's env and binds the
# embedded Caddy to the platform-provided $PORT. Scalingo terminates TLS, so we
# serve plain HTTP on $PORT (Caddy only auto-HTTPS for hostnames, not bare ports).
set -e

export DATABASE_URL="${SCALINGO_POSTGRESQL_URL:-$DATABASE_URL}"
export REDIS_URL="${SCALINGO_REDIS_URL:-$REDIS_URL}"

# Public URL Scalingo exposes this app on (used for links + CORS).
export BASEROW_PUBLIC_URL="${BASEROW_PUBLIC_URL:-https://artha-tables.osc-fr1.scalingo.io}"

# Bind the embedded Caddy reverse proxy to Scalingo's dynamic port over HTTP.
export BASEROW_CADDY_ADDRESSES=":${PORT:-80}"

exec /baserow.sh start
