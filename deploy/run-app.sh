#!/bin/sh

# Parse options
if [ -n "$MAILNAME" ]
then
    mailname="$MAILNAME"
elif [ "$FQDN" = "1" ]
then
    mailname=`hostname -f`
fi

local_all_subnets=no
local="no"
option_value=""
interfaces=""
relayhost=""
subnets=""
verbose=0

trust_local=1
trust_connected=0
trust_rfc1918=0
trust_connected_rfc1918=1
trust_lla=0

if [ -n "$RELAYHOST" ]
then
		relayhost="$RELAYHOST"
fi

if [ -n "$TRUST" ]
then
    trust_connected_rfc1918=0
    if [ "$TRUST" = "connected" ]
    then
        trust_connected=1
    elif [ "$TRUST" = "rfc1918" ]
    then
        trust_rfc1918=1
    elif [ "$TRUST" = "connected" ]
    then
        trust_connected=1
    elif [ "$TRUST" = "connected-rfc1918" ]
    then
        trust_connected_rfc1918=1
    fi
fi

if [ -n "$TRUST_INTERFACES" ]
then
    interfaces="$TRUST_INTERFACES"
elif [ -n "$TRUST_INTERFACE" ]
then
    interfaces="$TRUST_INTERFACE"
fi

if [ -n "$TRUST_SUBNETS" ]
then
    subnets="$TRUST_SUBNETS"
elif [ -n "$TRUST_SUBNET" ]
then
    subnets="$TRUST_SUBNET"
fi

if [ "$TRUST_LOCAL" = "0" ]
then
    trust_local=0
fi

if [ "$TRUST_CONNECTED" = "1" ]
then
    trust_connected=1
fi

if [ "$TRUST_RFC1918" = "1" ]
then
    trust_rfc1918=1
fi

if [ "$TRUST_CONNECTED_RFC1918" = "1" ]
then
    trust_connected_rfc1918=1
fi

if [ "$TRUST_LLA" = "1" ]
then
    trust_lla=1
fi

while [ $# -gt 0 ]
do
    case "$1" in
        (-h | --help)
            cat <<EOF

Usage: $0 [options]

Default: --trust-local --trust-connected-rfc1918

--mail-name                Mail name to use
--trust-local              Trust addresses on the lo interface
--trust-connected-rfc1918  Trust all locally connected rfc1918 subnets
--trust-connected          Trust all addresses connected (excluding IPv6 local-link addresses)
--trust-rfc1918            Trust all rfc1918 address
--trust-lla                Trust the fe80::/64 IPv6 subnet
--trust [subnet]           Trust the specified subnet (IPv4 and IPv6 supported)
--trust [interface]        Trust all network address on the interface (excluding IPv6 lla)

--skip-trust-*             Use with local, connected-rfc1918, connected, rfc1918, or lla to skip trusting it
--skip-all                 Disable/reset all trusts
--relayhost                Sets the relay host
EOF
            exit 1
            ;;

        (--mail-name)
            if [ -n "$2" ]
            then
                mailname="$2"
            fi
						;;
						
        (--relayhost)
            if [ -n "$2" ]
            then
                relayhost="$2"
            fi
						;;

        (--skip-trust-all)
            trust_local=0
            trust_connected=0
            trust_rfc1918=0
            trust_connected_rfc1918=0
            trust_lla=0
            ;;

        (--skip-trust-local)
            trust_local=0
            ;;

        (--trust-local)
            trust_local=1
            ;;

        (--skip-trust-connected)
            trust_connected=0
            ;;

        (--trust-connected)
            trust_connected=1
            ;;

        (--skip-trust-connected-rfc1918)
            trust_connected_rfc1918=0
            ;;

        (--trust-connected-rfc1918)
            trust_connected_rfc1918=1
            ;;

        (--skip-trust-rfc1918)
            trust_rfc1918=0
            ;;

        (--trust-rfc1918)
            trust_rfc1918=1
            ;;

        (--trust-rfc1918)
            trust_lla=1
            ;;

        (--trust-lla)
            trust_lla=1
            ;;

        (--exclude-ula)
            trust_lla=0
            ;;

        (--trust)
            shift
            if [ "$1" = "" ]
            then
                echo "$0: error - expected paramter for --trust"
                exit 1
            fi
            trusted="${trusted}$1"
            ;;

        (-*)
            if [ "$option_value" = "" ]
            then
                echo "$0: error - unrecognized option $1" 1>&2;
                exit 1
            fi
            ;;

        esac
    shift
done

trusted4=""
trusted6=""

get_v4_network() {
    xargs --no-run-if-empty sipcalc | awk '/Network address/ { printf "%s/", $4 } /Network mask \(bits\)/ { print $5 }'
}
get_v6_network() {
    xargs --no-run-if-empty sipcalc | awk '/Subnet prefix/ { print $5 }'
}
get_compact_v6_network() {
    get_v6_network | xargs --no-run-if-empty xargs sipcalc | awk '/Compressed address/ { printf "%s/", $4 } /Prefix length/ { print $4 }'
}

exclude_local() {
    awk '!/inet 127.0.0.1/ && !/inet6 ::1/'
}
exclude_rfc1918() {
    rfc1918_addresses='10(\.(2[0-9]{2}|1?[0-9]{1,2})){3}'
    rfc1918_addresses="$rfc1918_addresses|"'192\.168\.[12]?[0-9]{1,2}'
    rfc1918_addresses="$rfc1918_addresses|"'172\.(1[6-9]|2[0-9]|31)\.(25[1-4]|2[1-4][0-9]|1[0-9]{2}|[1-9]?[0-9])'
    awk "!/inet ($rfc1918_addresses)/"
}
exclude_lla() {
    awk '!/inet6 fe80::/'
}

for address in $trusted;
do
    # Check to see if the address specified is an interface instead
    # sipcalc doesn't seem to return IPv6 information, so first use it
    # to detect whether the input is an interface
    sip_calc=`sipcalc -u $address`
    is_interface=`echo $sip_calc | grep -c int-`

    if [ $is_interface -eq 0 ]
    then
        # $address is an ip address (v4 or v6)
        is_ipv6=`echo "$sip_calc" | grep -c ipv6`
        if [ $is_ipv6 -eq 0 ]
        then
           subnet=`sipcalc $address | get_v4_network`
           trusted4="${trusted4}$subnet "
        else
           subnet=`sipcalc $address | get_v6_network`
           trusted6="${trusted6}$subnet "
        fi
    else
        # $address is an interface
        if [ $trust_rfc1918 -eq 1 ]
        then
            addresses4=`ip addr show dev $address | exclude_rfc1918 | awk '/inet / { print $2 }' | get_v4_network`
        else
            addresses4=`ip addr show dev $address | awk '/inet / { print $2 }' | get_v4_network`
        fi

        addresses6=`ip addr show dev $address | exclude_lla | awk '/inet6/ { print $2 }' | get_compact_v6_network`

        trusted4="${trusted4}$addresses4 "
        trusted6="${trusted6}$addresses6 "
    fi
done

if [ ! "$option_value" = "" ]
then
    echo "$0: error - missing value for --$option_value"
    exit 1
fi

include_rfc1918() {
    rfc1918_addresses='10(\.(2[0-9]{2}|1?[0-9]{1,2})){3}'
    rfc1918_addresses="$rfc1918_addresses|"'192\.168\.[12]?[0-9]{1,2}'
    rfc1918_addresses="$rfc1918_addresses|"'172\.(1[6-9]|2[0-9]|31)\.(25[1-4]|2[1-4][0-9]|1[0-9]{2}|[1-9]?[0-9])'
    awk "/inet ($rfc1918_addresses)/"
}

if [ $trust_local -eq 1 ]
then
    local4_addresses=`ip addr show dev lo | awk '/inet /  {print $2 }' | get_v4_network`
    local6_addresses=`ip addr show dev lo | awk '/inet6 / {print $2 }' | get_compact_v6_network`
    trusted4="$local4_addresses "
    trusted6="$local6_addresses "
fi

if [ $trust_rfc1918 -eq 1 ]
then
    trusted4="${trusted4}10.0.0.0/8 172.16.0.0/12 192.168.0.0/24 "
fi

if [ $trust_lla -eq 1 ]
then
    trusted6="${trusted6}fe80::/64 "
fi

if [ $trust_connected -eq 1 ]
then
    if [ $trust_rfc1918 -eq 1 ]
    then
        connected4=`ip addr show | exclude_local | exclude_rfc1918 | awk '/inet / { print $2 }' | get_v4_network`
    else
        connected4=`ip addr show | exclude_local | awk '/inet / { print $2 }' | get_v4_network`
    fi
    connected6=`ip addr show | exclude_lla | awk '/inet6/ && !/inet6 ::1/ { print $2}' | get_compact_v6_network`
    trusted4="${trusted4}${connected4}"
    trusted6="${trusted6}${connected6} "
fi

if [ $trust_connected_rfc1918 -eq 1 -a $trust_rfc1918 -eq 0 -a $trust_connected -eq 0 ]
then
    connected1918=`ip addr show | include_rfc1918 | awk '/inet / { print $2 }' | get_v4_network`
    trusted4="${trusted4}${connected1918} "
fi

# Build mynetworks
mynetworks=""
for subnet in $trusted4
do
    mynetworks="${mynetworks}${subnet} "
    network=`echo $subnet | cut -d/ -f1`
    subnet_size=`echo $subnet | cut -d/ -f2`
    ipv6_size=`expr 96 + $subnet_size`
    trusted6="${trusted6}::ffff:$network/$ipv6_size "
done

for subnet in $trusted6
do
    network=`echo $subnet | cut -d/ -f1`
    subnet_size=`echo $subnet | cut -d/ -f2`
    mynetworks="${mynetworks}[$network]/$subnet_size "
done

# Generate an automatically generated private key if not generated
if [ ! -f /etc/ssl/certs/ssl-cert-snakeoil.pem ]
then
    DEBIAN_FRONTEND=noninteractive make-ssl-cert generate-default-snakeoil
fi

# Update the hostname
if [ -n "$mailname" ]
then
    sed -i "s#myhostname =.*#myhostname = $mailname#" /etc/postfix/main.cf
fi

seded_mynetworks=`echo $MYNETWORK | sed 's/#/\\#/g'`
sed -i -r "s#mynetworks = (.*)#mynetworks = $mynetworks#g" /etc/postfix/main.cf

sed -i -r "s#relayhost = (.*)#relayhost = $relayhost#g" /etc/postfix/main.cf

# Utilize the init script to configure the chroot (if needed)
/etc/init.d/postfix start > /dev/null
/etc/init.d/postfix stop > /dev/null

# The init script doesn't always stop
# Ask postfix to stop itself as well, in case there's an issue
postfix stop > /dev/null 2>/dev/null

trap_hup_signal() {
    echo "Reloading (from SIGHUP)"
    postfix reload
}

trap_term_signal() {
    echo "Stopping (from SIGTERM)"
    postfix stop
    exit 0
}

# Postfix conveniently, doesn't handle TERM (sent by docker stop)
# Trap that signal and stop postfix if we recieve it
trap "trap_hup_signal" HUP
trap "trap_term_signal" TERM

/usr/lib/postfix/master -c /etc/postfix -d &
pid=$!

# Loop "wait" until the postfix master exits
while wait $pid; test $? -gt 128
do
    kill -0 $pid 2> /dev/null || break;
done
