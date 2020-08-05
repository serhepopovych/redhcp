#!/bin/sh

# Requires: ip(8)

# prefsrc: routing table for prefsrc() lookups (see /etc/iproute2/rt_tables)
_prefsrc_table='main'
# prefsrc: unaddressed network interface (ip link add dev lo255 up type dummy)
_prefsrc_unaddr='lo255'

# inetdev: routing table for inetdev() lookups (see /etc/iproute2/rt_tables)
_inetdev_table="${_prefsrc_table}"
# inetdev: unaddressed network interface
_inetdev_unaddr="${_prefsrc_unaddr}"
# inetdev: protocol to associate with route (see /etc/iproute2/rt_protos)
_inetdev_proto='dhcp'

################################################################################

# Usage: prefsrc <ip> [<table>] [<unaddr>]
prefsrc()
{
    local func="${FUNCNAME:-prefsrc}"

    local ip="${1:?missing 1st arg to ${func}() <ip>}"

    local table="${2:-${_prefsrc_table}}"
    local unaddr="${3:-${_prefsrc_unaddr}}"

    set -- $(
        # Do not use "ip route get ..." to support Policy-Based Routing (PBR)
        ip -4 -o route show \
            table "$table" \
            proto kernel \
            scope link \
            dev "$unaddr" \
            match "$ip" \
            #
    ) || return

    while [ $# -gt 0 ]; do
        if [ "$1" = 'src' ]; then
            if [ -n "${2-}" ]; then
                echo "$2"
                return 0
            fi
        fi
        shift
    done

    return 1
}

# Usage: inetdev <ip> [<table>] [<unaddr>] [<proto>]
inetdev()
{
    local func="${FUNCNAME:-inetdev}"

    local ip="${1:?missing 1st arg to ${func}() <ip>}"

    local table="${2:-${_inetdev_table}}"
    local unaddr="${3:-${_inetdev_unaddr}}"
    local proto="${4:-${_inetdev_proto}}"

    local src="${src:-$(prefsrc "$ip")}"

    set -- $(
        ip -4 -o route show \
            table "$table" \
            proto "$proto" \
            ${src:+src "$src"} \
            exact "$ip" \
            #
    ) || return

    while [ $# -gt 0 ]; do
        if [ "$1" = 'dev' ]; then
            if [ -n "${2-}" ]; then
                [ "$2" = "$unaddr" ] || echo "$2"
                return 0
            fi
        fi
        shift
    done

    return 1
}

# Usage: renew ...
renew()
{
    local src="$(prefsrc "$3")"

    # dnsmasq(8) host/service restarted: interface MAY be defined
    local dev="${DNSMASQ_INTERFACE:-$(inetdev "$3")}"
    [ -n "$dev" ] || return 0

    ip -4 route replace "$3/32" dev "$dev" \
        table ${_inetdev_table} \
        proto ${_inetdev_proto} \
        ${src:+src "$src"}  || return
    ip -4 neigh replace "$3" dev "$dev" \
        lladdr "${2#*-}" nud permanent || return
}

# Usage: new ...
new()
{
    # dnsmasq(8) received DHCP Request: interface MUST be defined
    local dev="${DNSMASQ_INTERFACE-}"
    [ -n "$dev" ] || return

    renew "$@"
}

# Usage: release ...
release()
{
    # dnsmasq(8) received DHCP Release: interface MUST be defined
    local dev="${DNSMASQ_INTERFACE-}"
    [ -n "$dev" ] || return

    ip -4 route delete "$3/32" dev "$dev" \
        table ${_inetdev_table} \
        proto ${_inetdev_proto} ||:
    ip -4 neigh delete "$3" dev "$dev" ||:
}

################################################################################

#set -x
set -u
set -e

# See how we're called
case "$1" in
    'add') new     "$@" ;;
    'del') release "$@" ;;
    'old') renew   "$@" ;;
        *) exit 0       ;;
esac
