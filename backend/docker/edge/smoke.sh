#!/usr/bin/env bash
# Edge smoke assertions (contracts/ci-checks.md "Edge smoke assertions", FR-019 – FR-021, FR-023).
#
# Runs the hosts' Caddyfile as the prod host's edge (WASSAL_ENV=prod) with host networking, in front
# of a stack that already listens on 127.0.0.1:8100 (API) and 127.0.0.1:8101 (admin), prod's
# upstream ports. The API site binds 127.0.0.1 and the admin site 127.0.0.2, standing in for the VNIC
# and WireGuard addresses. Linux only, since 127.0.0.2 has to be a local address. Needs ports 80, 443
# and 2019 free.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
IMAGE=caddy:2.11.7
NAME=wassal-edge-smoke
PUBLIC_IP=127.0.0.1
ADMIN_IP=127.0.0.2
API=api.127-0-0-1.sslip.io
ADMIN=admin.127-0-0-2.sslip.io
# host.env's and edge.env's variables, as the prod host has them.
EDGE_ENV=(
  -e WASSAL_ENV=prod
  -e "PUBLIC_BIND_IP=$PUBLIC_IP" -e "ADMIN_BIND_IP=$ADMIN_IP" -e PUBLIC_TLS=internal
  -e "API_HOST=$API" -e "ADMIN_HOST=$ADMIN"
)
WORK="$(mktemp -d)"
HEADERS="$WORK/headers"
BODY="$WORK/body"

cleanup() {
  local status=$?
  if [ "$status" -ne 0 ]; then
    docker logs "$NAME" 2>&1 | tail -n 50 || true
  fi
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  rm -rf "$WORK"
  exit "$status"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  echo "--- headers" >&2
  cat "$HEADERS" >&2 || true
  echo "--- body" >&2
  head -c 500 "$BODY" >&2 || true
  echo >&2
  exit 1
}

pass() { echo "ok: $*"; }

# has_json <key> <value>: the body has "key": "value", with or without a space (DRF writes compact
# JSON, Django's JsonResponse doesn't).
has_json() { grep -Eq "\"$1\": ?$2" "$BODY"; }

# fetch <host> <address> <url> [curl args…]: prints the status. Headers and body land in files.
fetch() {
  local host=$1 address=$2 url=$3
  shift 3
  : >"$HEADERS"
  : >"$BODY"
  curl --silent --insecure --max-time 10 \
    --resolve "$host:443:$address" --resolve "$host:80:$address" \
    --dump-header "$HEADERS" --output "$BODY" --write-out '%{http_code}' "$@" "$url"
}

header() { grep -i "^$1:" "$HEADERS" | head -n 1 | cut -d: -f2- | tr -d '\r' | sed 's/^ *//'; }

expect_status() { [ "$1" = "$2" ] || fail "$3: status $1, expected $2"; }

expect_security_headers() {
  local hsts max_age
  hsts="$(header Strict-Transport-Security)"
  max_age="$(sed -n 's/.*max-age=\([0-9]*\).*/\1/p' <<<"$hsts")"
  if [ -z "$max_age" ] || [ "$max_age" -lt 31536000 ]; then
    fail "$1: HSTS max-age is '$hsts'"
  fi
  grep -q includeSubDomains <<<"$hsts" || fail "$1: HSTS lacks includeSubDomains"
  [ "$(header X-Content-Type-Options)" = nosniff ] || fail "$1: X-Content-Type-Options"
  [ "$(header X-Frame-Options)" = DENY ] || fail "$1: X-Frame-Options"
  [ "$(header Referrer-Policy)" = strict-origin-when-cross-origin ] || fail "$1: Referrer-Policy"
  [ -z "$(header Server)" ] || fail "$1: the Server header is still there"
  [ -z "$(header Via)" ] || fail "$1: the Via header is still there"
}

# validate <file> [docker run args…]: the exit status of `caddy validate`, its output in a file.
validate() {
  local file=$1
  shift
  docker run --rm "${EDGE_ENV[@]}" "$@" -v "$HERE:/etc/caddy:ro" "$IMAGE" \
    caddy validate --config "/etc/caddy/$file" --adapter caddyfile >"$WORK/validate.log" 2>&1
}

echo "== caddy validate"
# Each host's environment loads; a later -e overrides EDGE_ENV's.
for env in prod staging; do
  validate Caddyfile -e "WASSAL_ENV=$env" ||
    { cat "$WORK/validate.log" >&2; fail "caddy validate Caddyfile with WASSAL_ENV=$env"; }
done
validate Caddyfile.dev || { cat "$WORK/validate.log" >&2; fail "caddy validate Caddyfile.dev"; }
pass "the Caddyfile validates for prod and staging, and Caddyfile.dev validates"

# An edge that doesn't know its environment must not start, rather than guess the ports.
for env in "" dev; do
  if validate Caddyfile -e "WASSAL_ENV=$env"; then
    fail "caddy validate Caddyfile passed with WASSAL_ENV='$env'"
  fi
  grep -q "File to import not found" "$WORK/validate.log" ||
    { cat "$WORK/validate.log" >&2; fail "WASSAL_ENV='$env': not refused for the missing snippet"; }
done
pass "the Caddyfile doesn't load with WASSAL_ENV empty or unknown"

echo "== start the prod host's edge"
docker run -d --name "$NAME" --network host "${EDGE_ENV[@]}" --tmpfs /run/caddy \
  -v "$HERE/Caddyfile:/etc/caddy/Caddyfile:ro" "$IMAGE" >/dev/null
for _ in $(seq 60); do
  if [ "$(fetch "$API" "$PUBLIC_IP" "https://$API/healthz" || true)" = 200 ]; then
    break
  fi
  sleep 0.5
done

echo "== assertions"
status="$(fetch "$API" "$PUBLIC_IP" "https://$API/healthz")"
expect_status "$status" 200 "https://api/healthz"
has_json status '"ok"' || fail "https://api/healthz: not the API's health body"
expect_security_headers "https://api/healthz"
pass "https://api/healthz → 200 with the security headers"

status="$(fetch "$API" "$PUBLIC_IP" "http://$API/healthz")"
expect_status "$status" 308 "http://api/healthz"
[ "$(header Location)" = "https://$API/healthz" ] || fail "http://api/healthz: Location"
pass "http://api/healthz → 308 to https"

head -c 600000 /dev/zero | tr '\0' 'a' >"$WORK/large"
status="$(fetch "$API" "$PUBLIC_IP" "https://$API/v1/" -X POST \
  -H 'Content-Type: application/json' --data-binary "@$WORK/large")"
expect_status "$status" 413 "600 KB POST"
has_json code '"payload_too_large"' || fail "600 KB POST: no payload_too_large envelope"
has_json limit_bytes 524288 || fail "600 KB POST: limit_bytes"
[[ "$(header Content-Type)" == application/json* ]] || fail "600 KB POST: Content-Type"
expect_security_headers "600 KB POST"
pass "600 KB POST → 413 envelope with the security headers"

status="$(fetch "$API" "$PUBLIC_IP" "https://$API/admin/")"
expect_status "$status" 404 "https://api/admin/"
has_json code '"not_found"' || fail "https://api/admin/: no not_found envelope"
pass "https://api/admin/ → 404 envelope"

status="$(fetch "$ADMIN" "$ADMIN_IP" "https://$ADMIN/v1/")"
expect_status "$status" 404 "https://admin/v1/"
pass "https://admin/v1/ → 404"

# A refused handshake would be as good as an empty answer, so a curl failure is fine here.
status="$(fetch "$ADMIN" "$PUBLIC_IP" "https://$ADMIN/admin/login/" || true)"
[ -z "$(header Content-Security-Policy)" ] || fail "admin hostname on the public bind: CSP header"
! grep -q 'login-form' "$BODY" || fail "admin hostname on the public bind: admin content"
pass "admin hostname on $PUBLIC_IP:443 → no admin (status $status, no CSP)"

status="$(fetch "$API" "$ADMIN_IP" "https://$API/healthz" || true)"
! has_json status '"ok"' || fail "API hostname on the admin bind: API content"
pass "API hostname on $ADMIN_IP:443 → no API (status $status)"

status="$(fetch "$ADMIN" "$ADMIN_IP" "https://$ADMIN/admin/login/")"
expect_status "$status" 200 "https://admin/admin/login/"
grep -q 'login-form' "$BODY" || fail "https://admin/admin/login/: no login form"
csp="$(header Content-Security-Policy)"
[ "$csp" = "$(sed -n 's/.*header Content-Security-Policy "\([^"]*\)".*/\1/p' "$HERE/Caddyfile")" ] ||
  fail "https://admin/admin/login/: CSP is '$csp'"
expect_security_headers "https://admin/admin/login/"
pass "admin hostname on $ADMIN_IP:443 → the admin, with the CSP"

status="$(fetch "$ADMIN" "$ADMIN_IP" "http://$ADMIN/admin/login/")"
expect_status "$status" 308 "http://admin/admin/login/"
pass "http://admin → 308 to https"

[ "$(curl -s --max-time 5 http://127.0.0.1:2020/)" = ok ] || fail "the health site doesn't answer"
! curl -s --max-time 2 -o /dev/null http://127.0.0.1:2019/config/ || fail "the admin API is on TCP 2019"
docker exec "$NAME" caddy reload --config /etc/caddy/Caddyfile >/dev/null 2>&1 ||
  fail "caddy reload over the admin socket"
pass "health site on 127.0.0.1:2020, admin API only on its socket, reload works"

docker exec "$NAME" tail -n 1 /var/log/caddy/access.log |
  python3 -c 'import json, sys; assert "request" in json.loads(sys.stdin.read())' ||
  fail "the access log has no JSON request line"
pass "JSON access log"

echo "edge smoke: all assertions passed"
