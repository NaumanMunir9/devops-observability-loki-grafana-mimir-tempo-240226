# Architecture — Observability Stack (LGTM + Fluent Bit)

> All diagrams render natively on GitHub. Built with Mermaid JS.

---

## 1. High-Level System Overview

```mermaid
flowchart LR
    subgraph SOURCES["📡 Signal Sources"]
        PODS["☸️ Application Pods\n(stdout/stderr + /metrics + OTLP)"]
        NODES["🖥️ Kubernetes Nodes\n(system logs + node metrics)"]
    end

    subgraph COLLECTION["🔄 Collection"]
        FB["Fluent Bit\nDaemonSet"]
        PROM["Prometheus\nScraper"]
    end

    subgraph BACKENDS["🗄️ Storage Backends"]
        LOKI["📋 Loki\nLogs"]
        MIMIR["📈 Mimir\nMetrics"]
        TEMPO["🔍 Tempo\nTraces"]
    end

    GRAFANA["📊 Grafana\nDashboards · Alerts · Explore"]

    PODS -->|"stdout/stderr"| FB
    NODES -->|"system logs"| FB
    FB -->|"HTTP push (LogQL)"| LOKI

    PODS -->|"/metrics endpoint"| PROM
    PROM -->|"remote_write"| MIMIR

    PODS -->|"OTLP gRPC/HTTP"| TEMPO

    GRAFANA -->|"LogQL"| LOKI
    GRAFANA -->|"PromQL"| MIMIR
    GRAFANA -->|"TraceQL"| TEMPO
```

---

## 2. Kubernetes Deployment Layout

```mermaid
flowchart TB
    subgraph NS["Namespace: observability"]

        subgraph DAEMONSET["DaemonSet (one per node)"]
            FB1["Fluent Bit Pod\nNode 1"]
            FB2["Fluent Bit Pod\nNode 2"]
            FB3["Fluent Bit Pod\nNode 3"]
        end

        subgraph DEPLOYMENTS["Deployments"]
            GF["Grafana\nDeployment\n1 replica"]
        end

        subgraph STATEFULSETS["StatefulSets"]
            LK["Loki\nStatefulSet"]
            MM["Mimir\nStatefulSet"]
            TP["Tempo\nStatefulSet"]
        end

        subgraph STORAGE["💾 Persistent Volumes"]
            PV1["Loki PVC\n50Gi"]
            PV2["Mimir PVC\n100Gi"]
            PV3["Tempo PVC\n50Gi"]
        end
    end

    LK --> PV1
    MM --> PV2
    TP --> PV3
```

---

## 3. Log Pipeline — Fluent Bit to Loki

```mermaid
flowchart LR
    subgraph FB["Fluent Bit Pipeline"]
        INPUT["INPUT\ntail /var/log/containers/*.log\n+ systemd journal"]
        PARSER["PARSER\nDocker/CRI-O JSON parser\nKubernetes metadata enrichment"]
        FILTER["FILTER\nKubernetes label injection\n(namespace, pod_name, container)"]
        OUTPUT["OUTPUT\nHTTP → Loki\nlabel_map: namespace, app, pod"]
    end

    LOGS["📁 /var/log/containers/"] --> INPUT
    INPUT --> PARSER --> FILTER --> OUTPUT
    OUTPUT -->|"POST /loki/api/v1/push"| LOKI["📋 Loki"]
    LOKI --> GRAFANA["📊 Grafana\nExplore → Logs"]
```

---

## 4. Metrics Pipeline — Prometheus to Mimir

```mermaid
flowchart LR
    APPS["☸️ App Pods\n/metrics endpoint"]
    KUBE["Kubernetes\nkube-state-metrics\nnode-exporter"]

    subgraph PROM["Prometheus"]
        SCRAPE["Scrape\n(ServiceMonitor / PodMonitor)"]
        EVAL["Rule Evaluation\n& Alertmanager"]
    end

    MIMIR["📈 Mimir\nLong-term Storage\n(S3 / MinIO)"]
    GRAFANA["📊 Grafana\n→ Explore → Metrics"]

    APPS --> SCRAPE
    KUBE --> SCRAPE
    SCRAPE --> EVAL
    EVAL -->|"remote_write"| MIMIR
    MIMIR --> GRAFANA
```

---

## 5. Trace Pipeline — OpenTelemetry to Tempo

```mermaid
flowchart LR
    subgraph APPS["☸️ Instrumented Services"]
        SVC_A["Service A\n(OTel SDK)"]
        SVC_B["Service B\n(OTel SDK)"]
        SVC_C["Service C\n(OTel SDK)"]
    end

    OTEL["OpenTelemetry\nCollector\n(optional)"]

    subgraph TEMPO["🔍 Tempo"]
        RECV["Receivers\nOTLP · Jaeger · Zipkin"]
        STORE["Object Storage\nS3 / MinIO"]
        QUERY["Tempo Query\nTraceQL engine"]
    end

    GRAFANA["📊 Grafana\nTrace Viewer\n+ Log Correlation"]

    SVC_A & SVC_B & SVC_C -->|"OTLP gRPC :4317"| OTEL
    OTEL --> RECV
    RECV --> STORE
    STORE --> QUERY
    QUERY --> GRAFANA
```

---

## 6. Signal Correlation in Grafana

```mermaid
flowchart TB
    ALERT["🔔 Alert Fires\nError rate > 5% on service-a"]
    METRIC["📈 Mimir\nShow error_rate spike\nat 14:32 UTC"]
    LOGS["📋 Loki\nFilter logs: app=service-a\n|= 'ERROR' | since 14:30"]
    TRACE["🔍 Tempo\nFetch trace by trace_id\nfound in log line"]
    ROOT["🎯 Root Cause\nPostgres timeout at 14:32:07\nin service-a → db query span"]

    ALERT --> METRIC
    METRIC -->|"Grafana Explore: click log link"| LOGS
    LOGS -->|"Grafana: click trace_id"| TRACE
    TRACE --> ROOT
```

---

## 7. Alerting Flow

```mermaid
flowchart LR
    subgraph ALERTS["Alert Sources"]
        LOKI_RULE["Loki\nAlert Rule\n(LogQL)"]
        MIMIR_RULE["Mimir Ruler\nAlert Rule\n(PromQL)"]
    end

    subgraph GRAFANA["📊 Grafana"]
        AM["Alertmanager\n(bundled)"]
        UI["Alert Manager UI"]
    end

    subgraph NOTIFY["📣 Notifications"]
        SLACK["Slack"]
        EMAIL["Email"]
        PAGERDUTY["PagerDuty"]
    end

    LOKI_RULE --> AM
    MIMIR_RULE --> AM
    AM --> SLACK & EMAIL & PAGERDUTY
    AM --> UI
```
