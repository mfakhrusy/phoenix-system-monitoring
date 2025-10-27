#include <erl_nif.h>
#include <libvirt/libvirt.h>
#include <string.h>

// Resource type for connection handle
static ErlNifResourceType* VIRCONN_RESOURCE_TYPE;

typedef struct {
    virConnectPtr conn;
} VirConnResource;

// Helper function to create error tuple
static ERL_NIF_TERM make_error(ErlNifEnv* env, const char* reason) {
    return enif_make_tuple2(env,
        enif_make_atom(env, "error"),
        enif_make_string(env, reason, ERL_NIF_LATIN1));
}

// Helper function to create ok tuple
static ERL_NIF_TERM make_ok(ErlNifEnv* env, ERL_NIF_TERM value) {
    return enif_make_tuple2(env,
        enif_make_atom(env, "ok"),
        value);
}

// NIF: connect to hypervisor
static ERL_NIF_TERM connect_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 1) {
        return enif_make_badarg(env);
    }

    // Get string length first
    unsigned int len;
    if (!enif_get_list_length(env, argv[0], &len)) {
        return enif_make_badarg(env);
    }

    // Allocate buffer for URI
    char* uri = malloc(len + 1);
    if (!uri) {
        return make_error(env, "memory allocation failed");
    }

    if (!enif_get_string(env, argv[0], uri, len + 1, ERL_NIF_LATIN1)) {
        free(uri);
        return enif_make_badarg(env);
    }

    virConnectPtr conn = virConnectOpen(uri);
    free(uri);
    
    if (!conn) {
        return make_error(env, "failed to connect to hypervisor");
    }

    VirConnResource* res = enif_alloc_resource(VIRCONN_RESOURCE_TYPE, sizeof(VirConnResource));
    if (!res) {
        virConnectClose(conn);
        return make_error(env, "resource allocation failed");
    }
    
    res->conn = conn;
    
    ERL_NIF_TERM term = enif_make_resource(env, res);
    enif_release_resource(res);
    
    return make_ok(env, term);
}

// NIF: close connection
static ERL_NIF_TERM disconnect_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    VirConnResource* res;
    
    if (argc != 1 || !enif_get_resource(env, argv[0], VIRCONN_RESOURCE_TYPE, (void**)&res)) {
        return enif_make_badarg(env);
    }

    if (res->conn) {
        virConnectClose(res->conn);
        res->conn = NULL;
    }
    
    return enif_make_atom(env, "ok");
}

// NIF: list active domains
static ERL_NIF_TERM list_domains_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    VirConnResource* res;
    
    if (argc != 1 || !enif_get_resource(env, argv[0], VIRCONN_RESOURCE_TYPE, (void**)&res)) {
        return enif_make_badarg(env);
    }

    if (!res->conn) {
        return make_error(env, "connection closed");
    }

    int numDomains = virConnectNumOfDomains(res->conn);
    if (numDomains < 0) {
        return make_error(env, "failed to get number of domains");
    }

    if (numDomains == 0) {
        return make_ok(env, enif_make_list(env, 0));
    }

    int* activeDomains = malloc(sizeof(int) * numDomains);
    if (!activeDomains) {
        return make_error(env, "memory allocation failed");
    }

    numDomains = virConnectListDomains(res->conn, activeDomains, numDomains);
    if (numDomains < 0) {
        free(activeDomains);
        return make_error(env, "failed to list domains");
    }

    ERL_NIF_TERM* domain_list = malloc(sizeof(ERL_NIF_TERM) * numDomains);
    if (!domain_list) {
        free(activeDomains);
        return make_error(env, "memory allocation failed");
    }

    for (int i = 0; i < numDomains; i++) {
        virDomainPtr dom = virDomainLookupByID(res->conn, activeDomains[i]);
        if (!dom) {
            domain_list[i] = enif_make_atom(env, "nil");
            continue;
        }

        virDomainInfo info;
        const char* name = virDomainGetName(dom);
        
        if (virDomainGetInfo(dom, &info) == 0 && name) {
            ERL_NIF_TERM keys[] = {
                enif_make_atom(env, "id"),
                enif_make_atom(env, "name"),
                enif_make_atom(env, "cpu_time"),
                enif_make_atom(env, "memory"),
                enif_make_atom(env, "state")
            };
            
            ERL_NIF_TERM values[] = {
                enif_make_int(env, activeDomains[i]),
                enif_make_string(env, name, ERL_NIF_LATIN1),
                enif_make_uint64(env, info.cpuTime),
                enif_make_ulong(env, info.memory),
                enif_make_int(env, info.state)
            };
            
            ERL_NIF_TERM map;
            enif_make_map_from_arrays(env, keys, values, 5, &map);
            domain_list[i] = map;
        } else {
            domain_list[i] = enif_make_atom(env, "nil");
        }
        
        virDomainFree(dom);
    }

    ERL_NIF_TERM result = enif_make_list_from_array(env, domain_list, numDomains);
    
    free(domain_list);
    free(activeDomains);
    
    return make_ok(env, result);
}

virNodeCPUStats *getCPUStats(virConnectPtr conn, int cpu, int *nparams) {
    if (!conn || !nparams) {
        return NULL;
    }

    // Query the number of available CPU stats
    int ret = virNodeGetCPUStats(conn, cpu, NULL, nparams, 0);
    if (ret < 0 || *nparams == 0) {
        return NULL;
    }

    // Allocate memory for the stats
    virNodeCPUStats *stats = calloc((size_t)*nparams, sizeof(virNodeCPUStats));
    if (!stats) {
        return NULL;
    }

    // Fetch the actual CPU stats
    ret = virNodeGetCPUStats(conn, cpu, stats, nparams, 0);
    if (ret < 0) {
        free(stats);
        return NULL;
    }

    return stats;
}

static ERL_NIF_TERM get_host_info_nif(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    VirConnResource* res;
    
    if (argc != 1 || !enif_get_resource(env, argv[0], VIRCONN_RESOURCE_TYPE, (void**)&res)) {
        return enif_make_badarg(env);
    }

    if (!res->conn) {
        return make_error(env, "connection closed");
    }

    virNodeInfo *nodeInfo = malloc(sizeof(virNodeInfo));
    if (virNodeGetInfo(res->conn, nodeInfo) < 0) {
        return make_error(env, "failed to get node info");
    }

    ERL_NIF_TERM* hostCpuTime = calloc(nodeInfo->cpus, sizeof(ERL_NIF_TERM));
    if (!hostCpuTime) {
        free(hostCpuTime);
        return make_error(env, "memory allocation failed for hostCpuTime");
    }

    for (int cpu = 0; cpu < nodeInfo->cpus; cpu++) {
        int cpuStatsParams = 0;
        virNodeCPUStats *cpuStats = getCPUStats(res->conn, cpu, &cpuStatsParams);
        if (!cpuStats) {
        free(cpuStats);
            return make_error(env, "failed to get cpu stats");
        }

        unsigned long long total_cpu_time = 0;
        unsigned long long idle_cpu_time = 0;
        unsigned long long user_cpu_time = 0;
        unsigned long long kernel_cpu_time = 0;

        for (int cpuParamIndex = 0; cpuParamIndex < cpuStatsParams; cpuParamIndex++) {
            unsigned long long value = cpuStats[cpuParamIndex].value;

            total_cpu_time += value;
            if (strcmp(cpuStats[cpuParamIndex].field, VIR_NODE_CPU_STATS_IDLE) == 0) {
                idle_cpu_time += value;
            } else if (strcmp(cpuStats[cpuParamIndex].field, VIR_NODE_CPU_STATS_USER) == 0) {
                user_cpu_time += value;
            } else if (strcmp(cpuStats[cpuParamIndex].field, VIR_NODE_CPU_STATS_KERNEL) == 0) {
                kernel_cpu_time += value;
            }
        }

        ERL_NIF_TERM hostCpuTimeKeys[] = {
            enif_make_atom(env, "total"),
            enif_make_atom(env, "idle"),
            enif_make_atom(env, "user"),
            enif_make_atom(env, "kernel")
        };
            
        ERL_NIF_TERM hostCpuTimeValues[] = {
            enif_make_ulong(env, total_cpu_time),
            enif_make_ulong(env, idle_cpu_time),
            enif_make_ulong(env, user_cpu_time),
            enif_make_ulong(env, kernel_cpu_time),
        };
            
        ERL_NIF_TERM map;
        enif_make_map_from_arrays(env, hostCpuTimeKeys, hostCpuTimeValues, 4, &map);
        hostCpuTime[cpu] = map;

        free(cpuStats);
    }

    ERL_NIF_TERM hostCpuKeys[] = {
        enif_make_atom(env, "time"),
        enif_make_atom(env, "cpus"),
    };

    ERL_NIF_TERM hostCpuValues[] = {
        enif_make_list_from_array(env, hostCpuTime, nodeInfo->cpus),
        enif_make_int(env, nodeInfo->cpus)
    };

    ERL_NIF_TERM result;

    enif_make_map_from_arrays(env, hostCpuKeys, hostCpuValues, 2, &result);

    return make_ok(env, result);
}

// NIF: get host CPU info
// static ERL_NIF_TERM get_host_info_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
//     VirConnResource* res;
    
//     if (argc != 1 || !enif_get_resource(env, argv[0], VIRCONN_RESOURCE_TYPE, (void**)&res)) {
//         return enif_make_badarg(env);
//     }

//     if (!res->conn) {
//         return make_error(env, "connection closed");
//     }

//     virNodeInfo nodeInfo;
//     if (virNodeGetInfo(res->conn, &nodeInfo) < 0) {
//         return make_error(env, "failed to get node info");
//     }

//     ERL_NIF_TERM keys[] = {
//         enif_make_atom(env, "model"),
//         enif_make_atom(env, "memory"),        // in KB
//         enif_make_atom(env, "cpus"),          // total logical CPUs
//         enif_make_atom(env, "mhz"),
//         enif_make_atom(env, "nodes"),         // NUMA nodes
//         enif_make_atom(env, "sockets"),
//         enif_make_atom(env, "cores"),         // cores per socket
//         enif_make_atom(env, "threads")        // threads per core
//     };
    
//     ERL_NIF_TERM values[] = {
//         enif_make_string(env, nodeInfo.model, ERL_NIF_LATIN1),
//         enif_make_ulong(env, nodeInfo.memory),
//         enif_make_uint(env, nodeInfo.cpus),
//         enif_make_uint(env, nodeInfo.mhz),
//         enif_make_uint(env, nodeInfo.nodes),
//         enif_make_uint(env, nodeInfo.sockets),
//         enif_make_uint(env, nodeInfo.cores),
//         enif_make_uint(env, nodeInfo.threads)
//     };
    
//     ERL_NIF_TERM map;
//     enif_make_map_from_arrays(env, keys, values, 8, &map);
    
//     return make_ok(env, map);
// }

// Resource destructor
static void virconn_destructor(ErlNifEnv* env, void* obj) {
    VirConnResource* res = (VirConnResource*)obj;
    if (res->conn) {
        virConnectClose(res->conn);
        res->conn = NULL;
    }
}

// NIF loading
static int load(ErlNifEnv* env, void** priv_data, ERL_NIF_TERM load_info) {
    ErlNifResourceFlags flags = ERL_NIF_RT_CREATE | ERL_NIF_RT_TAKEOVER;
    VIRCONN_RESOURCE_TYPE = enif_open_resource_type(
        env, NULL, "virconn_resource", virconn_destructor, flags, NULL);
    
    if (!VIRCONN_RESOURCE_TYPE) {
        return -1;
    }
    
    return 0;
}

// NIF function array
static ErlNifFunc nif_funcs[] = {
    {"connect", 1, connect_nif, 0},
    {"disconnect", 1, disconnect_nif, 0},
    {"list_domains", 1, list_domains_nif, 0},
    {"get_host_info", 1, get_host_info_nif, 0},
};

// Initialize NIF module
ERL_NIF_INIT(Elixir.LibvirtNif, nif_funcs, load, NULL, NULL, NULL)
