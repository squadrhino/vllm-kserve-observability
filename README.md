# vLLM + KServe Observability

## Architecture
<img width="1750" height="1163" alt="arc_diagram" src="https://github.com/user-attachments/assets/269867e2-6479-4852-a641-728b4c9681bc" />

Manifests, Grafana dashboards, and the load generator behind
[How I Instrumented vLLM on Kubernetes: The Dashboards, Queries, and SLOs](https://vinayakgajare.hashnode.dev/vllm-kubernetes-observability-dashboards-queries-slos)

**Stack:** KServe · vLLM 0.20.1 · Gemma 4 26B (NVFP4) · Prometheus · DCGM · Grafana

- `kserve/` — ServingRuntime, InferenceService, model-cache PVC + sync Job
- `dashboards/` — Grafana dashboard JSON (import-ready)
- `loadgen/` — closed-loop chat traffic generator (PowerShell)

The thirty-second capacity review: grep your vLLM startup logs for
`Maximum concurrency` — the engine prints its real headroom at every boot.
