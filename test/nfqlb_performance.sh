#! /bin/sh
##
## nfqlb_performance.sh --
##
##   Performance test scriptlets for;
##   https://github.com/Nordix/nfqueue-loadbalancer/
##

prg=$(basename $0)
dir=$(dirname $0); dir=$(readlink -f $dir)
tmp=/tmp/${prg}_$$
me=$dir/$prg
nfqlbsh=$(readlink -f $dir/../nfqlb.sh)

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

## Low-level Commands;

##   start_iperf_server
##     In the current netns. Both tcp6 and udp6
cmd_start_iperf_server() {
	if netstat -putln 2> /dev/null | grep 5001 | grep -q tcp6; then
		log "Iperf tcp6 already started"
	else
		iperf --server --daemon --ipv6_domain || die
	fi
	if netstat -putln 2> /dev/null | grep 5001 | grep -q udp6; then
		log "Iperf udp6 already started"
	else
		iperf --server --daemon --ipv6_domain --udp || die
	fi
}

##   start_test_image
##     Re-start the test container. Re-build if specified.
cmd_start_test_image() {
	docker stop -t 1 nfqlb > /dev/null 2>&1
	docker run --privileged --name=nfqlb -d --rm registry.nordix.org/cloud-native/nfqlb:latest
}

cmd_docker_address() {
	docker inspect bridge | jq -r .[].IPAM.Config[].Gateway | grep -v :
}

##   start_lb [--adr=] [--vip=]
##     Start nfqlb in the test container
cmd_start_lb() {
	test -n "$__adr" || __adr=$(cmd_docker_address)
	test -n "$__vip" || __vip=10.0.0.0/32
	docker exec --detach nfqlb /opt/nfqlb/bin/nfqlb.sh lb --queue=$__queue --vip=$__vip $__adr
}

##   iperf <params...>
cmd_iperf() {
	docker exec -it nfqlb iperf $@
}

##   qstats
cmd_qstats() {
	local sfile=/proc/net/netfilter/nfnetlink_queue
	echo "  Q       port inq cp   rng  Qdrop  Udrop      Seq"
	docker exec nfqlb cat $sfile | format_stats
}
format_stats() {
	local line s
	while read line; do
		s=$(echo $line | tr -s ' ' :)
		# Q port(pid) inQ cpmode range Qdroped usrDropped lastSeq 1
		local Q=$(echo $s | cut -d: -f1)
		local port=$(echo $s | cut -d: -f2)
		local inQ=$(echo $s | cut -d: -f3)
		local cp=$(echo $s | cut -d: -f4)
		local rng=$(echo $s | cut -d: -f5)
		local Qdrop=$(echo $s | cut -d: -f6)
		local Udrop=$(echo $s | cut -d: -f7)
		local seq=$(echo $s | cut -d: -f8)
		printf "%3u %10u %3u  %u %5u %6u %6u %8u\n"\
			$Q $port $inQ $cp $rng $Qdrop $Udrop $seq
	done
}

# CPU usage;
# https://stackoverflow.com/questions/23367857/accurate-calculation-of-cpu-usage-given-in-percentage-in-linux

cmd_cpu_sample() {
	local s=$(head -1 /proc/stat | tr -s ' ' :)
	local user=$(echo $s | cut -d: -f2)
	local nice=$(echo $s | cut -d: -f3)
	local system=$(echo $s | cut -d: -f4)
	local idle=$(echo $s | cut -d: -f5)
	local iowait=$(echo $s | cut -d: -f6)
	local irq=$(echo $s | cut -d: -f7)
	local softirq=$(echo $s | cut -d: -f8)
	local steal=$(echo $s | cut -d: -f9)
	local guest=$(echo $s | cut -d: -f10)
	local guest_nice=$(echo $s | cut -d: -f11)
	echo "$((user + nice + system + irq + softirq + steal)):$((idle + iowait))"
}
cmd_cpu_usage_since() {
	local s=$(cmd_cpu_sample)  # (asap!)
	test -n "$1" || die "No previous sample"
	local pbusy=$(echo $1 | cut -d: -f1)
	local pidle=$(echo $1 | cut -d: -f2)
	local ptotal=$((pbusy + pidle))
	local busy=$(echo $s | cut -d: -f1)
	local idle=$(echo $s | cut -d: -f2)
	local total=$((busy + idle))

	local totald=$((total - ptotal))
	local idled=$((idle - pidle))
	local pecent10=$(( 1000 * (totald - idled) / totald))
	echo "$((pecent10/10)).$((pecent10%10))%"
}

##
## Test Commands;

##   test [--rebuild] [--no-stop] [iperf options...]
cmd_test() {
	local s
	local i=0
	i=$((i+1)); echo "$i. Start iperf servers"
	cmd_start_iperf_server > /dev/null 2>&1
	if test "$__rebuild" = "yes"; then
		i=$((i+1)); echo "$i. Rebuild the test container"
		$nfqlbsh build_alpine_image > /dev/null || die
	fi
	i=$((i+1)); echo "$i. Start the test container"
	cmd_start_test_image > /dev/null
	i=$((i+1)); echo "$i. Start LB"
	cmd_start_lb
	i=$((i+1)); echo "$i. Iperf direct (-c $(cmd_docker_address) $@)"
	s=$(cmd_cpu_sample)
	cmd_iperf -c $(cmd_docker_address) $@
	i=$((i+1)); echo "$i. CPU usage $(cmd_cpu_usage_since $s)"
	i=$((i+1)); echo "$i. Nfnetlink_queue stats"
	cmd_qstats
	i=$((i+1)); echo "$i. Re-start iperf servers"
	cmd_start_iperf_server > /dev/null 2>&1
	local vip=$(echo $__vip | cut -d/ -f1)
	i=$((i+1)); echo "$i. Iperf VIP (-c $vip $@)"
	cmd_iperf -c $vip $@
	i=$((i+1)); echo "$i. CPU usage $(cmd_cpu_usage_since $s)"
	i=$((i+1)); echo "$i. Nfnetlink_queue stats"
	cmd_qstats
	if test "$__fragstats" = "yes"; then
		i=$((i+1)); echo "$i. Get frag stats"
		docker exec nfqlb /opt/nfqlb/bin/nfqlb stats
	fi
	if test "$__no_stop" != "yes"; then
		echo "$i. Stop the container"
		docker stop -t 1 nfqlb > /dev/null 2>&1
	fi
}
#   test_report [iperf options...]
cmd_test_report() {
	echo "# Nfqlb test report - iperf $@"
	echo '```'
	cmd_test $@
	echo '```'
}


##

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