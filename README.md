<p align="center">
  <a href="https://digitalis.io">
    <img src="https://cdn.prod.website-files.com/68370d67a3c849c28c22f703/68370d67a3c849c28c22f803_digitalis-logo.svg" alt="Digitalis.IO" width="300">
  </a>
</p>

<p align="center">
  <em>Built and maintained by <a href="https://digitalis.io">Digitalis.IO</a></em>
</p>

# ingress2gateway-demo

A runnable [kind](https://kind.sigs.k8s.io/) cluster that puts **Apache Cassandra behind a Gateway API `TCPRoute`**, with no Ingress object and no ingress-nginx `tcp-services` ConfigMap anywhere.

ingress-nginx was archived read only on 24 March 2026. `ingress2gateway` converts your HTTP Ingress objects, but it cannot see the raw TCP ports your data platform used, because those were never Ingress objects in the first place. This repo shows what you have to write by hand instead.

Companion to the Digitalis post [What ingress2gateway will not migrate for Cassandra and Kafka](https://digitalis.io/blog).

## Quick start

Needs `kind`, `kubectl`, `helm` and a running Docker or Rancher Desktop. About five minutes, most of it Cassandra starting up.

```bash
git clone https://github.com/digitalis-io/ingress2gateway-demo.git
cd ingress2gateway-demo
./setup.sh
./test.sh
```

Expected output from `./test.sh`:

```
==> Gateway address: 10.96.147.239:9042 (service envoy-data-data-gateway-42dff023)
==> Running cqlsh through the Gateway from inside the cluster

 cluster_name | release_version
--------------+-----------------
        ms784 |           5.0.9

(1 rows)
```

That query only succeeds if the `TCPRoute` is programmed, so it is the whole proof in one command.

Tear it down with `./teardown.sh`.

## What gets built

| Component | Detail |
|---|---|
| kind cluster | `ms784`, single node, nodePort `30942` mapped to `localhost:9042` |
| Gateway controller | Envoy Gateway `v1.9.1`, `GatewayClass eg` |
| Envoy service | forced to `NodePort` via the `EnvoyProxy` CRD, because kind has no load balancer |
| Database | one Cassandra `5.0` pod in namespace `data`, headless service on 9042 |
| Gateway | `data-gateway` with a single `protocol: TCP` listener on port 9042 |
| Route | `TCPRoute/cassandra-0` attaching that listener to the Cassandra service |

## Why Cassandra and not Kafka

An unencrypted CQL connection has no TLS handshake, so there is no SNI for the Gateway to match on and the only option is `TCPRoute` with one listener port per node. No certificates, no operator, three manifests: the shortest path to a working demo.

Encrypted Cassandra is a different story. The TLS handshake does carry a server name, which is how k8ssandra exposes CQL through Traefik on port 9142 with several clusters behind one port and token aware routing intact. It needs a driver that sets a per node SNI name.

Kafka sits at the far end of the same scale. Clients always send SNI, so many brokers share one port through `TLSRoute` hostname matching, but you need certificates, a Strimzi install and correct `advertised.listeners` before anything works. The blog post covers that side; this repo covers the one you can run in five minutes.

## Usage examples

### Route a second Cassandra node

Real clusters need one listener and one route per node, otherwise you lose token aware routing in the driver. Scale the StatefulSet, then add a matching pair:

```yaml
# in the Gateway
    - name: cassandra-1
      protocol: TCP
      port: 9043
      allowedRoutes:
        kinds:
          - kind: TCPRoute
---
apiVersion: gateway.networking.k8s.io/v1
kind: TCPRoute
metadata:
  name: cassandra-1
  namespace: data
spec:
  parentRefs:
    - name: data-gateway
      sectionName: cassandra-1
  rules:
    - backendRefs:
        - name: cassandra-1
          port: 9042
```

Generate these. Hand writing thirty of them is how mistakes get made.

### Check what the route is actually doing

```bash
kubectl -n data get tcproute cassandra-0 \
  -o jsonpath='{.status.parents[*].conditions[*].type}{" "}{.status.parents[*].conditions[*].status}{"\n"}'
# Accepted ResolvedRefs True True

kubectl -n data get gateway data-gateway -o wide
kubectl -n envoy-gateway-system get svc -l gateway.envoyproxy.io/owning-gateway-name=data-gateway
```

### Connect from the host

kind maps the Envoy nodePort to your laptop, so any local CQL client works:

```bash
cqlsh 127.0.0.1 9042 -e "DESCRIBE KEYSPACES;"
```

## Configuration reference

Values are edited in the files directly, so this is the map of what to change and where.

| Setting | File | Default | Example |
|---|---|---|---|
| Cluster name | `kind-cluster.yaml`, `setup.sh` (`CLUSTER`) | `ms784` | `gateway-demo` |
| Host port for CQL | `kind-cluster.yaml` (`hostPort`) | `9042` | `19042` |
| Envoy nodePort | `kind-cluster.yaml`, `setup.sh` (`NODE_PORT`) | `30942` | `30943` |
| Envoy Gateway version | `setup.sh` (`EG_VERSION`) | `v1.9.1` | `v1.8.0` |
| Cassandra image | `cassandra.yaml` | `cassandra:5.0` | `cassandra:4.1` |
| Cassandra heap | `cassandra.yaml` (`MAX_HEAP_SIZE`) | `512M` | `1G` |
| Gateway listener port | `gateway.yaml` | `9042` | `9142` |

## What this demo confirmed

Run against Envoy Gateway v1.9.1 on 22 September 2026:

- The `TCPRoute` CRD is served at **both `v1` and `v1alpha2`**. Applying the older one prints:

  ```
  Warning: The v1alpha2 version of TCPRoute has been deprecated and will be removed
  in a future release of the API. Please upgrade to v1.
  ```

  The manifests here use `gateway.networking.k8s.io/v1`, which Envoy Gateway accepts and programmes. `TCPRoute` graduated to the Gateway API Standard channel in [v1.6.0](https://kubernetes.io/blog/2026/08/03/gateway-api-v1-6-release/), released on 30 June 2026.

- A plain unencrypted CQL session works end to end through the Gateway, with no SNI anywhere in the path.

## Known limitations

- Single Cassandra node, so the per node listener problem is described above rather than demonstrated.
- No TLS. Client to node encryption plus `TLSRoute` is the Kafka shaped variant and is deliberately out of scope.
- `NodePort` rather than a real load balancer, because kind has none. On a cloud cluster drop the `EnvoyProxy` override and the nodePort patch in `setup.sh`.
- Not a production topology. There is no persistent volume, no anti-affinity and no resource tuning beyond a small heap.

## Contact

Maintained by [Digitalis.io](https://digitalis.io). Support at [digitalis.io/contact](https://digitalis.io/contact).

We run Kubernetes, Cassandra and Kafka in production for customers 24x7, including migrations off ingress-nginx with live clients in front of them.

## License

See [LICENSE](LICENSE) for details.
