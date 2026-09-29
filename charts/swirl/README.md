
# Swirl Helm Chart

Deploy Swirl AI-powered search platform on Azure Kubernetes Service (AKS).

## Overview

Swirl is an AI-powered search and retrieval augmented generation (RAG) platform that unifies multiple data sources into a single, intelligent search interface. This Helm chart deploys the complete Swirl stack on Azure AKS, including:

- Swirl search application
- Celery workers for async task processing
- Redis for caching and message brokering
- Apache Tika for document processing
- Topic Text Matcher for semantic search
- MCP (Model Context Protocol) server, built into SWIRL 5
- Horizontal Pod Autoscaling (HPA)
- Azure-native persistent storage

## Prerequisites

- Kubernetes cluster (AKS) running version 1.25.0 or higher
- Helm 3.x
- Azure CLI configured with appropriate permissions
- PostgreSQL database (external)
- Docker registry credentials (if using private images)

### Autoscaling support
Autoscaling uses the celery queue depth and busy workers ratio to control scaling of pods and
nodes (provided the cluster node pools support this)

Swirl pod's main container provides a metrics endport at `/swirl/metrics/celery` providing:
-  `celery_queue_depth`: the number of tasks waiting in the queue.
- `celery_workers_busy_ratio`: the proportion of workers that are actively processing tasks.

#### Prometheus

* **Prometheus** is the monitoring system responsible for **collecting and storing metrics**.
* It scrapes metrics from the swirl pod at regular intervals (`15s`).
* In our setup, an **extra scrape job** is configured specifically for Celery:

```yaml
job_name: 'swirl-celery-activity'
metrics_path: /swirl/metrics/celery
scrape_interval: 15s
targets:
  - 'swirl-service.swirl.svc.cluster.local:8000'
```

* Once collected, these metrics are stored in Prometheus’ time-series database, making them queryable for downstream systems.

#### Prometheus Adapter

* Kubernetes HPAs cannot consume raw Prometheus metrics directly.
* The **Prometheus Adapter** acts as a **bridge** between Prometheus and Kubernetes.
* It **translates Prometheus queries into Kubernetes External Metrics API objects**.
* In our setup, we configure adapter rules so that:
    * `celery_queue_depth` from Prometheus → available to HPA as `external.metrics.k8s.io/celery_queue_depth`
    * `celery_workers_busy_ratio` → available as `external.metrics.k8s.io/celery_workers_busy_ratio`

Example rule:

```yaml
- seriesQuery: 'celery_queue_depth{job="swirl-celery-activity"}'
  name: { as: 'celery_queue_depth' }
  metricsQuery: 'avg(celery_queue_depth)'
```

> **NOTE:** Without this adapter, Kubernetes would not be able to see the Celery metrics.

#### Horizontal Pod Autoscaler (HPA)

* The **HPA is the Kubernetes controller that performs the scaling action**.
* It queries the metrics API (populated by the adapter) to decide when to increase or decrease the number of pods.
* In our Helm configuration, we define:
    * `minReplicas`/`maxReplicas`: the lower and upper limits of scaling.
    * `queueDepthTarget`: the maximum acceptable queue size per worker.
    * `busyRatioTarget`: the acceptable threshold of worker utilization.
    * `behavior`: cooldown periods to avoid rapid up/down fluctuations.

By combining these rules, the HPA can, for example:

* Add pods when the queue grows beyond the target.
* Reduce pods during low activity, saving resources.

#### End to End interaction flow

**1 Swirl exposes metrics**

→ The Celery workers publish queue and worker activity data at `/swirl/metrics/celery`.

**2 Prometheus scrapes data**

→ Every 15 seconds, Prometheus collects these metrics and stores them.

**3 Adapter transforms data**

→ The Prometheus Adapter converts Prometheus queries into metrics the Kubernetes API can expose.

**4 HPA consumes metrics**

→ The HPA queries the Kubernetes metrics API and compares values (queue depth, worker ratio) against the desired targets defined in Helm.

**5 Scaling action happens**

→ If the queue is too deep or workers are overloaded, pods are scaled up.
→ If queues are empty and workers idle, pods are scaled down.

#### Troubleshooting & Verification

* Check metrics exposed to Kubernetes:

  ```bash
  kubectl get --raw "/apis/external.metrics.k8s.io/v1beta1/namespaces/swirl/celery_queue_depth" | jq
  ```
* Inspect HPA decisions:

  ```bash
  kubectl describe hpa -n swirl
  ```
* Validate Prometheus queries directly:

  ```bash
  avg(celery_queue_depth)
  avg(celery_workers_busy_ratio)
  ```



### Helm chart configuration

The **Swirl Helm chart** encapsulates all scaling configuration. For example:

```
swirl:
  autoscaling:
    enabled: true
    minReplicas: 1
    maxReplicas: 3
    queueDepthTarget: "10.0"
    busyRatioTarget: "1.0"
    behavior:
      scaleUp:
        stabilizationWindowSeconds: 300
      scaleDown:
        stabilizationWindowSeconds: 300
```

* Enabling autoscaling allows the chart to deploy an HPA.
* The HPA is automatically wired to the external metrics from the adapter.
### Required Azure Resources

- Azure Kubernetes Service (AKS) cluster
- Azure PostgreSQL Flexible Server
- Azure Storage Account (for persistent volumes)
- Azure Key Vault (recommended for secrets management)
- Azure Container Registry or Docker Hub access

## Installation

### 1. Add the Helm Repository

```bash
helm repo add swirlai https://swirlai.github.io/helm-charts
helm repo update
```

### 2. Create Required Secrets
kubectl create namespace swirl

kubectl create secret docker-registry docker-secret \
--docker-server=<your-registry-server> \
--docker-username=<your-username> \
--docker-password=<your-password-or-personal-access-token> \
--namespace=swirl

**Note:** 

### 3. Create values.yaml to override default values for your environment
```yaml
swirl:
  secret:
    envSecrets:
      # Admin user credentials for one time   
      ADMIN_PASSWORD: ""
      SWIRL_LICENSE: "<json text for Swirl enterprise license"
      # Optional: AI/LLM API Keys
      # OPENAI_API_KEY: ""
      # AZURE_OPENAI_API_KEY: ""
      # Optional: Authentication
      # GOOGLE_AUTH_CLIENT_ID: ""
      # MS_AUTH_CLIENT_ID: ""
      # MS_TENANT_ID: ""
  config:
    envConfig:
      # Application Configuration
      # Database Configuration
      SQL_HOST: "your-postgres-server.postgres.database.azure.com"
      SQL_PORT: "5432"
      SQL_DATABASE: "swirl"
      SQL_USER: "swirluser"
      SQL_PASSWORD: "your-secure-password"
      
      # Admin Credentials
      ADMIN_PASSWORD: "your-admin-password"
      
      
      # Optional: AI/LLM API Keys
      # OPENAI_API_KEY: "sk-..."
      # AZURE_OPENAI_API_KEY: "..."
      
      # Optional: Authentication
      # GOOGLE_AUTH_CLIENT_ID: "..."
      # MS_AUTH_CLIENT_ID: "..."
      # MS_TENANT_ID: "..."
```


# Examples
## Minimal Production Setup
```
# production-values.yaml
namespace: swirl-prod

swirl:
  replicaCount: null
  image:
    tag: "v4_3_0_0"
  
  autoscaling:
    enabled: true
    minReplicas: 1
    maxReplicas: 2

  resources:
    limits:
      cpu: 4
      memory: 8Gi
    requests:
      cpu: 2
      memory: 4Gi

celeryWorker:
  enabled: true
  replicaCount: null
  
  autoscaling:
    enabled: true
    minReplicas: 1
    maxReplicas: 5

redis:
  enabled: true

tika:
  enabled: true
  replicaCount: 1

topicTextMatcher:
  enabled: true
  replicaCount: 1
```

## Development/Testing Setup
```bash
# dev-values.yaml
namespace: swirl-dev

swirl:
  replicaCount: 1
  
  resources:
    limits:
      cpu: 2
      memory: 4Gi
    requests:
      cpu: 1
      memory: 2Gi

celeryWorker:
  enabled: true
  replicaCount: 1

redis:
  enabled: true

tika:
  enabled: false

topicTextMatcher:
  enabled: false
```

## With the MCP Server

SWIRL 5 includes a built-in MCP (Model Context Protocol) server. The chart runs it from the SWIRL image as its own deployment, serving the streamable HTTP transport at `/mcp` on port 8675. It replaces the MCP proxy, which is retired as of SWIRL 5.0.

### Inside the cluster (static token, the default)

Every MCP caller acts as one SWIRL user, identified by an API token. There is no inbound authentication in this mode, so the service is a `ClusterIP` and is reachable only from inside the cluster.

```bash
# mcp-values.yaml
mcp:
  enabled: true

swirl:
  secret:
    envSecrets:
      # At most 40 characters, for example: openssl rand -hex 20
      SWIRL_MCP_TOKEN: "<api-key>"
```

A hook job provisions the token in SWIRL for the `admin` user on install and on upgrade. The MCP endpoint is then available in the cluster at `http://mcp.<namespace>.svc.cluster.local:8675/mcp`.

### Public endpoint (OIDC)

To expose the MCP server outside the cluster, use OIDC mode. Callers present their own bearer token, which the MCP server validates against your identity provider and SWIRL maps to the caller's own user. The chart refuses to render a `LoadBalancer` service in static mode.

```bash
# mcp-public-values.yaml
mcp:
  enabled: true
  auth:
    mode: oidc
    oidc:
      issuer: "https://<idp-host>/realms/<realm>"
      jwksUri: "https://<idp-host>/realms/<realm>/protocol/openid-connect/certs"
      audience: "https://<mcp-host>"
      resourceUrl: "https://<mcp-host>"
  service:
    type: LoadBalancer
    loadBalancer:
      azureResourceGroup: "my-resource-group"
      azurePublicIPName: "swirl-mcp-public-ip"
```

### Upgrading to 0.3.0

Chart 0.3.0 changes the `mcp` values incompatibly. If you have `mcp.enabled: true`:

| Removed | Replace with |
|---|---|
| `mcp.image.*` | Nothing. The MCP server runs from `swirl.image`. |
| `mcp.host` | Nothing. |
| `mcp.port: 9000` | `mcp.port: 8675` (the default) |
| `mcp.swirl.api_base` | `mcp.baseUrl`, or leave empty for the in-cluster SWIRL service |
| `mcp.swirl.api_base_path`, `mcp.swirl.api_timeout` | Nothing. |
| `mcp.loadBalancer.*` | `mcp.service.loadBalancer.*`, with `mcp.service.type: LoadBalancer` and `mcp.auth.mode: oidc` |
| `mcp.probe.*.execCommand` | Nothing. The probes are TCP checks. |
| secrets `SWIRL_MCP_USERNAME`, `SWIRL_MCP_PASSWORD` | secret `SWIRL_MCP_TOKEN` |
| config `SWIRL_MCP_ENABLED`, `SWIRL_MCP_HOST`, `SWIRL_MCP_PORT` | Nothing. SWIRL 5 does not read them. |

The chart stops with an error if the removed `mcp.image`, `mcp.swirl` or `mcp.host` values are still set while MCP is enabled. MCP clients must change too: the proxy spoke a raw TCP protocol on port 9000; the built-in server speaks streamable HTTP at `http://<host>:8675/mcp`.

The built-in MCP server requires SWIRL 5.0 or later. To keep running the MCP proxy with SWIRL 4.x, stay on chart 0.2.5.

# Upgrading
```bash
# Update repository
helm repo update

# Check for changes
helm diff upgrade swirl swirlai/swirl -f values.yaml

# Upgrade
helm upgrade swirl swirlai/swirl \
  --namespace swirl \
  -f secrets.yaml \
  -f custom-values.yaml
```

# Uninstalling
```bash
helm uninstall swirl --namespace swirl
```

Removing all data including PVCs (impacts the Azure File Shares)
```bash
kubectl delete pvc -n swirl --all
```

# Troubleshooting
## Check Pod Status
```bash
kubectl get pods -n swirl
kubectl describe pod <pod-name> -n swirl
kubectl logs <pod-name> -n swirl
```

## Check Celery Workers
```bash
# View worker logs
kubectl logs -n swirl -l app.kubernetes.io/name=celery-worker

# Check worker health
kubectl exec -it -n swirl <celery-pod> -- celery -A swirl_server inspect active
```

## Storage Issues
```bash
# Check PVC status
kubectl get pvc -n swirl

# Check storage class
kubectl get storageclass
```

# Common Issues
1. ImagePullBackOff: Ensure Docker registry secret is created correctly
2. CrashLoopBackOff: Check logs for database connection or configuration errors
3. Pending PVCs: Verify Azure storage account and CSI driver are configured
4. HPA not scaling: Ensure metrics-server is installed in the cluster

# Support
Documentation: https://docs.swirl.today
Email: support@swirlaiconnect.com
Website: https://swirl.today
