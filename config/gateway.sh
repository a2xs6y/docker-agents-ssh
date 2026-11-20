#!/bin/bash
set -euo pipefail

umask 077
key_dir=$(mktemp -d)
install -m 600 /run/keys/exit "$key_dir/exit-key"

cat > "$key_dir/tunnel.conf" <<CONFIG
Host exit
    HostName ${SSH_HOST}
    User ${SSH_USER}
    Port ${SSH_PORT}
    IdentityFile ${key_dir}/exit-key
CONFIG

if [[ -n ${SSH_JUMP_HOST} ]]; then
  install -m 600 /run/keys/jump "$key_dir/jump-key"
  cat >> "$key_dir/tunnel.conf" <<CONFIG
    ProxyJump jump
Host jump
    HostName ${SSH_JUMP_HOST}
    User ${SSH_JUMP_USER:-$SSH_USER}
    Port ${SSH_JUMP_PORT}
    IdentityFile ${key_dir}/jump-key
CONFIG
fi

cat >> "$key_dir/tunnel.conf" <<'CONFIG'
Host *
    IdentitiesOnly yes
    BatchMode yes
    ForwardAgent no
    StrictHostKeyChecking yes
    UserKnownHostsFile /run/keys/known_hosts
    GlobalKnownHostsFile none
    UpdateHostKeys no
    ConnectTimeout 10
    ServerAliveInterval 15
    ServerAliveCountMax 3
    ExitOnForwardFailure yes
CONFIG

pids=()
cleanup() {
  kill "${pids[@]}" 2>/dev/null || true
  wait || true
  rm -rf -- "$key_dir"
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

ssh -F "$key_dir/tunnel.conf" -N -D 127.0.0.1:1080 exit &
pids+=("$!")
privoxy --no-daemon /opt/gateway/privoxy.conf &
pids+=("$!")
wait -n "${pids[@]}"
