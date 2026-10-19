#!/usr/bin/env bash
# Provision the production host: Ubuntu 24.04 aarch64 on OCI (research R13,
# docs/runbooks/provision-host.md). Idempotent: every step checks before it changes anything.
#
#   sudo ./provision.sh --public-ip <ip>   first run
#   sudo ./provision.sh                    later runs, e.g. after filling /etc/wassal/*.env
#   sudo ./provision.sh --finalize         once the operator's WireGuard peer works: SSH moves
#                                          to 10.66.0.1 only and public TCP 22 closes for good
#   ./provision.sh --render-firewall <oracle-rules> [--finalize] [--public-if <if>] [--ipv6]
#                                          print the rendered rules and change nothing
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPT=/opt/wassal
ETC=/etc/wassal
STATE=/var/lib/wassal
FINALIZED_MARKER="$STATE/ssh-finalized"
WG_ADDRESS=10.66.0.1
DEFAULT_PUBLIC_IF=ens3

log() { echo "provision: $*"; }
die() { echo "provision: $*" >&2; exit 1; }

# -- Firewall rendering (also used without root by the tests) -------------------------------------

# Oracle's rules file with the project rules inserted before the final INPUT REJECT. Rules from an
# earlier render (comment "wassal…") and Oracle's SSH accept for every interface are dropped: the
# latter would let any WireGuard peer, staff included, reach SSH.
render_firewall() {
  local source="$1" template="$2" public_if="$3" finalize="$4"
  [ -f "$source" ] || die "no such rules file: $source"
  [ -f "$template" ] || die "no such template: $template"
  awk -v template="$template" -v public_if="$public_if" -v finalize="$finalize" '
    function project_chains(   line) {
      while ((getline line < template) > 0) if (line ~ /^:/) print line
      close(template)
    }
    function project_rules(   line) {
      while ((getline line < template) > 0) {
        if (line ~ /^#/ || line == "" || line ~ /^:/) continue
        if (finalize == "1" && line ~ /--comment wassal-bootstrap-ssh/) continue
        gsub(/@PUBLIC_IF@/, public_if, line)
        print line
      }
      close(template)
    }
    /--comment "?wassal/ || /^:DOCKER-USER / { next }
    /^\*filter/ { print; project_chains(); next }
    /^-A INPUT / && / --dport 22 / && / -j ACCEPT/ && !/ -i / { next }
    /^-A INPUT -j REJECT/ && !inserted { project_rules(); inserted = 1 }
    { print }
    END { if (!inserted) { print "provision: no final INPUT REJECT in the rules file" > "/dev/stderr"; exit 1 } }
  ' "$source"
}

render_mode() {
  local source="" finalize=0 public_if="$DEFAULT_PUBLIC_IF" template="$HERE/iptables/rules.v4.tmpl"
  while [ $# -gt 0 ]; do
    case "$1" in
      --render-firewall) source="${2:?--render-firewall needs a rules file}"; shift 2 ;;
      --finalize) finalize=1; shift ;;
      --public-if) public_if="${2:?--public-if needs an interface}"; shift 2 ;;
      --ipv6) template="$HERE/iptables/rules.v6.tmpl"; shift ;;
      *) die "unknown option for --render-firewall: $1" ;;
    esac
  done
  render_firewall "$source" "$template" "$public_if" "$finalize"
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
  cat > "$tmp" <<'SUDOERS'
# The deploy key's forced command is `sudo /opt/wassal/bin/deploy --only <env>` (contracts/environment.md).
Defaults!/opt/wassal/bin/deploy env_keep += "SSH_ORIGINAL_COMMAND"
deploy ALL=(root) NOPASSWD: /opt/wassal/bin/deploy --only staging, /opt/wassal/bin/deploy --only prod
SUDOERS
  visudo -cf "$tmp" >/dev/null || die "the sudoers rule doesn't parse"
  install -m 0440 -o root -g root "$tmp" "$sudoers"
  rm -f "$tmp"

  install -d -m 0755 -o root -g root "$OPT" "$OPT/bin" "$OPT/edge"
  install -d -m 0700 -o root -g root "$ETC"
  install -d -m 0755 -o root -g root "$STATE" "$STATE/staging" "$STATE/prod" "$STATE/host-monitor"
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

  local unit timers=()
  for unit in "$HERE"/systemd/*.service "$HERE"/systemd/*.timer; do
    [ -e "$unit" ] || continue
    install -m 0644 "$unit" /etc/systemd/system/
    # Templates (backup, restore drill) run for production only.
    case "$unit" in
      *@.timer) timers+=("$(basename "$unit" .timer)prod.timer") ;;
      *.timer) timers+=("$(basename "$unit")") ;;
    esac
  done
  systemctl daemon-reload
  if [ "${#timers[@]}" -gt 0 ]; then systemctl enable --now "${timers[@]}"; fi
}

wireguard() {
  local public_ip="$1" private_key
  log "WireGuard wg0"
  if [ ! -f /etc/wireguard/wg0.conf ]; then
    [ -n "$public_ip" ] || die "the first run needs --public-ip <reserved public IP>"
    umask 077
    private_key="$(wg genkey)"
    sed "s|@SERVER_PRIVATE_KEY@|$private_key|" "$HERE/wireguard/wg0.conf.example" > /etc/wireguard/wg0.conf
    chmod 0600 /etc/wireguard/wg0.conf
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
  local finalize="$1" force="$2" changed=0 public_if family source target template
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
    render_firewall "$source" "$template" "$public_if" "$finalize" > "$target.new"
    if cmp -s "$target.new" "$target"; then
      rm -f "$target.new"
    else
      mv "$target.new" "$target"
      changed=1
    fi
  done
  if [ "$changed" -eq 0 ] && [ "$force" -eq 0 ]; then
    log "firewall unchanged; not reloading"
    return
  fi
  netfilter-persistent reload
  # The reload flushes Docker's chains; restarting Docker puts them back (R13).
  systemctl restart docker
}

edge() {
  if [ -f "$ETC/edge.env" ]; then
    log "edge"
    docker compose -p wassal-edge -f "$OPT/edge/compose.yml" up -d --wait
    # `up` leaves a running container alone, so a changed Caddyfile needs a reload.
    docker compose -p wassal-edge -f "$OPT/edge/compose.yml" exec -T caddy caddy reload --config /etc/caddy/Caddyfile
  else
    log "edge skipped: fill the /etc/wassal/*.env files (quickstart step 4), then re-run provision.sh"
  fi
}

operator_peer_is_live() {
  # An operator peer (10.66.0.2-9) with a handshake in the last 10 minutes. No pipeline: with
  # pipefail, `… | grep -q` can fail on SIGPIPE when several peers match.
  local now handshakes
  now="$(date +%s)"
  [ -f "$ETC/wg-peers.tsv" ] || return 1
  handshakes="$(wg show wg0 latest-handshakes)" || return 1
  HANDSHAKES="$handshakes" awk -F'\t' -v now="$now" '
    BEGIN {
      n = split(ENVIRON["HANDSHAKES"], lines, "\n")
      for (i = 1; i <= n; i++) { split(lines[i], field, /[ \t]+/); latest[field[1]] = field[2] }
    }
    NR > 1 && $2 == "operator" && $6 == "" && ($4 in latest) && latest[$4] > now - 600 { found = 1 }
    END { exit !found }
  ' "$ETC/wg-peers.tsv"
}

finalize_ssh() {
  log "finalize: SSH on $WG_ADDRESS only"
  operator_peer_is_live || die "no operator peer has a recent handshake. Connect over WireGuard first, or you would lock yourself out."
  install -m 0644 "$HERE/sshd_config.d/wassal.conf" /etc/ssh/sshd_config.d/wassal.conf
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
  local public_ip="" finalize_now=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --public-ip) public_ip="${2:?--public-ip needs an address}"; shift 2 ;;
      --finalize) finalize_now=1; shift ;;
      *) die "unknown option: $1" ;;
    esac
  done

  check_platform
  install_packages
  console_password
  users_and_dirs
  install_files
  wireguard "$public_ip"
  [ "$finalize_now" -eq 0 ] || finalize_ssh
  # Once finalized, every later run keeps public SSH closed.
  if [ -f "$FINALIZED_MARKER" ]; then firewall 1 "$finalize_now"; else firewall 0 "$finalize_now"; fi
  edge
  log "done"
}

if [ "${1:-}" = --render-firewall ]; then
  render_mode "$@"
else
  main "$@"
fi
