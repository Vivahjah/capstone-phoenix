# Architecture — Capstone Phoenix

## 1. Topology diagram

```
Internet ──DNS(A)──▶ taskapp.cognistack.dpdns.org
      │
      ▼
Traefik (k3s built-in Ingress, all 3 nodes)  ──TLS terminated, cert issued by cert-manager──┐
      │                                                                                      │
      │  path: /            path: /api                                                      │
      ▼                     ▼                                                                ▼
frontend Service      backend Service                                          Secret: taskapp-tls
(ClusterIP)           (ClusterIP)                                              (Let's Encrypt prod cert)
      │                     │
      ▼                     ▼
frontend Pods x2      backend Pods x2
(nodes: ip-10-0-1-100, (nodes: ip-10-0-1-100, ip-10-0-1-246 —
 ip-10-0-1-246 —        topologySpreadConstraints enforces
 topologySpreadConstraints  this split, verified via
 enforces this split)       `kubectl get pods -o wide`)
                              │
                              ▼
                       postgres Service (headless, clusterIP: None)
                              │
                              ▼
                       postgres-0 (StatefulSet, 1 replica)
                       PVC: postgres-storage, 5Gi, bound to
                       whichever node the pod is scheduled on
```

Control plane node (`ip-10-0-1-180`) runs the k3s API server, etcd, and
Argo CD — it does not run app workloads by taint/scheduling convention,
though nothing currently forbids it explicitly.

## 2. Node & network

- **Nodes**: 1 control plane + 2 workers, all `t3.small`, all in the same
  AZ (default subnet placement, `us-east-1`), all Ubuntu 22.04.
- **CIDR**: VPC `10.0.0.0/16`, single public subnet `10.0.1.0/24`. One
  subnet was sufficient for a 3-node dev/capstone cluster — no need for
  multi-AZ subnet splitting at this scale, and it keeps the Terraform
  `network` module simple.
- **Firewall** (AWS Security Group, defense-in-depth with UFW on each node):
  - Open to the world: `80`, `443` (app traffic + Let's Encrypt HTTP-01
    challenge — both need to be reachable from anywhere, including Let's
    Encrypt's validation servers, which don't have a fixed IP range to
    allowlist).
  - Restricted to the admin's current IP only: `22` (SSH), `6443`
    (k3s API server). `6443` open to `0.0.0.0/0` is an explicit auto-fail
    condition in this project's grading rubric — kept locked to a single
    IP for the entire build, updated each session as that IP rotates.
  - Internal only (self-referencing SG rule, not exposed externally):
    all traffic between the 3 nodes themselves (kubelet on `10250`,
    Calico's overlay networking, etcd on `2379`/`2380`).

## 3. Request flow

A browser resolves `taskapp.cognistack.dpdns.org` via DNS (Cloudflare,
"DNS only" — not proxied, so the record points directly at the control
plane's public IP rather than Cloudflare's edge) and connects over HTTPS.
Traefik terminates TLS using the certificate cert-manager obtained from
Let's Encrypt (stored in the `taskapp-tls` Secret) and routes by path:
`/` goes to the `frontend` Service (ClusterIP, port `80` → container port
`80`, nginx serving the built React app), `/api/*` goes to the `backend`
Service (ClusterIP, port `80` → container port `5000`, gunicorn running
the Flask app). The backend authenticates requests via JWT and talks to
Postgres over the `postgres` headless Service on port `5432`, resolved by
Kubernetes' internal DNS to whichever pod IP `postgres-0` currently has.

## 4. The single-server assumptions you fixed

| Single-server assumption | Why it breaks at scale | How you fixed it |
|---|---|---|
| migrate-on-boot in the entrypoint (`alembic upgrade head` runs every container start) | 2+ replicas race on the same migration on first boot | **Not fixed** — accepted as a known, documented trade-off. The backend's source/entrypoint is not modifiable for this project. Confirmed the race actually happens in practice: on first rollout, one backend pod's logs show `Running upgrade -> d5edfb30a373`, the other shows only `Will assume transactional DDL` with no upgrade line — no crash resulted, but it is a genuine, observed race, not a theoretical one. See `RUNBOOK.md`. |
| named volume on the host (`docker-compose` style bind mount) | Pods reschedule across nodes; a host-path volume wouldn't follow the pod | `StatefulSet` + `volumeClaimTemplates` gives each replica its own PVC and stable pod identity (`postgres-0`) — **but note a real, verified limitation**: this cluster's default `StorageClass` is k3s's bundled `local-path` (`rancher.io/local-path`), not a network-attached volume. Confirmed via `kubectl get storageclass` and `kubectl get pvc -o wide`: the PV carries a `nodeAffinity` tying it to the specific node it was first provisioned on (`ip-10-0-1-246`). A same-node pod restart correctly reattaches to the existing data (verified live: the probes-related rolling restart came back with 0 data loss) — but if that *node itself* were lost or drained, the data would not follow to a different node the way a true network-attached volume (e.g. the AWS EBS CSI driver) would. Installing and using the EBS CSI driver's `StorageClass` instead of `local-path` would close this gap; not done here, and worth flagging as a real trade-off rather than a fully solved problem. |
| `ports:` published directly on the host (`-p 5432:5432` style) | Many pods, many nodes, no single "the host" anymore; also, exposing Postgres's port on a node would defeat the whole point of network isolation | A `Service` (headless for Postgres, ClusterIP for backend/frontend) provides a stable internal address regardless of which node/IP a pod actually lands on; nothing about Postgres is exposed outside the cluster at all |
| single container = single point of failure | One process dying takes the whole app down | 2 replicas each for backend/frontend, spread across nodes via `topologySpreadConstraints`, backed by a `PodDisruptionBudget` (`minAvailable: 1`) so voluntary disruptions (node drains) can't take both down at once either |
| manual restart if something dies | No supervisor watching process health beyond "is it still running" | `livenessProbe`/`readinessProbe`/`startupProbe` on every workload, including Postgres via `pg_isready` — Kubernetes actively kills and restarts genuinely unhealthy containers, and pulls not-yet-ready ones out of Service rotation rather than routing traffic to them |
| deploy = stop the container, start the new one (real downtime) | Users see errors during every deploy | `RollingUpdate` strategy with `maxUnavailable: 0` / `maxSurge: 1` — a new pod must be healthy *before* an old one is removed, so capacity never drops during a rollout |
| secrets in a `.env` file sitting next to the code | Anyone with filesystem/git access sees plaintext credentials directly | Kubernetes `Secret` object, deliberately kept out of git entirely (not even encrypted-in-git) — real values exist only in the live cluster and on the operator's local machine, applied out-of-band from the GitOps flow |
| any request could hit anything on the box (no internal segmentation) | A compromised or misbehaving pod can reach anything else on the network by default | Default-deny `NetworkPolicy` at the namespace level, with explicit allow rules only for the traffic paths that are actually required (Traefik→app, app→Postgres, everything→DNS) |
| fixed capacity regardless of load | A traffic spike either overwhelms the single process or sits idle wasting resources at all other times | `HorizontalPodAutoscaler` on the backend, 2–5 replicas targeting 70% CPU utilization |

## 5. Choices & trade-offs

- **Raw YAML, not Helm or Kustomize** — at this project's scale (one app,
  one environment, no multi-environment templating need), raw manifests
  are more transparent for both learning and grading: every object is
  fully visible in one file, with no templating layer to mentally
  resolve. Helm/Kustomize would earn their complexity at a larger scale
  than this capstone operates at.
- **k3s Traefik, not ingress-nginx** — Traefik ships with k3s by default
  and was already running, healthy, before any Ingress-layer decision was
  made. Installing a second Ingress controller (ingress-nginx) alongside
  an already-working one would have been redundant complexity with no
  concrete benefit for this project's requirements.
- **CNI / NetworkPolicy enforcement** — Calico, not k3s's default Flannel.
  This isn't a preference — it's a hard requirement: Flannel does not
  enforce `NetworkPolicy` at all, so the entire default-deny/allow-list
  layer described above would silently do nothing under Flannel. k3s was
  explicitly installed with `--flannel-backend=none` for this reason.
- **Secrets approach: out-of-band, not Sealed Secrets or External
  Secrets** — the real `Secret` is applied manually via `kubectl` and
  deliberately excluded from git (see `.gitignore`), rather than using a
  tool like Sealed Secrets or an external secrets manager (Vault, AWS
  Secrets Manager). This was a scope decision for the project's size: a
  single Secret object, one operator, one environment. Sealed
  Secrets/External Secrets would be the correct next step for a team
  environment or multiple environments, but add real operational
  overhead (a controller to run, a KMS/Vault dependency) that isn't
  justified here. This choice also directly caused a real incident
  during the Argo CD setup — documented in full in `RUNBOOK.md` — where
  a same-named example file in the synced manifests directory
  overwrote, and Argo CD's `prune` then deleted, the real Secret.