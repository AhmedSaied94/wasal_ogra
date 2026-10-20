#!/usr/bin/env bash
# Provision one host for one environment: Ubuntu 24.04 aarch64 on OCI (research R13,
# docs/runbooks/provision-host.md). Idempotent: every step checks before it changes anything.
#
#   sudo ./provision.sh --env <staging|prod> --public-ip <ip>
#                                          first run: records the host's environment for good
#   sudo ./provision.sh                    later runs, e.g. after filling /etc/wassal/*.env
#   sudo ./provision.sh --finalize         once the operator's WireGuard peer works: SSH moves
#                                          to the host's WireGuard address only and public TCP 22
#                                          closes for good
#   ./provision.sh --render-firewall <oracle-rules> [--finalize] [--public-if <if>]
#                  [--wg-address <address>] [--ipv6]
#                                          print the rendered rules and change nothing
#   ./provision.sh --identity [--env <env>] [--public-ip <ip>] [--root <dir>]
#                                          the host-identity step alone, with every path under
#                                          <dir> (the tests)
#   ./provision.sh --render-dirs <staging|prod>
#                                          print that host's state directories, one
#                                          "<mode> <owner> <path>" per line, and change nothing
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPT=/opt/wassal
ETC=/etc/wassal
STATE=/var/lib/wassal
# The image's `app` user and its group (docker/Dockerfile).
APP_UID=10001
WG_CONF=/etc/wireguard/wg0.conf
FINALIZED_MARKER="$STATE/ssh-finalized"
# Rendered rules that aren't loaded yet. It outlives a run that dies before the reload.
FIREWALL_PENDING="$STATE/firewall-pending"
DEFAULT_PUBLIC_IF=ens3
# The host's identity, from host.env or, on the first run, --env (host_identity).
WASSAL_ENV=""
WG_ADDRESS=""
WG_NET=""

log() { echo "provision: $*"; }
die() { echo "provision: $*" >&2; exit 1; }

# -- Firewall rendering (also used without root by the tests) -------------------------------------

# Oracle's rules file with the project rules inserted before the final INPUT REJECT. Rules from an
# earlier render (comment "wassal…") and Oracle's SSH accept for every interface are dropped: the
# latter would let any WireGuard peer, staff included, reach SSH. An IPv6 file without that REJECT
# filters nothing (Oracle's Ubuntu image, R13), so it comes back unchanged; an IPv4 one is an error.
# <wg_net> is the host's /24 without its last octet (10.66.0 on prod, 10.67.0 on staging).
render_firewall() {
  local source="$1" template="$2" public_if="$3" wg_net="$4" finalize="$5" ipv6="$6"
  [ -f "$source" ] || die "no such rules file: $source"
  [ -f "$template" ] || die "no such template: $template"
  awk -v template="$template" -v public_if="$public_if" -v wg_net="$wg_net" -v finalize="$finalize" -v ipv6="$ipv6" '
    function project_chains(   line) {
      while ((getline line < template) > 0) if (line ~ /^:/) print line
      close(template)
    }
    function project_rules(   line) {
      while ((getline line < template) > 0) {
        if (line ~ /^#/ || line == "" || line ~ /^:/) continue
        if (finalize == "1" && line ~ /--comment wassal-bootstrap-ssh/) continue
        gsub(/@PUBLIC_IF@/, public_if, line)
        gsub(/@WG_NET@/, wg_net, line)
        print line
      }
      close(template)
    }
    /--comment "?wassal/ || /^:DOCKER-USER / { next }
    /^\*filter/ { print; project_chains(); next }
    /^-A INPUT / && / --dport 22 / && / -j ACCEPT/ && !/ -i / { next }
    /^-A INPUT -j REJECT/ && !inserted { project_rules(); inserted = 1 }
    { print }
    END { if (!inserted && ipv6 != "1") { print "provision: no final INPUT REJECT in the rules file" > "/dev/stderr"; exit 1 } }
  ' "$source"
}

render_mode() {
  local source="" finalize=0 public_if="$DEFAULT_PUBLIC_IF" template="$HERE/iptables/rules.v4.tmpl" ipv6=0
  local wg_address
  wg_address="$(wg_address_for prod)"
  while [ $# -gt 0 ]; do
    case "$1" in
      --render-firewall) source="${2:?--render-firewall needs a rules file}"; shift 2 ;;
      --finalize) finalize=1; shift ;;
      --public-if) public_if="${2:?--public-if needs an interface}"; shift 2 ;;
      --wg-address) wg_address="${2:?--wg-address needs an address}"; shift 2 ;;
      --ipv6) template="$HERE/iptables/rules.v6.tmpl"; ipv6=1; shift ;;
      *) die "unknown option for --render-firewall: $1" ;;
    esac
  done
  [[ "$wg_address" =~ ^([0-9]{1,3}\.){3}1$ ]] || die "--wg-address needs a host's WireGuard address, like 10.66.0.1"
  render_firewall "$source" "$template" "$public_if" "${wg_address%.*}" "$finalize" "$ipv6"
}

# -- Host identity (FR-001a; also used without root by the tests) ----------------------------------

# The WireGuard address of each environment's host. It follows from the environment and is never
# given on its own.
wg_address_for() {
  case "$1" in
    prod) echo 10.66.0.1 ;;
    staging) echo 10.67.0.1 ;;
    *) return 1 ;;
  esac
}

# The timers that run on each environment's host: the host's own backups on both (staging's since
# B04, research R8), the drill of prod's backups on staging, and the host monitor on both. A backup
# or drill is skipped until its env file exists (the units' ConditionPathExists).
host_timers() {
  case "$1" in
    prod) echo wassal-backup@prod.timer wassal-host-monitor.timer ;;
    staging) echo wassal-backup@staging.timer wassal-restore-drill@prod.timer wassal-host-monitor.timer ;;
  esac
}

# The state directories of each environment's host, as "<mode> <owner> <path>". Root owns the
# environment's own directory, which holds the stack definitions that root runs. The image's app
# user owns the two that containers write: the backup's own directory (bin/backup gives it the same
# owner and mode) and the packs directory, which the worker publishes into and the edge serves
# read-only at /srv/packs (B04 contracts/environment.md).
host_dirs() {
  printf '0755 root:root %s\n' "$STATE" "$STATE/$1" "$STATE/host-monitor"
  printf '0750 %s %s\n' "$APP_UID:$APP_UID" "$STATE/$1/backup"
  printf '0755 %s %s\n' "$APP_UID:$APP_UID" "$STATE/packs"
}

# host_identity <--env or ""> <--public-ip or "">: sets WASSAL_ENV, WG_ADDRESS and WG_NET from
# host.env, or from --env on the first run, and changes nothing. host.env is data, never sourced:
# exactly the two lines record_identity writes, in either order.
host_identity() {
  local requested="$1" public_ip="$2" file="$ETC/host.env" recorded address expected
  if [ -n "$requested" ]; then
    wg_address_for "$requested" >/dev/null || die "--env must be staging or prod, not '$requested'"
  fi
  if [ ! -e "$file" ]; then
    if [ -z "$requested" ] || [ -z "$public_ip" ]; then
      die "the first run needs --env staging|prod and --public-ip <reserved public IP>"
    fi
    WASSAL_ENV="$requested"
  else
    recorded="$(sed -n 's/^WASSAL_ENV=//p' "$file")"
    address="$(sed -n 's/^WG_ADDRESS=//p' "$file")"
    if ! expected="$(wg_address_for "$recorded")" || [ "$address" != "$expected" ] \
      || [ "$(grep -c '' "$file")" -ne 2 ]; then
      die "$file is malformed: it must hold WASSAL_ENV (staging or prod) and that environment's WG_ADDRESS, and nothing else. provision.sh wrote it; find out what changed it"
    fi
    [ -z "$requested" ] || [ "$requested" = "$recorded" ] \
      || die "this is the $recorded host ($file); it can't become $requested. Changing a host's environment means rebuilding it (FR-043)"
    WASSAL_ENV="$recorded"
  fi
  WG_ADDRESS="$(wg_address_for "$WASSAL_ENV")"
  WG_NET="${WG_ADDRESS%.*}"
}

# What has to agree with the identity before anything changes. With ip_nonlocal_bind and FreeBind,
# an address that isn't the host's would still bind, and nobody could reach it.
check_host() {
  local recorded
  if [ -f "$WG_CONF" ]; then
    recorded="$(sed -n 's/^Address *= *//p' "$WG_CONF")"
    [ "$recorded" = "$WG_ADDRESS/24" ] \
      || die "$WG_CONF has Address '$recorded', not this host's $WG_ADDRESS/24. Stop wg-quick@wg0, move it and $ETC/wg-server.env aside (provision-host.md), then re-run"
  fi
  if [ -f "$ETC/edge.env" ]; then
    recorded="$(sed -n 's/^ADMIN_BIND_IP=//p' "$ETC/edge.env")"
    [ "$recorded" = "$WG_ADDRESS" ] \
      || die "$ETC/edge.env has ADMIN_BIND_IP '$recorded', not this host's WG_ADDRESS $WG_ADDRESS; the admin site would never answer"
  fi
}

# Records host.env on the first run (root, 0600). Later runs leave it alone.
record_identity() {
  local tmp
  [ ! -e "$ETC/host.env" ] || return 0
  [ -d "$ETC" ] || install -d -m 0700 "$ETC"
  tmp="$(mktemp "$ETC/.host.env.XXXXXX")"
  printf 'WASSAL_ENV=%s\nWG_ADDRESS=%s\n' "$WASSAL_ENV" "$WG_ADDRESS" > "$tmp"
  chmod 0600 "$tmp"
  mv "$tmp" "$ETC/host.env"
  log "recorded $ETC/host.env"
}

# identity <--env or ""> <--public-ip or "">: the first step of every run.
identity() {
  host_identity "$1" "$2"
  check_host
  record_identity
  log "$WASSAL_ENV host, WireGuard $WG_ADDRESS, timers $(host_timers "$WASSAL_ENV")"
}

# The one-host design ran both environments on one VM. provision.sh never deletes data, so it names
# what of that is still here and leaves it to the runbook (provision-host.md).
warn_leftovers() {
  local other path peers
  if [ "$WASSAL_ENV" = prod ]; then other=staging; else other=prod; fi
  local foreign=("$STATE/$other" "$ETC/$other.env" "$ETC/$other-db.env")
  case "$WASSAL_ENV" in
    prod) foreign+=("$ETC/staging-backup.env" "$ETC/staging-drill.env" "$ETC/prod-drill.env") ;;
    staging) foreign+=("$ETC/prod-backup.env") ;;
  esac
  for path in "${foreign[@]}"; do
    [ ! -e "$path" ] || log "WARNING: $path belongs to the $other host, not this one. Remove it (provision-host.md)."
  done
  if [ -f "$ETC/wg-peers.tsv" ]; then
    peers="$(awk -F'\t' -v net="$WG_NET." -v deploy="deploy-$WASSAL_ENV" '
      NR > 1 && $6 == "" && (index($3, net) != 1 || ($2 ~ /^deploy-/ && $2 != deploy)) { printf " %s (%s, %s)", $1, $2, $3 }
    ' "$ETC/wg-peers.tsv")"
    [ -z "$peers" ] || log "WARNING: peers that don't belong to this host's $WG_NET.0/24 network:$peers. Remove them with wg-peer remove."
  fi
  if [ -f "$ETC/edge.env" ] && grep -qE '^(PROD|STAGING)_' "$ETC/edge.env"; then
    log "WARNING: $ETC/edge.env still has the one-host PROD_/STAGING_ variables. The edge reads API_HOST and ADMIN_HOST (contracts/environment.md)."
  fi
}

# --identity: the identity step alone. --root puts every path it reads or writes under <dir>.
identity_mode() {
  local env="" public_ip="" root=""
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --env) env="${2:?--env needs staging or prod}"; shift 2 ;;
      --public-ip) public_ip="${2:?--public-ip needs an address}"; shift 2 ;;
      --root) root="${2:?--root needs a directory}"; shift 2 ;;
      *) die "unknown option for --identity: $1" ;;
    esac
  done
  ETC="$root$ETC"
  STATE="$root$STATE"
  WG_CONF="$root$WG_CONF"
  identity "$env" "$public_ip"
  warn_leftovers
}

# --render-dirs <env>: the state directories a run of that environment's host creates.
dirs_mode() {
  [ $# -eq 2 ] && wg_address_for "$2" >/dev/null || die "usage: provision.sh --render-dirs staging|prod"
  host_dirs "$2"
}

# -- Host steps ----------------------------------------------------------------------------------

check_platform() {
  [ "$(id -u)" -eq 0 ] || die "run as root (sudo ./provision.sh)"
  # shellcheck source=/dev/null
  . /etc/os-release
  if [ "${ID:-}" != ubuntu ] || [ "${VERSION_ID:-}" != 24.04 ]; then
    die "needs Ubuntu 24.04 (found ${ID:-?} ${VERSION_ID:-?})"
  fi
  [ "$(uname -m)" = aarch64 ] || die "needs aarch64 (found $(uname -m))"
}

install_packages() {
  log "packages"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -q
  apt-get upgrade -y -q
  apt-get install -y -q --no-install-recommends \
    ca-certificates curl gnupg unattended-upgrades iptables-persistent wireguard-tools python3
  # Security updates only, the Ubuntu default origins for unattended-upgrades.
  cat > /etc/apt/apt.conf.d/20auto-upgrades <<'CONF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
CONF
  if ! command -v docker >/dev/null; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    # shellcheck source=/dev/null
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      > /etc/apt/sources.list.d/docker.list
    apt-get update -q
    apt-get install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  fi
  systemctl enable --now docker
}

console_password() {
  # The OCI serial console is the break-glass path, and it needs a local password (R13).
  if passwd -S ubuntu | awk '{ exit !($2 == "L" || $2 == "NP") }'; then
    if [ -t 0 ]; then
      log "set a password for 'ubuntu' (serial console only; keep it in the password manager)"
      passwd ubuntu
    else
      log "WARNING: 'ubuntu' has no password, so the serial console can't be used. Run 'sudo passwd ubuntu'."
    fi
  fi
}

users_and_dirs() {
  log "users and directories"
  id deploy >/dev/null 2>&1 || useradd --create-home --shell /bin/bash deploy
  # Not in the docker group: a key that loses its forced command must not be root-equivalent.
  if id -nG deploy | tr ' ' '\n' | grep -qx docker; then gpasswd -d deploy docker; fi

  local sudoers tmp
  sudoers=/etc/sudoers.d/wassal-deploy
  tmp="$(mktemp)"
  # This host's environment only (contracts/environment.md).
  cat > "$tmp" <<SUDOERS
# The deploy key's forced command is: sudo /opt/wassal/bin/deploy --only $WASSAL_ENV
Defaults!/opt/wassal/bin/deploy env_keep += "SSH_ORIGINAL_COMMAND"
deploy ALL=(root) NOPASSWD: /opt/wassal/bin/deploy --only $WASSAL_ENV
SUDOERS
  visudo -cf "$tmp" >/dev/null || die "the sudoers rule doesn't parse"
  install -m 0440 -o root -g root "$tmp" "$sudoers"
  rm -f "$tmp"

  install -d -m 0755 -o root -g root "$OPT" "$OPT/bin" "$OPT/edge"
  install -d -m 0700 -o root -g root "$ETC"
  local mode owner path
  while read -r mode owner path; do
    install -d -m "$mode" -o "${owner%:*}" -g "${owner#*:}" "$path"
  done <<< "$(host_dirs "$WASSAL_ENV")"
  install -d -m 0755 -o root -g root /var/log/caddy
}

install_files() {
  log "scripts, edge, systemd and sysctl"
  install -m 0755 -o root -g root "$HERE"/bin/* "$OPT/bin/"
  # sudo's secure_path has /usr/local/sbin, not /opt/wassal/bin, so `sudo wg-peer` needs the link.
  ln -sfn "$OPT/bin/wg-peer" /usr/local/sbin/wg-peer
  cp -r "$HERE/../edge/." "$OPT/edge/"
  install -D -m 0644 "$HERE/systemd/docker.service.d/after-wg.conf" \
    /etc/systemd/system/docker.service.d/after-wg.conf
  install -m 0644 "$HERE/sysctl.d/90-wassal.conf" /etc/sysctl.d/90-wassal.conf
  sysctl --quiet --system

  # Every unit file on both hosts; only this host's timers are enabled.
  local unit link timers
  read -r -a timers <<< "$(host_timers "$WASSAL_ENV")"
  for unit in "$HERE"/systemd/*.service "$HERE"/systemd/*.timer; do
    [ -e "$unit" ] || continue
    install -m 0644 "$unit" /etc/systemd/system/
  done
  systemctl daemon-reload
  # An enabled timer is a link in timers.target.wants, template instances included.
  for link in /etc/systemd/system/timers.target.wants/wassal-*.timer; do
    [ -L "$link" ] || continue
    unit="$(basename "$link")"
    [[ " ${timers[*]} " == *" $unit "* ]] && continue
    log "disabling $unit: it doesn't run on the $WASSAL_ENV host"
    systemctl disable --now "$unit"
  done
  systemctl enable --now "${timers[@]}"
}

wireguard() {
  local public_ip="$1" private_key
  log "WireGuard wg0 on $WG_ADDRESS/24"
  if [ ! -f "$WG_CONF" ]; then
    [ -n "$public_ip" ] || die "the first run needs --public-ip <reserved public IP>"
    umask 077
    private_key="$(wg genkey)"
    sed -e "s|@WG_ADDRESS@|$WG_ADDRESS|" -e "s|@SERVER_PRIVATE_KEY@|$private_key|" \
      "$HERE/wireguard/wg0.conf.example" > "$WG_CONF"
    chmod 0600 "$WG_CONF"
    printf 'WG_SERVER_PUBLIC_KEY=%s\nWG_ENDPOINT=%s:51820\n' \
      "$(wg pubkey <<< "$private_key")" "$public_ip" > "$ETC/wg-server.env"
    umask 022
  elif [ -n "$public_ip" ]; then
    sed -i "s|^WG_ENDPOINT=.*|WG_ENDPOINT=$public_ip:51820|" "$ETC/wg-server.env"
  fi
  systemctl enable --now wg-quick@wg0
}

# firewall <finalized 0|1> <force 0|1>: render the rules, and apply them only when they changed or
# when forced (--finalize). Applying restarts Docker, so every container restarts, production's too.
firewall() {
  local finalize="$1" force="$2" public_if family source target template
  public_if="$(ip -o route show default | awk '{ print $5; exit }')"
  [ -n "$public_if" ] || die "no default route, so the public interface is unknown"
  log "firewall (public interface $public_if, finalized=$finalize)"
  [ -f "$STATE/iptables-before.txt" ] || iptables -S > "$STATE/iptables-before.txt"
  for family in 4 6; do
    target="/etc/iptables/rules.v$family"
    source="$STATE/oracle-rules.v$family"
    template="$HERE/iptables/rules.v$family.tmpl"
    [ -f "$target" ] || continue
    # Always render from Oracle's original, saved on the first run.
    [ -f "$source" ] || cp "$target" "$source"
    if [ "$family" = 6 ] && ! grep -q '^-A INPUT -j REJECT' "$source"; then
      # Leaving IPv6 unfiltered is safe only while the host has no IPv6 address.
      [ -z "$(ip -6 -o addr show scope global)" ] \
        || die "the host has a global IPv6 address, but Oracle's rules.v6 filters nothing"
      log "rules.v6 filters nothing and the host has no IPv6 address; leaving it as it is"
    fi
    render_firewall "$source" "$template" "$public_if" "$WG_NET" "$finalize" "$((family == 6))" > "$target.new"
    if cmp -s "$target.new" "$target"; then
      rm -f "$target.new"
    else
      touch "$FIREWALL_PENDING"
      mv "$target.new" "$target"
    fi
  done
  if [ ! -f "$FIREWALL_PENDING" ] && [ "$force" -eq 0 ]; then
    log "firewall unchanged; not reloading"
    return
  fi
  # Not `netfilter-persistent reload`: Oracle's image sets IPTABLES_RESTORE_NOFLUSH=yes, so a reload
  # appends to INPUT and the old rules, ahead of the new ones, keep deciding (R13). A full restore
  # leaves what a reboot loads. It drops Docker's chains too; restarting Docker puts them back.
  [ ! -f /etc/iptables/rules.v4 ] || iptables-restore < /etc/iptables/rules.v4
  [ ! -f /etc/iptables/rules.v6 ] || ip6tables-restore < /etc/iptables/rules.v6
  systemctl restart docker
  rm -f "$FIREWALL_PENDING"
}

# The edge reads host.env, then edge.env. check_host has made sure edge.env's ADMIN_BIND_IP is this
# host's WG_ADDRESS.
edge() {
  if [ -f "$ETC/edge.env" ]; then
    log "edge ($WASSAL_ENV)"
    docker compose -p wassal-edge -f "$OPT/edge/compose.yml" up -d --wait
    # `up` leaves a running container alone, so a changed Caddyfile needs a reload.
    docker compose -p wassal-edge -f "$OPT/edge/compose.yml" exec -T caddy caddy reload --config /etc/caddy/Caddyfile
  else
    log "edge skipped: fill the /etc/wassal/*.env files (quickstart step 4), then re-run provision.sh"
  fi
}

# The other environment's Compose project: containers or volumes the one-host design left here.
warn_other_project() {
  local other found
  if [ "$WASSAL_ENV" = prod ]; then other=staging; else other=prod; fi
  found="$(docker ps -aq --filter "label=com.docker.compose.project=wassal-$other")$(
    docker volume ls -q --filter "label=com.docker.compose.project=wassal-$other")"
  [ -z "$found" ] || log "WARNING: the $other environment's Compose project wassal-$other has containers or volumes here. Remove them (provision-host.md)."
}

operator_peer_is_live() {
  # An operator peer of this host (<wg>.2-9) with a handshake in the last 10 minutes. No pipeline:
  # with pipefail, `… | grep -q` can fail on SIGPIPE when several peers match.
  local now handshakes
  now="$(date +%s)"
  [ -f "$ETC/wg-peers.tsv" ] || return 1
  handshakes="$(wg show wg0 latest-handshakes)" || return 1
  HANDSHAKES="$handshakes" awk -F'\t' -v now="$now" -v net="$WG_NET." '
    BEGIN {
      n = split(ENVIRON["HANDSHAKES"], lines, "\n")
      for (i = 1; i <= n; i++) { split(lines[i], field, /[ \t]+/); latest[field[1]] = field[2] }
    }
    NR > 1 && $2 == "operator" && $6 == "" && index($3, net) == 1 && ($4 in latest) && latest[$4] > now - 600 { found = 1 }
    END { exit !found }
  ' "$ETC/wg-peers.tsv"
}

finalize_ssh() {
  log "finalize: SSH on $WG_ADDRESS only"
  # A wg0 still up with an older config would leave sshd on an address nobody can reach.
  [[ "$(ip -4 -o addr show dev wg0)" == *" inet $WG_ADDRESS/24 "* ]] \
    || die "wg0 doesn't have $WG_ADDRESS/24. Restart wg-quick@wg0 and reconnect first."
  operator_peer_is_live || die "no operator peer has a recent handshake. Connect over WireGuard first, or you would lock yourself out."
  sed "s|@WG_ADDRESS@|$WG_ADDRESS|" "$HERE/sshd_config.d/wassal.conf" > /etc/ssh/sshd_config.d/wassal.conf
  chmod 0644 /etc/ssh/sshd_config.d/wassal.conf
  install -D -m 0644 "$HERE/systemd/ssh.socket.d/wassal.conf" /etc/systemd/system/ssh.socket.d/wassal.conf
  sshd -t || die "sshd rejects the drop-in"
  systemctl daemon-reload
  systemctl restart ssh.socket
  local listening
  listening="$(ss -Htln 'sport = :22' | awk '{ print $4 }' | sort -u)"
  [ "$listening" = "$WG_ADDRESS:22" ] || die "sshd listens on '${listening//$'\n'/ }', not only $WG_ADDRESS:22; public TCP 22 stays open"
  touch "$FINALIZED_MARKER"
}

main() {
  local env="" public_ip="" finalize_now=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --env) env="${2:?--env needs staging or prod}"; shift 2 ;;
      --public-ip) public_ip="${2:?--public-ip needs an address}"; shift 2 ;;
      --finalize) finalize_now=1; shift ;;
      *) die "unknown option: $1" ;;
    esac
  done

  check_platform
  # Before anything changes: a different --env, or a malformed host.env, stops here.
  identity "$env" "$public_ip"
  install_packages
  console_password
  users_and_dirs
  install_files
  wireguard "$public_ip"
  [ "$finalize_now" -eq 0 ] || finalize_ssh
  # Once finalized, every later run keeps public SSH closed.
  if [ -f "$FINALIZED_MARKER" ]; then firewall 1 "$finalize_now"; else firewall 0 "$finalize_now"; fi
  edge
  warn_leftovers
  warn_other_project
  log "done"
}

case "${1:-}" in
  --render-firewall) render_mode "$@" ;;
  --identity) identity_mode "$@" ;;
  --render-dirs) dirs_mode "$@" ;;
  *) main "$@" ;;
esac
