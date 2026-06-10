# vLLM + KServe Observability

Manifests, Grafana dashboards, and the load generator behind
[How I Instrumented vLLM on Kubernetes: The Dashboards, Queries, and SLOs](https://vinayakgajare.hashnode.dev/vllm-kubernetes-observability-dashboards-queries-slos)

**Stack:** RTX 5090 · k3s · KServe · vLLM 0.20.1 · Gemma 4 26B (NVFP4) · Prometheus · DCGM · Grafana

- `kserve/` — ServingRuntime, InferenceService, model-cache PVC + sync Job
- `dashboards/` — Grafana dashboard JSON (import-ready)
- `loadgen/` — closed-loop chat traffic generator (PowerShell)

The thirty-second capacity review: grep your vLLM startup logs for
`Maximum concurrency` — the engine prints its real headroom at every boot.