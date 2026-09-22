#!/usr/bin/env bash
# Prove that CQL traffic reaches Cassandra through the Gateway, not directly.
set -euo pipefail

ENVOY_SVC=$(kubectl -n envoy-gateway-system get svc \
  -l gateway.envoyproxy.io/owning-gateway-name=data-gateway \
  -o jsonpath='{.items[0].metadata.name}')
GW_IP=$(kubectl -n envoy-gateway-system get svc "${ENVOY_SVC}" -o jsonpath='{.spec.clusterIP}')

echo "==> Gateway address: ${GW_IP}:9042 (service ${ENVOY_SVC})"
echo "==> Running cqlsh through the Gateway from inside the cluster"
kubectl -n data run cqlsh-test --rm -i --restart=Never --image=cassandra:5.0 -- \
  cqlsh "${GW_IP}" 9042 -e "SELECT cluster_name, release_version FROM system.local;"

echo
echo "==> kind maps nodePort 30942 to localhost:9042, so from the host:"
echo "    cqlsh 127.0.0.1 9042 -e 'DESCRIBE KEYSPACES;'"
echo "    (or: nc -z 127.0.0.1 9042)"
