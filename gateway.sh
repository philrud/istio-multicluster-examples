#!/bin/bash -e

### script arguments
# ISTIO_VERSION: e.g. "1.1.3" or "release-1.1-20190417-09-16"
ISTIO_VERSION="${ISTIO_VERSION:-release-1.1-latest-daily}"
# KUBECONFIG: path to a kubeconfig file
KUBECONFIG1="${KUBECONFIG1:-${HOME}/.kube/config}"
KUBECONFIG2="${KUBECONFIG2:-${HOME}/.kube/config}"
# KUBECONTEXT: empty value defaults to "current" context of given kubeconfig file
KUBECONTEXT1="${KUBECONTEXT1:-$(kubectl --kubeconfig=${KUBECONFIG1} config current-context)}"
KUBECONTEXT2="${KUBECONTEXT2:-$(kubectl --kubeconfig=${KUBECONFIG2} config current-context)}"
###

### script arguments sanity checks
if [[ $KUBECONFIG1 == $KUBECONFIG2 ]] && [[ $KUBECONTEXT1 == $KUBECONTEXT2 ]]; then
  echo
  echo " [FAIL] KUBECONFIG{1,2}/KUBECONTEXT{1,2} pairs refer to the same cluster"
  echo "        this configuration requires two distinct clusters, terminating..."
  echo
  exit 1
fi
###

function download_istio_dist {
  local ISTIO_VERSION="${1:?required argument is not set or empty}"
  local ISTIO_DIST_DIR="${2:?required argument is not set or empty}"

  mkdir -p $ISTIO_DIST_DIR

  local BUCKET_CONTENTS
  local BUCKET_URL

  # looking for a RELEASE
  local RELEASE_BUCKET_URL="https://storage.googleapis.com/istio-release/?prefix=releases/${ISTIO_VERSION}/"
  if [[ -z "$BUCKET_URL" ]]; then
    BUCKET_CONTENTS=$(curl --location --fail $RELEASE_BUCKET_URL)
    if [[ $BUCKET_CONTENTS == *"charts/index.yaml"* ]]; then
      BUCKET_URL=$(echo $RELEASE_BUCKET_URL | sed 's/?.*//')
    fi
  fi

  # looking for a DAILY BUILD
  local SNAPSHOT_BUCKET_URL="https://storage.googleapis.com/istio-prerelease/?prefix=daily-build/${ISTIO_VERSION}/"
  if [[ -z "$BUCKET_URL" ]]; then
    BUCKET_CONTENTS=$(curl --location --fail $SNAPSHOT_BUCKET_URL)
    if [[ $BUCKET_CONTENTS == *"charts/index.yaml"* ]]; then
      BUCKET_URL=$(echo $SNAPSHOT_BUCKET_URL | sed 's/?.*//')
    fi
  fi

  if [[ -z "$BUCKET_URL" ]]; then
    echo "couldn't find specified Istio release"
    return 1
  fi

  echo $BUCKET_URL

  # distribution found, downloading artifacts
  local ISTIO_URL=$(sed -ne '/.*/{s/.*<Key>\([^<>]*charts\/istio-[0-9][^<>]*\.tgz\)<\/Key>.*/\1/p;q;}' <<< "$BUCKET_CONTENTS")
  local ISTIO_INIT_URL=$(sed -ne '/.*/{s/.*<Key>\([^<>]*charts\/istio-init-[^<>]*\.tgz\)<\/Key>.*/\1/p;q;}' <<< "$BUCKET_CONTENTS")

  : "${ISTIO_URL:?failed to locate istio-<RELEASE>.tgz}"
  : "${ISTIO_INIT_URL:?failed to locate istio-init-<RELEASE>.tgz}"

  curl --location --fail "${BUCKET_URL}${ISTIO_URL}" -o "${ISTIO_DIST_DIR}/istio.tgz"
  curl --location --fail "${BUCKET_URL}${ISTIO_INIT_URL}" -o "${ISTIO_DIST_DIR}/istio-init.tgz"

  tar xzf "${ISTIO_DIST_DIR}/istio.tgz" -C "${ISTIO_DIST_DIR}"
  tar xzf "${ISTIO_DIST_DIR}/istio-init.tgz" -C "${ISTIO_DIST_DIR}"
}

function ensure_namespace_exists {
  local KUBECTL="${1:?required argument is not set or empty}"
  $KUBECTL create namespace "istio-system" || true
}

function install_istio_init {
  local KUBECTL="${1:?required argument is not set or empty}"
  local ISTIO_INIT_DIR="${2:?required argument is not set or empty}"

  helm template $ISTIO_INIT_DIR --name istio-init --namespace istio-system | $KUBECTL apply -f -

  until [[ "$($KUBECTL get crds | grep 'istio.io\|certmanager.k8s.io' | wc -l)" -gt 52 ]]; do
    echo "awaiting CRDs creation..."
    sleep 3
  done
}

function install_certs {
  local KUBECTL1="${1:?required argument is not set or empty}"
  local KUBECTL2="${2:?required argument is not set or empty}"
  local CERTS_DIR="${3:?required argument is not set or empty}"

  mkdir -p $CERTS_DIR

  cat > $CERTS_DIR/ca-cert.pem <<EOF
-----BEGIN CERTIFICATE-----
MIIDnzCCAoegAwIBAgIJAON1ifrBZ2/BMA0GCSqGSIb3DQEBCwUAMIGLMQswCQYD
VQQGEwJVUzETMBEGA1UECAwKQ2FsaWZvcm5pYTESMBAGA1UEBwwJU3Vubnl2YWxl
MQ4wDAYDVQQKDAVJc3RpbzENMAsGA1UECwwEVGVzdDEQMA4GA1UEAwwHUm9vdCBD
QTEiMCAGCSqGSIb3DQEJARYTdGVzdHJvb3RjYUBpc3Rpby5pbzAgFw0xODAxMjQx
OTE1NTFaGA8yMTE3MTIzMTE5MTU1MVowWTELMAkGA1UEBhMCVVMxEzARBgNVBAgT
CkNhbGlmb3JuaWExEjAQBgNVBAcTCVN1bm55dmFsZTEOMAwGA1UEChMFSXN0aW8x
ETAPBgNVBAMTCElzdGlvIENBMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKC
AQEAyzCxr/xu0zy5rVBiso9ffgl00bRKvB/HF4AX9/ytmZ6Hqsy13XIQk8/u/By9
iCvVwXIMvyT0CbiJq/aPEj5mJUy0lzbrUs13oneXqrPXf7ir3HzdRw+SBhXlsh9z
APZJXcF93DJU3GabPKwBvGJ0IVMJPIFCuDIPwW4kFAI7R/8A5LSdPrFx6EyMXl7K
M8jekC0y9DnTj83/fY72WcWX7YTpgZeBHAeeQOPTZ2KYbFal2gLsar69PgFS0Tom
ESO9M14Yit7mzB1WDK2z9g3r+zLxENdJ5JG/ZskKe+TO4Diqi5OJt/h8yspS1ck8
LJtCole9919umByg5oruflqIlQIDAQABozUwMzALBgNVHQ8EBAMCAgQwDAYDVR0T
BAUwAwEB/zAWBgNVHREEDzANggtjYS5pc3Rpby5pbzANBgkqhkiG9w0BAQsFAAOC
AQEAltHEhhyAsve4K4bLgBXtHwWzo6SpFzdAfXpLShpOJNtQNERb3qg6iUGQdY+w
A2BpmSkKr3Rw/6ClP5+cCG7fGocPaZh+c+4Nxm9suMuZBZCtNOeYOMIfvCPcCS+8
PQ/0hC4/0J3WJKzGBssaaMufJxzgFPPtDJ998kY8rlROghdSaVt423/jXIAYnP3Y
05n8TGERBj7TLdtIVbtUIx3JHAo3PWJywA6mEDovFMJhJERp9sDHIr1BbhXK1TFN
Z6HNH6gInkSSMtvC4Ptejb749PTaePRPF7ID//eq/3AH8UK50F3TQcLjEqWUsJUn
aFKltOc+RAjzDklcUPeG4Y6eMA==
-----END CERTIFICATE-----
EOF

  cat > $CERTS_DIR/ca-key.pem <<EOF
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEAyzCxr/xu0zy5rVBiso9ffgl00bRKvB/HF4AX9/ytmZ6Hqsy1
3XIQk8/u/By9iCvVwXIMvyT0CbiJq/aPEj5mJUy0lzbrUs13oneXqrPXf7ir3Hzd
Rw+SBhXlsh9zAPZJXcF93DJU3GabPKwBvGJ0IVMJPIFCuDIPwW4kFAI7R/8A5LSd
PrFx6EyMXl7KM8jekC0y9DnTj83/fY72WcWX7YTpgZeBHAeeQOPTZ2KYbFal2gLs
ar69PgFS0TomESO9M14Yit7mzB1WDK2z9g3r+zLxENdJ5JG/ZskKe+TO4Diqi5OJ
t/h8yspS1ck8LJtCole9919umByg5oruflqIlQIDAQABAoIBAGZI8fnUinmd5R6B
C941XG3XFs6GAuUm3hNPcUFuGnntmv/5I0gBpqSyFO0nDqYg4u8Jma8TTCIkmnFN
ogIeFU+LiJFinR3GvwWzTE8rTz1FWoaY+M9P4ENd/I4pVLxUPuSKhfA2ChAVOupU
8F7D9Q/dfBXQQCT3VoUaC+FiqjL4HvIhji1zIqaqpK7fChGPraC/4WHwLMNzI0Zg
oDdAanwVygettvm6KD7AeKzhK94gX1PcnsOi3KuzQYvkenQE1M6/K7YtEc5qXCYf
QETj0UCzB55btgdF36BGoZXf0LwHqxys9ubfHuhwKBpY0xg2z4/4RXZNhfIDih3w
J3mihcECgYEA6FtQ0cfh0Zm03OPDpBGc6sdKxTw6aBDtE3KztfI2hl26xHQoeFqp
FmV/TbnExnppw+gWJtwx7IfvowUD8uRR2P0M2wGctWrMpnaEYTiLAPhXsj69HSM/
CYrh54KM0YWyjwNhtUzwbOTrh1jWtT9HV5e7ay9Atk3UWljuR74CFMUCgYEA392e
DVoDLE0XtbysmdlfSffhiQLP9sT8+bf/zYnr8Eq/4LWQoOtjEARbuCj3Oq7bP8IE
Vz45gT1mEE3IacC9neGwuEa6icBiuQi86NW8ilY/ZbOWrRPLOhk3zLiZ+yqkt+sN
cqWx0JkIh7IMKWI4dVQgk4I0jcFP7vNG/So4AZECgYEA426eSPgxHQwqcBuwn6Nt
yJCRq0UsljgbFfIr3Wfb3uFXsntQMZ3r67QlS1sONIgVhmBhbmARrcfQ0+xQ1SqO
wqnOL4AAd8K11iojoVXLGYP7ssieKysYxKpgPE8Yru0CveE9fkx0+OGJeM2IO5hY
qHAoTt3NpaPAuz5Y3XgqaVECgYA0TONS/TeGjxA9/jFY1Cbl8gp35vdNEKKFeM5D
Z7h+cAg56FE8tyFyqYIAGVoBFL7WO26mLzxiDEUfA/0Rb90c2JBfzO5hpleqIPd5
cg3VR+cRzI4kK16sWR3nLy2SN1k6OqjuovVS5Z3PjfI3bOIBz0C5FY9Pmt0g1yc7
mDRzcQKBgQCXWCZStbdjewaLd5u5Hhbw8tIWImMVfcfs3H1FN669LLpbARM8RtAa
8dYwDVHmWmevb/WX03LiSE+GCjCBO79fa1qc5RKAalqH/1OYxTuvYOeTUebSrg8+
lQFlP2OC4GGolKrN6HVWdxtf+F+SdjwX6qGCfYkXJRLYXIFSFjFeuw==
-----END RSA PRIVATE KEY-----
EOF

  cat > $CERTS_DIR/root-cert.pem <<EOF
-----BEGIN CERTIFICATE-----
MIID7TCCAtWgAwIBAgIJAOIRDhOcxsx6MA0GCSqGSIb3DQEBCwUAMIGLMQswCQYD
VQQGEwJVUzETMBEGA1UECAwKQ2FsaWZvcm5pYTESMBAGA1UEBwwJU3Vubnl2YWxl
MQ4wDAYDVQQKDAVJc3RpbzENMAsGA1UECwwEVGVzdDEQMA4GA1UEAwwHUm9vdCBD
QTEiMCAGCSqGSIb3DQEJARYTdGVzdHJvb3RjYUBpc3Rpby5pbzAgFw0xODAxMjQx
OTE1NTFaGA8yMTE3MTIzMTE5MTU1MVowgYsxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
DApDYWxpZm9ybmlhMRIwEAYDVQQHDAlTdW5ueXZhbGUxDjAMBgNVBAoMBUlzdGlv
MQ0wCwYDVQQLDARUZXN0MRAwDgYDVQQDDAdSb290IENBMSIwIAYJKoZIhvcNAQkB
FhN0ZXN0cm9vdGNhQGlzdGlvLmlvMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIB
CgKCAQEA38uEfAatzQYqbaLou1nxJ348VyNzumYMmDDt5pbLYRrCo2pS3ki1ZVDN
8yxIENJFkpKw9UctTGdbNGuGCiSDP7uqF6BiVn+XKAU/3pnPFBbTd0S33NqbDEQu
IYraHSl/tSk5rARbC1DrQRdZ6nYD2KrapC4g0XbjY6Pu5l4y7KnFwSunnp9uqpZw
uERv/BgumJ5QlSeSeCmhnDhLxooG8w5tC2yVr1yDpsOHGimP/mc8Cds4V0zfIhQv
YzfIHphhE9DKjmnjBYLOdj4aycv44jHnOGc+wvA1Jqsl60t3wgms+zJTiWwABLdw
zgMAa7yxLyoV0+PiVQud6k+8ZoIFcwIDAQABo1AwTjAdBgNVHQ4EFgQUOUYGtUyh
euxO4lGe4Op1y8NVoagwHwYDVR0jBBgwFoAUOUYGtUyheuxO4lGe4Op1y8NVoagw
DAYDVR0TBAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEANXLyfAs7J9rmBamGJvPZ
ltx390WxzzLFQsBRAaH6rgeipBq3dR9qEjAwb6BTF+ROmtQzX+fjstCRrJxCto9W
tC8KvXTdRfIjfCCZjhtIOBKqRxE4KJV/RBfv9xD5lyjtCPCQl3Ia6MSf42N+abAK
WCdU6KCojA8WB9YhSCzza3aQbPTzd26OC/JblJpVgtus5f8ILzCsz+pbMimgTkhy
AuhYRppJaQ24APijsEC9+GIaVKPg5IwWroiPoj+QXNpshuvqVQQXvGaRiq4zoSnx
xAJz+w8tjrDWcf826VN14IL+/Cmqlg/rIfB5CHdwVIfWwpuGB66q/UiPegZMNs8a
3g==
-----END CERTIFICATE-----
EOF

  cat > $CERTS_DIR/cert-chain.pem <<EOF
-----BEGIN CERTIFICATE-----
MIIDnzCCAoegAwIBAgIJAON1ifrBZ2/BMA0GCSqGSIb3DQEBCwUAMIGLMQswCQYD
VQQGEwJVUzETMBEGA1UECAwKQ2FsaWZvcm5pYTESMBAGA1UEBwwJU3Vubnl2YWxl
MQ4wDAYDVQQKDAVJc3RpbzENMAsGA1UECwwEVGVzdDEQMA4GA1UEAwwHUm9vdCBD
QTEiMCAGCSqGSIb3DQEJARYTdGVzdHJvb3RjYUBpc3Rpby5pbzAgFw0xODAxMjQx
OTE1NTFaGA8yMTE3MTIzMTE5MTU1MVowWTELMAkGA1UEBhMCVVMxEzARBgNVBAgT
CkNhbGlmb3JuaWExEjAQBgNVBAcTCVN1bm55dmFsZTEOMAwGA1UEChMFSXN0aW8x
ETAPBgNVBAMTCElzdGlvIENBMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKC
AQEAyzCxr/xu0zy5rVBiso9ffgl00bRKvB/HF4AX9/ytmZ6Hqsy13XIQk8/u/By9
iCvVwXIMvyT0CbiJq/aPEj5mJUy0lzbrUs13oneXqrPXf7ir3HzdRw+SBhXlsh9z
APZJXcF93DJU3GabPKwBvGJ0IVMJPIFCuDIPwW4kFAI7R/8A5LSdPrFx6EyMXl7K
M8jekC0y9DnTj83/fY72WcWX7YTpgZeBHAeeQOPTZ2KYbFal2gLsar69PgFS0Tom
ESO9M14Yit7mzB1WDK2z9g3r+zLxENdJ5JG/ZskKe+TO4Diqi5OJt/h8yspS1ck8
LJtCole9919umByg5oruflqIlQIDAQABozUwMzALBgNVHQ8EBAMCAgQwDAYDVR0T
BAUwAwEB/zAWBgNVHREEDzANggtjYS5pc3Rpby5pbzANBgkqhkiG9w0BAQsFAAOC
AQEAltHEhhyAsve4K4bLgBXtHwWzo6SpFzdAfXpLShpOJNtQNERb3qg6iUGQdY+w
A2BpmSkKr3Rw/6ClP5+cCG7fGocPaZh+c+4Nxm9suMuZBZCtNOeYOMIfvCPcCS+8
PQ/0hC4/0J3WJKzGBssaaMufJxzgFPPtDJ998kY8rlROghdSaVt423/jXIAYnP3Y
05n8TGERBj7TLdtIVbtUIx3JHAo3PWJywA6mEDovFMJhJERp9sDHIr1BbhXK1TFN
Z6HNH6gInkSSMtvC4Ptejb749PTaePRPF7ID//eq/3AH8UK50F3TQcLjEqWUsJUn
aFKltOc+RAjzDklcUPeG4Y6eMA==
-----END CERTIFICATE-----
EOF

  $KUBECTL1 create secret generic cacerts -n istio-system \
    --from-file=$CERTS_DIR/ca-cert.pem \
    --from-file=$CERTS_DIR/ca-key.pem \
    --from-file=$CERTS_DIR/root-cert.pem \
    --from-file=$CERTS_DIR/cert-chain.pem || true

  $KUBECTL2 create secret generic cacerts -n istio-system \
    --from-file=$CERTS_DIR/ca-cert.pem \
    --from-file=$CERTS_DIR/ca-key.pem \
    --from-file=$CERTS_DIR/root-cert.pem \
    --from-file=$CERTS_DIR/cert-chain.pem || true
}

function install_istio {
  local KUBECTL="${1:?required argument is not set or empty}"
  local ISTIO_DIR="${2:?required argument is not set or empty}"

  helm template $ISTIO_DIR --name istio \
    --namespace istio-system \
    -f $ISTIO_DIR/example-values/values-istio-multicluster-gateways.yaml \
    | $KUBECTL apply -f -
}

function await_istio_rollout {
  local KUBECTL="${1:?required argument is not set or empty}"

  $KUBECTL -n istio-system rollout status deployment istiocoredns
  $KUBECTL -n istio-system rollout status deployment istio-ingressgateway
  $KUBECTL -n istio-system rollout status deployment istio-egressgateway
}

function configure_dns {
  local KUBECTL="${1:?required argument is not set or empty}"

  $KUBECTL -n istio-system rollout status deployment istiocoredns
  $KUBECTL apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: kube-dns
  namespace: kube-system
data:
  stubDomains: |
    {"global": ["$($KUBECTL get svc -n istio-system istiocoredns -o jsonpath={.spec.clusterIP})"]}
EOF
}

function install_probe {
  local KUBECTL_SRV="${1:?required argument is not set or empty}"
  local KUBECTL_CLI="${2:?required argument is not set or empty}"

  $KUBECTL_SRV create ns test || true
  $KUBECTL_SRV label --overwrite=true ns test istio-injection=enabled || true
  $KUBECTL_SRV apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: test-srv
  namespace: test
spec:
  ports:
  - port: 8080
    name: http-echo
  selector:
    app: test-srv
---
apiVersion: apps/v1beta1
kind: Deployment
metadata:
  name: test-srv
  namespace: test
spec:
  template:
    metadata:
      labels:
        app: test-srv
    spec:
      containers:
      - name: fortio-server
        image: fortio/fortio
        ports:
        - containerPort: 8080
        args:
        - server
EOF

  $KUBECTL_SRV -n test rollout status deployment test-srv

  local SRV_GATEWAY_IP
  while true; do
    SRV_GATEWAY_IP=$($KUBECTL_SRV -n istio-system \
      get svc istio-ingressgateway \
      -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    if [[ -z $SRV_GATEWAY_IP ]]; then
      echo "awaiting IngressGateway external IP address provisioning..."
      sleep 3
    else
      echo "discovered IngressGateway external IP address: ${SRV_GATEWAY_IP}"
      break
    fi
  done

  $KUBECTL_CLI create ns test || true
  $KUBECTL_CLI label --overwrite=true ns test istio-injection=enabled || true
  $KUBECTL_CLI apply -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: ServiceEntry
metadata:
  name: test-srv-global
  namespace: test
spec:
  hosts:
  # must be of form name.namespace.global
  - test-srv.test.global
  # Treat remote cluster services as part of the service mesh
  # as all clusters in the service mesh share the same root of trust.
  location: MESH_INTERNAL
  ports:
  - name: http1
    number: 8080
    protocol: http
  resolution: DNS
  addresses:
  # the IP address to which httpbin.bar.global will resolve to
  # must be unique for each remote service, within a given cluster.
  # This address need not be routable. Traffic for this IP will be captured
  # by the sidecar and routed appropriately.
  - 127.255.0.2
  endpoints:
  # This is the routable address of the ingress gateway in cluster2 that
  # sits in front of sleep.foo service. Traffic from the sidecar will be
  # routed to this address.
  - address: ${SRV_GATEWAY_IP}
    ports:
      http1: 15443 # Do not change this port value
EOF

  sleep 5
}

function check_probe {
  local KUBECTL="${1:?required argument is not set or empty}"

  local POD=$($KUBECTL -n test get pod -l app=test-srv -o jsonpath="{.items[0].metadata.name}")
  $KUBECTL -n test exec -it $POD -c fortio-server -- fortio curl http://test-srv.test.global:8080/debug
}

### main block

TEMP_DIR=$(mktemp -d)
ISTIO_DIST_DIR="${TEMP_DIR}/istio"

KUBECTL1="kubectl --kubeconfig=${KUBECONFIG1} --context=${KUBECONTEXT1}"
KUBECTL2="kubectl --kubeconfig=${KUBECONFIG2} --context=${KUBECONTEXT2}"

echo -e "\n [*] downloading Istio (version: ${ISTIO_VERSION}) to $ISTIO_DIST_DIR ... \n"
download_istio_dist "$ISTIO_VERSION" "$ISTIO_DIST_DIR"
echo -e "\n [OK] downloaded Istio (version: ${ISTIO_VERSION}) to $ISTIO_DIST_DIR \n"

echo -e "\n [*] ensuring Istio namespaces exist ... \n"
ensure_namespace_exists "$KUBECTL1"
ensure_namespace_exists "$KUBECTL2"
echo -e "\n [OK] ensured Istio namespaces exist \n"

echo -e "\n [*] installing Istio Init (CRDs) ... \n"
install_istio_init "$KUBECTL1" "${ISTIO_DIST_DIR}/istio-init"
install_istio_init "$KUBECTL2" "${ISTIO_DIST_DIR}/istio-init"
echo -e "\n [OK] installed Istio Init (CRDs) \n"

echo -e "\n [*] ensuring certs are populated ... \n"
install_certs "$KUBECTL1" "$KUBECTL2" "$TEMP_DIR/certs"
echo -e "\n [OK] ensured certs are populated \n"

echo -e "\n [*] installing Istio ... \n"
install_istio "$KUBECTL1" "${ISTIO_DIST_DIR}/istio"
install_istio "$KUBECTL2" "${ISTIO_DIST_DIR}/istio"
echo -e "\n [OK] installed Istio \n"

echo -e "\n [*] configuring kube-dns ... \n"
configure_dns "$KUBECTL1"
configure_dns "$KUBECTL2"
echo -e "\n [OK] configured kube-dns \n"

echo -e "\n [*] waiting till everything's running ... \n"
await_istio_rollout "$KUBECTL1"
await_istio_rollout "$KUBECTL2"
echo -e "\n [OK] looks like everything's running \n"

echo -e "\n [*] installing probe apps ... \n"
install_probe "$KUBECTL1" "$KUBECTL2"
install_probe "$KUBECTL2" "$KUBECTL1"
echo -e "\n [OK] installed probe apps \n"

echo -e "\n [*] verifying cross-cluster connectivity using probe apps ... \n"
check_probe "$KUBECTL1"
check_probe "$KUBECTL2"
echo -e "\n [OK] successfully verified cross-cluster connectivity using probe apps \n"

echo -e "\n [OK] ALL DONE! \n"
