#pragma once
/*
  SPDX-License-Identifier: Apache-2.0
  Copyright (c) 2021 Nordix Foundation
*/

#include <conntrack.h>

#define IN_BOUNDS(p,o,e) (((void const*)p + o) < (void const*)(e))

int ipv6IsExtensionHeader(unsigned htype);

/*
  Get the key used for hashing.

  Returns;
  <0 - Failed
  0  - Normal packet. Ports are valid
  1  - First fragment. Ports are valid, *fragid is returned
  2  - Sub-sequent fragment. Id is valid
  4  - UDP packet, dport matching the "udpEncap" port. The proto is set
       to sctp and the ports are taken from the (inner) sctp header
  8  - ICMP packet with inner header (e.g packet too big). The addresses
       and ports are taken from the inner packet and reversed.
  16 - ICMP without inner header, e.g "ping". Id may be valid.
  32 - Only addresses are valid
 */
int getHashKey(
	struct ctKey* key, unsigned udpEncap, uint64_t* fragid,
	unsigned proto, void const* data, unsigned len);

// Hash on addresses only
unsigned hashKeyAddresses(struct ctKey* key);

// The default hash function.
// Hashes on the entire key, unless proto=sctp in which case we hash on
// ports only.
unsigned hashKey(struct ctKey* key);
