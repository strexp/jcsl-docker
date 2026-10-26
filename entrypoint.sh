#!/bin/sh
#
# Configure and run the Oracle Java Card simulator (jcsl).
#
# All key/PIN values are hex-encoded bytes, as accepted by Configurator.jar.
# For example, the PIN 313233343536 is the ASCII string "123456".

set -eu

log() { printf 'jcsl-docker: %s\n' "$*" >&2; }
die() { log "error: $*"; exit 1; }

[ "${JCSL_ACCEPT_LICENSE:-}" = "yes" ] \
    || die "accept the Oracle Java Card Development Kit license by setting JCSL_ACCEPT_LICENSE=yes"

JCSL_KVN=${JCSL_KVN:-01}
JCSL_ENC_KEY=${JCSL_ENC_KEY:-404142434445464748494A4B4C4D4E4F}
JCSL_MAC_KEY=${JCSL_MAC_KEY:-404142434445464748494A4B4C4D4E4F}
JCSL_DEK_KEY=${JCSL_DEK_KEY:-404142434445464748494A4B4C4D4E4F}
JCSL_GLOBAL_PIN=${JCSL_GLOBAL_PIN:-000000000000}
JCSL_PIN_TRIES=${JCSL_PIN_TRIES:-03}
JCSL_BIND_IP=${JCSL_BIND_IP:-0.0.0.0}
JCSL_PORT=${JCSL_PORT:-9025}
JCSL_INTERNAL_PORT=${JCSL_INTERNAL_PORT:-}

is_hex() {
    case $1 in
        '' | *[!0-9A-Fa-f]*) return 1 ;;
    esac
    return 0
}

check_key() {
    name=$1
    value=$2
    is_hex "$value" || die "$name must contain only hexadecimal digits"
    case ${#value} in
        32 | 48 | 64) ;;
        *) die "$name must be 16, 24 or 32 bytes of hex (32, 48 or 64 hex digits)" ;;
    esac
}

check_key JCSL_ENC_KEY "$JCSL_ENC_KEY"
check_key JCSL_MAC_KEY "$JCSL_MAC_KEY"
check_key JCSL_DEK_KEY "$JCSL_DEK_KEY"

if [ ${#JCSL_ENC_KEY} -ne ${#JCSL_MAC_KEY} ] \
    || [ ${#JCSL_MAC_KEY} -ne ${#JCSL_DEK_KEY} ]; then
    die "JCSL_ENC_KEY, JCSL_MAC_KEY and JCSL_DEK_KEY must have the same length"
fi

if ! is_hex "$JCSL_KVN" || [ ${#JCSL_KVN} -ne 2 ]; then
    die "JCSL_KVN must be 1 byte of hex (2 hex digits)"
fi

if ! is_hex "$JCSL_GLOBAL_PIN"; then
    die "JCSL_GLOBAL_PIN must contain only hexadecimal digits"
fi
pin_len=${#JCSL_GLOBAL_PIN}
if [ $((pin_len % 2)) -ne 0 ] || [ "$pin_len" -lt 6 ] || [ "$pin_len" -gt 32 ]; then
    die "JCSL_GLOBAL_PIN must be 3..16 bytes of hex (6..32 hex digits)"
fi

if ! is_hex "$JCSL_PIN_TRIES" || [ ${#JCSL_PIN_TRIES} -ne 2 ]; then
    die "JCSL_PIN_TRIES must be 1 byte of hex (2 hex digits)"
fi

case $JCSL_PORT in
    '' | *[!0-9]*) die "JCSL_PORT must be a TCP port number (1..65535)" ;;
esac
if [ "$JCSL_PORT" -lt 1 ] || [ "$JCSL_PORT" -gt 65535 ]; then
    die "JCSL_PORT must be a TCP port number (1..65535)"
fi
[ -n "$JCSL_BIND_IP" ] || die "JCSL_BIND_IP must not be empty"

if [ "$JCSL_ENC_KEY" = "404142434445464748494A4B4C4D4E4F" ] \
    && [ "$JCSL_MAC_KEY" = "404142434445464748494A4B4C4D4E4F" ] \
    && [ "$JCSL_DEK_KEY" = "404142434445464748494A4B4C4D4E4F" ]; then
    log "warning: using the built-in test SCP03 keyset"
fi

# jcsl always binds 0.0.0.0 and only accepts a port, so it listens on a
# private port and socat provides the requested bind address/port.
port_in_use() {
    port_hex=$(printf '%04X' "$1")
    set -- /proc/net/tcp
    [ -r /proc/net/tcp6 ] && set -- "$@" /proc/net/tcp6
    awk -v port="$port_hex" \
        '$4 == "0A" && $2 ~ (":" port "$") { found = 1 } END { exit !found }' \
        "$@" 2>/dev/null
}

if [ -n "$JCSL_INTERNAL_PORT" ]; then
    case $JCSL_INTERNAL_PORT in
        '' | *[!0-9]*) die "JCSL_INTERNAL_PORT must be a TCP port number (1..65535)" ;;
    esac
    if [ "$JCSL_INTERNAL_PORT" -lt 1 ] || [ "$JCSL_INTERNAL_PORT" -gt 65535 ]; then
        die "JCSL_INTERNAL_PORT must be a TCP port number (1..65535)"
    fi
    [ "$JCSL_INTERNAL_PORT" -ne "$JCSL_PORT" ] \
        || die "JCSL_INTERNAL_PORT must differ from JCSL_PORT"
    port_in_use "$JCSL_INTERNAL_PORT" \
        && die "JCSL_INTERNAL_PORT $JCSL_INTERNAL_PORT is already in use"
else
    internal_port=19025
    while port_in_use "$internal_port" || [ "$internal_port" -eq "$JCSL_PORT" ]; do
        internal_port=$((internal_port + 1))
        [ "$internal_port" -le 65535 ] || die "no free internal port available"
    done
    JCSL_INTERNAL_PORT=$internal_port
fi
internal_port=$JCSL_INTERNAL_PORT

sim_bin=/var/lib/jcsl/jcsl
cp /opt/jcsl/runtime/bin/jcsl "$sim_bin" \
    || die "cannot write $sim_bin (is /var/lib/jcsl writable?)"
chmod 0755 "$sim_bin"

log "configuring SCP03 keyset (KVN $JCSL_KVN)"
java -jar /opt/jcsl/Configurator.jar \
    -binary "$sim_bin" -force \
    -SCP-keyset "$JCSL_KVN" "$JCSL_ENC_KEY" "$JCSL_MAC_KEY" "$JCSL_DEK_KEY" \
    -global-pin "$JCSL_GLOBAL_PIN" "$JCSL_PIN_TRIES" \
    || die "jcsl configuration failed"

export LD_LIBRARY_PATH=/opt/jcsl/runtime/bin
export OPENSSL_MODULES=/opt/jcsl/runtime/bin

"$sim_bin" -p="$internal_port" &
sim_pid=$!

# Wait until jcsl itself owns a listening socket on the internal port.
sim_listening() {
    for fd in /proc/"$sim_pid"/fd/*; do
        target=$(readlink "$fd" 2>/dev/null) || continue
        case $target in
            socket:\[*\]) ;;
            *) continue ;;
        esac
        inode=${target#socket:[}
        inode=${inode%]}
        if awk -v inode="$inode" -v port="$port_hex" \
            '$10 == inode && $4 == "0A" && $2 ~ (":" port "$") { found = 1 } END { exit !found }' \
            /proc/net/tcp 2>/dev/null; then
            return 0
        fi
    done
    return 1
}

port_hex=$(printf '%04X' "$internal_port")
ready=0
i=0
while [ "$i" -lt 150 ]; do
    if ! kill -0 "$sim_pid" 2>/dev/null; then
        die "simulator exited during startup"
    fi
    if sim_listening; then
        ready=1
        break
    fi
    sleep 0.2
    i=$((i + 1))
done
[ "$ready" -eq 1 ] || die "simulator did not start listening on port $internal_port"

case $JCSL_BIND_IP in
    *:*) listen_spec="TCP6-LISTEN:$JCSL_PORT,bind=[$JCSL_BIND_IP],reuseaddr,fork" ;;
    *) listen_spec="TCP-LISTEN:$JCSL_PORT,bind=$JCSL_BIND_IP,reuseaddr,fork" ;;
esac
socat "$listen_spec" "TCP:127.0.0.1:$internal_port" &
socat_pid=$!

log "simulator listening on $JCSL_BIND_IP:$JCSL_PORT (internal jcsl port $internal_port)"

shutdown() {
    _rc=$1
    trap - TERM INT
    kill -TERM "$sim_pid" "$socat_pid" 2>/dev/null || true
    i=0
    while [ "$i" -lt 50 ]; do
        if ! kill -0 "$sim_pid" 2>/dev/null && ! kill -0 "$socat_pid" 2>/dev/null; then
            break
        fi
        sleep 0.1
        i=$((i + 1))
    done
    kill -KILL "$sim_pid" "$socat_pid" 2>/dev/null || true
    wait 2>/dev/null || true
    exit "$_rc"
}
trap 'shutdown 143' TERM
trap 'shutdown 130' INT

while kill -0 "$sim_pid" 2>/dev/null && kill -0 "$socat_pid" 2>/dev/null; do
    sleep 1
done

status=0
if ! kill -0 "$sim_pid" 2>/dev/null; then
    wait "$sim_pid" || status=$?
else
    wait "$socat_pid" || status=$?
fi

log "simulator or socat exited (status $status), stopping"
shutdown "$status"
