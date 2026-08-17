# Cost — Capstone Phoenix

## Monthly itemized cost

Pricing verified against current AWS list rates for `us-east-1` (August 2026),
assuming continuous 24/7 operation for a full month.

| Item | Spec | Qty | $/mo |
|---|---|---:|---:|
| control-plane VM | `t3.small`, $0.0208/hr | 1 | $15.18 |
| worker VMs | `t3.small`, $0.0208/hr each | 2 | $30.37 |
| load balancer / elastic IP | none used — standard dynamic public IPs (free while attached; the accepted trade-off is a public IP change on stop/start, see `RUNBOOK.md`) | 0 | $0.00 |
| block storage (PVC) | k3s default `local-path` StorageClass — the Postgres 5Gi claim is carved from a worker node's existing root EBS volume, not a separately-provisioned/billed volume (confirmed via `kubectl get storageclass`) | 0 extra | $0.00 |
| block storage (root volumes) | default Ubuntu 22.04 AMI root volume per instance (gp3, $0.08/GB-mo) | 3 × ~8GB | ~$1.92 |
| object storage (Terraform state) | S3 standard, state file is KB-scale | 1 bucket | ~$0.01 |
| DNS / domain | `dpdns.org` free subdomain (DigitalPlat) + Cloudflare free-tier DNS | 1 | $0.00 |
| TLS certificate | Let's Encrypt, free | 1 | $0.00 |
| **Total** | | | **~$47.48** |

Not itemized above, effectively $0: DynamoDB lock table (created early on,
since replaced by S3-native locking via `use_lockfile`, table left unused
rather than deleted — negligible/free at this access pattern), data
transfer (all traffic volume is trivial for a dev-scale capstone).

## Compared to the single-server Compose+Portainer deploy

- That stack (1 VM running Docker Compose + Portainer, from the earlier
  MERN/Task-CRUD project this capstone builds on) costs roughly the price
  of **one** small instance — call it ~$15/month for an equivalent single
  `t3.small`, plus effectively the same ~$2 for its root volume: **~$17/month
  total**.
- This cluster costs **~$47/month** — roughly **2.8x** the single-server cost.
- **What the extra ~$30/month actually buys**: real multi-node self-healing
  (a node can be drained or lost and the app keeps serving, backed by
  `topologySpreadConstraints` + `PodDisruptionBudget` — not simulated, both
  verified live on this project); zero-downtime rolling deploys
  (`maxUnavailable: 0`); horizontal autoscaling under load
  (`HorizontalPodAutoscaler`, 2→5 backend replicas); and a real
  network-segmentation boundary (`NetworkPolicy` default-deny) that a
  single Docker host has no equivalent of.
- **When it's genuinely not worth it**: a hobby project, an internal tool
  with a handful of known users, or anything where a few minutes of
  downtime during a manual restart is a non-event rather than a real cost.
  The extra spend buys resilience against failure modes (node loss, traffic
  spikes, zero-downtime deploys) that only matter once real users or a real
  SLA are on the line — for this capstone specifically, the value is
  primarily educational, not operationally necessary at this traffic scale.

## How I'd halve this

The single biggest lever is **node count and size, not anything exotic**:
dropping from 3 nodes to 2 (1 control plane doubling as a workload node,
1 worker) would cut compute from ~$45.55/mo to ~$30.37/mo outright — k3s
supports this without any architecture change, just removing the taint (if
one were set) that would keep workloads off the control plane. Combined
with switching both remaining nodes from `t3.small` to `t3.micro`
($0.0104/hr vs $0.0208/hr — roughly half), compute alone would drop to
around **$15/month**, bringing the whole stack close to **$17/month total** —
similar to the single-server baseline, while keeping *some* multi-node
resilience (just less headroom for it). The trade-off: `topologySpreadConstraints`
becomes far less meaningful with only 2 nodes, and a `t3.micro`'s limited
CPU/memory would likely need the HPA's `maxReplicas` and resource requests
tuned down too, or backend pods would start getting evicted under normal
load rather than genuinely autoscaling.