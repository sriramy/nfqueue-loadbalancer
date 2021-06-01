#pragma once
#include <maglev.h>
#include <conntrack.h>

struct SharedData {
        int ownFwmark;
        int fwOffset;
        struct MagData magd;
};

extern char const* const defaultTargetShm;

typedef int (*packetHandleFn_t)(
	unsigned short proto, void* payload, unsigned plen);

int nfqueueRun(unsigned int queue_num, packetHandleFn_t packetHandleFn);

