#! /bin/sh
##
## nfqlb.sh --
##
##   Help script for the xcluster ovl/nfqlb.
##
## Commands;
##

prg=$(basename $0)
dir=$(dirname $0); dir=$(readlink -f $dir)
me=$dir/$prg
tmp=/tmp/${prg}_$$

die() {
	echo "ERROR: $*" >&2
	rm -rf $tmp
	exit 1
}
help() {
	grep '^##' $0 | cut -c3-
	rm -rf $tmp
	exit 0
}
test -n "$1" || help
echo "$1" | grep -qi "^help\|-h" && help

log() {
	echo "$prg: $*" >&2
}
dbg() {
	test -n "$__verbose" && echo "$prg: $*" >&2
}

##  env
##    Print environment.
##
cmd_env() {

	if test "$cmd" = "env"; then
		set | grep -E '^(__.*)='
		retrun 0
	fi

	test -n "$XCLUSTER" || die 'Not set [$XCLUSTER]'
	test -x "$XCLUSTER" || die "Not executable [$XCLUSTER]"
	eval $($XCLUSTER env)
}

##   test --list
##   test [--xterm] [test...] > logfile
##     Exec tests
##
##   Tests;
cmd_test() {
	if test "$__list" = "yes"; then
		grep '^test_' $me | cut -d'(' -f1 | sed -e 's,test_,,'
		return 0
	fi

	cmd_env
	start=starts
	test "$__xterm" = "yes" && start=start
	rm -f $XCLUSTER_TMP/cdrom.iso

	if test -n "$1"; then
		for t in $@; do
			test_$t
		done
	else
		unset __fragrev
		test_basic || tdie

		test_udp || tdie
		__vip=10.0.0.0:5001
		test_udp || tdie

		unset __vip
		__fragrev=yes
		test_udp || tdie
		__vip=10.0.0.0:5001
		test_udp || tdie

		export xcluster_LBOPT="--queue=0:3 --reassembler=1000"
		unset __vip
		unset __fragrev
		test_udp || tdie
		__vip=10.0.0.0:5001
		test_udp || tdie

		
		unset __fragrev
		unset __vip
		test_mtu || tdie

		unset __nrouters
		test_sctp || tdie
	fi		

	now=$(date +%s)
	tlog "Xcluster test ended. Total time $((now-begin)) sec"

}

test_flows() {
	export xcluster_FLOW=yes
	test_basic_flows
	test_mtu_flow
	test_port64
	test_sctp_flow
	export xcluster_LBOPT=--promiscuous_ping
	test_tcp_udp_flow
}

test_start_empty() {
	export __image=$XCLUSTER_HOME/hd.img
	echo "$XOVLS" | grep -q private-reg && unset XOVLS
	export xcluster_DISABLE_MASQUERADE=yes
	export TOPOLOGY=evil_tester
	export xcluster_TOPOLOGY=$TOPOLOGY
	. $($XCLUSTER ovld network-topology)/$TOPOLOGY/Envsettings
	local OVLS
	test "$__fragrev" = "yes" && OVLS=tap-scrambler
	xcluster_start network-topology iptools nfqlb $OVLS $@
	test "$__fragrev" = "yes" && otc 222 fragrev
}
##     [--fragrev] start
test_start() {
	test_start_empty $@
	if test "$xcluster_FLOW" != "yes"; then
		otcr nfqueue_activate_all
	else
		otcr nfqueue_activate_default_flow
	fi
}
##     [--vip=] start_hw_setup
test_start_hw_setup() {
	export __image=$XCLUSTER_HOME/hd.img
	echo "$XOVLS" | grep -q private-reg && unset XOVLS
	export xcluster_HW_SETUP=yes
	export xcluster_PREFIX=fd01:
	test -n "$__vip" || __vip=10.0.0.0
	export xcluster_vip=$__vip
	export __nvm=1
	export __nrouters=1
	export __ntesters=0
	export __smp201=4
	xcluster_start network-topology iptools udp-test nfqlb
	otc 201 hw_netns
	otc 1 "hw_server --vip=$__vip"
}

##     start_dual_path
test_start_dual_path() {
	export TOPOLOGY=dual-path
	export xcluster_TOPOLOGY=$TOPOLOGY
	export __ntesters=1
	export __image=$XCLUSTER_HOME/hd.img
	echo "$XOVLS" | grep -q private-reg && unset XOVLS
	. $($XCLUSTER ovld network-topology)/$TOPOLOGY/Envsettings
	xcluster_start network-topology iptools nfqlb $@

	otc 201 nfqueue_activate_all
	otc 202 nfqueue_activate_all
	otc 203 "vip_route 192.168.3.201"
	otc 204 "vip_route 192.168.5.202"
	otc 221 "default_route 1000::1:192.168.6.204"
	otcw "default_route 1000::1:192.168.4.202"
}

##     basic
test_basic() {
	tlog "=== nfqlb: Basic test"
	test_start
	otc 221 "ping --vip=1000::"
	otc 221 "ping --vip=10.0.0.0"
	otc 221 "mconnect_udp --vip=10.0.0.0:5001"
	otc 221 "mconnect --vip=[1000::]:5001"
	otc 221 "mconnect --vip=10.0.0.0:5001"
	otc 221 "mconnect_udp --vip=[1000::]:5001"
	otc 221 "mconnect_udp --vip=10.0.0.0:5001"
	xcluster_stop
}
##     basic_flows
test_basic_flows() {
	tlog "=== nfqlb: Basic flow test"
	export xcluster_FLOW=yes
	test_start_empty
	otcr nfqueue_flow_vms
	otc 221 mconnect_vmflow
	otc 221 "mconnect_vmflow udp"
	xcluster_stop
}

##	   [--verbose] udp
test_udp() {
	test -n "$__vip" || __vip="[1000::]:5003"
	tlog "=== nfqlb: UDP test, vip=$__vip, fragrev=$__fragrev"
	test_start
	#export xcluster_LBOPT="--ft_size=500 --ft_buckets=500 --ft_frag=100"
	#__copt="-monitor -psize 2048 -rate 1000 -nconn 40 -timeout 20s"
	otc 221 "udp --copt='$__copt' --vip=$__vip --verbose=$__verbose"
	test "$__verbose" = "yes" && otcr nfqlb_stats
	xcluster_stop
}
##     mtu
test_mtu() {
	tlog "=== nfqlb: MTU test"
	test_start mtu
	otc 221 "http http://10.0.0.0 -s -m2 --interface 20.0.0.1"
	otc 221 "http http://[1000::] -s -m2 --interface $PREFIX:20.0.0.1"
	otcprog=mtu_test
	otc 222 squeeze_chain
	unset otcprog
	otc 221 "http http://10.0.0.0 -s -m2 --interface 20.0.0.1"
	sleep 1				# ICMP6 not sent immadiately! Probably some DAD problem.
	otc 221 "http http://[1000::] -s -m2 --interface $PREFIX:20.0.0.1"
	xcluster_stop
}

##     mtu_flow
test_mtu_flow() {
	tlog "=== nfqlb: MTU test with flows"
	export xcluster_FLOW=yes
	test_start_empty mtu
	otcr nfqueue_flow_vms
	otc 221 "http http://10.0.0.0 -s -m2 --interface 20.0.0.1"
	otc 221 "http http://[1000::] -s -m2 --interface $PREFIX:20.0.0.1"
	otcprog=mtu_test
	otc 222 squeeze_chain
	unset otcprog
	otc 221 "http http://10.0.0.0 -s -m2 --interface 20.0.0.1"
	sleep 1				# ICMP6 not sent immadiately! Probably some DAD problem.
	otc 221 "http http://[1000::] -s -m2 --interface $PREFIX:20.0.0.1"
	xcluster_stop
}

##     sctp
test_sctp() {
	tlog "=== nfqlb: SCTP test"
	test_start_dual_path

	otc 221 "sctpt_start -- --addr=10.0.0.0,1000:: --clients=16 --rate=16 --duration=30"
	tlog "Sleep 10..."
	sleep 10
	otc 203 "iptables -A FORWARD -p sctp -j DROP"
	tlog "Sleep 15..."
	sleep 15
	otc 203 "iptables -D FORWARD 1"
	tlog "Sleep 5..."
	sleep 5

	otc 221 "sctpt_wait --timeout=20"
	otc 221 sctpt_stats
	otcw nsctpconn
	
	xcluster_stop
}
##     port64
test_port64() {
	tlog "=== nfqlb: Create a flow with a 64 ranges dports"
	export xcluster_FLOW=yes
	test_start
	otcr range64
	xcluster_stop
}
##     sctp_flow
test_sctp_flow() {
	tlog "=== nfqlb: SCTP test with flows"
	export xcluster_FLOW=yes
	test_start_empty
	otcr udpencap_flow
	otcr nfqueue_activate_all
	otc 221 sctp_ctraffic
	test "$__no_encap" = "yes" && return 0

	otcw sctp_server_udpencap
	otc 221 "sctp_ctraffic --udpencap=9899"
	xcluster_stop
}

##    tcp_udp_flow
test_tcp_udp_flow() {
	tlog "=== nfqlb: Flow with tcp,udp match"
	export xcluster_FLOW=yes
	test_start
	otcr tcp_udp_flow
	otc 221 "mconnect_udp --vip=10.0.0.0:5001"
	otc 221 "mconnect --vip=[1000::]:5001"
	otc 221 "mconnect --vip=10.0.0.0:5001"
	otc 221 "mconnect_udp --vip=[1000::]:5001"
	otc 221 "mconnect_udp --vip=10.0.0.0:5001"
	if echo $xcluster_LBOPT | grep -q promiscuous_ping; then
		otc 221 "ping --vip=1000::"
		otc 221 "ping --vip=10.0.0.0"
	else
		tlog "Not promiscuous_ping. Ping tests skipped"
	fi
	xcluster_stop
}

##

#  rexec [--expand=x|y] <cmd>
#	 Exec command on routers in xterms.
cmd_rexec() {
	test -n "$1" || die "No cmd"
	test -n "$__nrouters" || __nrouters=2
	local rsh='ssh -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no'
	local i geometry
	for i in $(seq 1 $__nrouters); do
		if test "$__expand" = "x"; then
			geometry=$($XCLUSTER geometry $i 1)
		else
			geometry=$($XCLUSTER geometry 1 $i)
		fi
		XXTERM=XCLUSTER xterm -T "Router $i $1" -bg '#400' $geometry -e \
			$rsh root@192.168.0.$((200 + i)) -- $1 &
	done
}


. $($XCLUSTER ovld test)/default/usr/lib/xctest
indent=''

test -n "$PREFIX" || PREFIX=1000::1
test -n "$XADDR" || XADDR=20.0.0.0

# Get the command
cmd=$1
shift
grep -q "^cmd_$cmd()" $0 $hook || die "Invalid command [$cmd]"

while echo "$1" | grep -q '^--'; do
	if echo $1 | grep -q =; then
		o=$(echo "$1" | cut -d= -f1 | sed -e 's,-,_,g')
		v=$(echo "$1" | cut -d= -f2-)
		eval "$o=\"$v\""
	else
		o=$(echo "$1" | sed -e 's,-,_,g')
		eval "$o=yes"
	fi
	shift
done
unset o v
long_opts=`set | grep '^__' | cut -d= -f1`

# Execute command
trap "die Interrupted" INT TERM
cmd_$cmd "$@"
status=$?
rm -rf $tmp
exit $status
