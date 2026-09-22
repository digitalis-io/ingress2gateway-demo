#!/usr/bin/env bash
# Bring up a kind cluster with Envoy Gateway in front of a single Cassandra node
# using a Gateway API TCPRoute. See README.md.
set -euo pipefail

CLUSTER=ms784
EG_VERSION=v1.9.1
NODE_PORT=30942

log() { printf '==> %s\n' "$*"; }

log "Creating kind cluster ${CLUSTER}"
kind get clusters | grep -qx "${CLUSTER}" || kind create cluster --config kind-cluster.yaml
kubectl config use-context "kind-${CLUSTER}"

log "Installing Envoy Gateway ${EG_VERSION}"
helm upgrade --install eg oci://docker.io/envoyproxy/gateway-helm \
  --version "${EG_VERSION}" \
  --namespace envoy-gateway-system --create-namespace \
  --wait --timeout 5m

log "Checking the TCPRoute CRD is installed"
kubectl get crd tcproutes.gateway.networking.k8s.io -o jsonpath='{.spec.versions[*].name}{"\n"}'

log "Deploying Cassandra"
kubectl create namespace data --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f cassandra.yaml

log "Deploying the Gateway and TCPRoute"
kubectl apply -f gateway.yaml

log "Waiting for Cassandra to become ready (this takes a couple of minutes)"
kubectl -n data rollout status statefulset/cassandra --timeout=10m

log "Waiting for the Gateway to be programmed"
kubectl -n data wait --for=condition=Programmed gateway/data-gateway --timeout=5m

log "Pinning the Envoy service to nodePort ${NODE_PORT}"
ENVOY_SVC=$(kubectl -n envoy-gateway-system get svc \
  -l gateway.envoyproxy.io/owning-gateway-name=data-gateway \
  -o jsonpath='{.items[0].metadata.name}')
kubectl -n envoy-gateway-system patch svc "${ENVOY_SVC}" --type=json \
  -p "[{\"op\":\"replace\",\"path\":\"/spec/ports/0/nodePort\",\"value\":${NODE_PORT}}]"

log "Done. Run ./test.sh"
