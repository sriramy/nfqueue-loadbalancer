# nfqueue-loadbalancer

A load-balancer based on the NF_QUEUE iptables target


The `-j NFQUEUE` iptables target directs packets to a user-space
program. The program can analyze the packet, set `fwmark` and place a
"verdict".

<img src="nfqueue.svg" alt="NFQUEUQE packet path" width="75%" />

The `nfqlb lb` program receives packets and uses a configuration in
shared memory to compute a `fwmark`. The `nfqlb` program invoked with
other commands configures the shared memory. This decouples the
traffic handling from configuration. For instance when a real-target
is lost it must be removed from the configuration with;

```
nfqlb deactivate 3
```

Automatic detection and configuration is *not* a part of the
`nfqueue-loadbalancer`. You must do that yourself.

Hashing and fragment handling is done in the same way as for the
Google load-balancer,
[Maglev](https://static.googleusercontent.com/media/research.google.com/en//pubs/archive/44824.pdf).

<img src="lb-tier.svg" alt="load-balancer tier" width="75%" />

The `nfqlb` is scalable, a property inherited from the Maglev
load-balancer. Since the configuration is the same for all nfqlb's it
does not matter which instance that receives a packet.

The forwarding of packets is done by normal Linux routing, the `nfqlb`
just sets a `fwmark`. That let you use any Linux function to route
packets to your targets. Example;

```
ip rule add fwmark 1 table 1
ip route add default via 192.168.1.1 table 1
```

### Build

```
make -C src help
make -C src -j8
```

Linked with `-lmnl -lnetfilter_queue` so you must install those.

## Try it locally

You must have some targets. You can for instance use docker
containers, but anything with an ip-address (not loopback) will do.

Bring up some container targets
```
for n in 1 2 3; do
  name=target$n
  docker run -d --hostname=$name --name=$name --rm alpine:latest nc -nlk -p 8888 -e hostname
  docker inspect $name | jq .[].NetworkSettings.Networks.bridge.IPAddress
done
nc <addr> 8888   # Test connectivity
```

You *can* setup load-balancing in your main network name-space but
it is better to use another container. Build the test container and
enter. You must use `--privileged` for network configuration.

```
./nfqlb.sh build_image
docker run --privileged -it --rm nordixorg/nfqlb:latest /bin/bash
```

Use the `nfqlb.sh lb` script to setup load-balancing and check the
setup. Later you can make your own setup and/or check the `nfqlb.sh`
script.

In the container;
```
PATH=$PATH:/opt/nfqlb/bin
nfqlb.sh lb --vip=10.0.0.0/32 <your container targets here...>
# Check load-balancing;
for n in $(seq 1 20); do echo | nc 10.0.0.0 8888; done
# Check some things
iptables -t nat -S    # OUTPUT for local origin, forwardng not setup
iptables -t mangle -S # The VIP is routed to user-space
nfqlb show            # Shows the Maglev hash lookup
nfqlb deactivate 1    # Deactivates a target. Check load-balancing again!
```

This is a basic example. `nfqlb` can load-balance forwarded traffic
also (of course) and do Direct Server Return (DSR). This will however
require a different setup. But the setup in this example *can* be used
for IPv6. You must setup ipv6 support in `docker` and use ipv6
addresses for the VIP and targets in the `nfqlb.sh lb` command. But
that is left as an exercise for the reader :smiley:

You can also test with [xcluster]() in [ovl/load-balancer]().