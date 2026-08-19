# Runbook — Capstone Phoenix

## Provision from zero

```bash
# 1. infra
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars   # then fill in real values:
#   my_ip (curl ifconfig.me), key_pair_name/ssh_public_key_path, project_name
terraform init
terraform apply   # review the plan before typing yes — 16 resources on a clean apply

# 2. cluster
cd ../ansible
# ansible.cfg already points at inventory.ini and roles_path=roles.
# inventory.ini must have the real IPs from `terraform output` (control_plane_public_ip,
# worker_public_ips) filled in under [server]/[agents] before this will connect.
ansible-playbook playbooks/site.yml
# Runs hardening → k3s-server → k3s-agent → kubeconfig, in that fixed order (Ansible has
# no dependency graph between roles — order is whatever the playbook lists).
# NOTE: the kubeconfig role's `fetch` OVERWRITES ~/.kube/config wholesale, not a merge.
# If you already have other clusters configured locally, back up ~/.kube/config first.

# 3. CNI (manual — deliberately not in Ansible, see ARCHITECTURE.md)
ssh -i ~/.ssh/capstone-phoenix-key ubuntu@<control_plane_public_ip>
sudo k3s kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.1/manifests/calico.yaml
# exit back out, then confirm from local machine:
kubectl get nodes   # expect all 3 Ready within ~60s of Calico applying

# 4. platform (ingress is already live — Traefik ships with k3s)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.20.1/cert-manager.yaml
kubectl get pods -n cert-manager   # expect 3/3 Running before continuing
kubectl apply -f manifests/cluster-issuer.yaml   # edit the email field first
kubectl get clusterissuer letsencrypt-prod       # expect READY: True

kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl get pods -n argocd   # expect 7 pods Running

# metrics-server: no action needed, k3s bundles it by default —
# confirm with `kubectl get deployment metrics-server -n kube-system`

# 5. the one thing that stays outside GitOps, on purpose (see "Secrets" below)
cp manifests/backend-secret.example.yaml manifests/backend-secret.yaml   # not committed
# edit manifests/backend-secret.yaml with real generated values, then:
kubectl apply -f manifests/backend-secret.yaml

# 6. GitOps takes over for everything else
kubectl apply -f gitops/application.yaml
kubectl get application taskapp -n argocd   # expect Synced / Healthy within ~1-2 min
```

## Day-2 operations

- **Scale a tier:** edit `replicas:` in `manifests/backend-deployment.yaml` (or
  `frontend-deployment.yaml`), commit, push. Do **not** `kubectl scale` directly —
  Argo CD's `selfHeal: true` will revert a manual scale back to whatever git says
  within its next reconcile pass (confirmed live: scaling backend to 1 replica by
  hand, Argo CD spun a second pod back up on its own within seconds, no
  intervention needed).

- **Roll back a bad deploy:** `git revert <bad-commit>` and push — Argo CD syncs
  the reverted state automatically. Alternatively, the Argo CD UI's History tab
  lets you select a previous synced revision and roll back directly from there
  without a new commit, useful if git access is briefly unavailable.

- **Run a new migration safely:** the backend's entrypoint runs
  `alembic upgrade head` on every pod start (see the documented migration-race
  trade-off in `ARCHITECTURE.md` — source is not modifiable for this project).
  To minimize risk when deploying a change that includes a new migration:
  temporarily scale the backend to 1 replica *before* the new image rolls out
  (via the git-commit method above), let the single pod apply the migration
  cleanly, then scale back to 2. This isn't automatic — it's a manual
  precaution to take before migration-bearing deploys specifically.

- **Rotate a secret:** edit `manifests/backend-secret.yaml` locally (real
  values, gitignored — never committed), then `kubectl apply -f
  manifests/backend-secret.yaml` directly. This is intentionally the one
  legitimate exception to "no manual kubectl apply" — the real Secret is
  deliberately kept outside git (see `ARCHITECTURE.md` §5), so it can't flow
  through the normal GitOps path. After rotating, run
  `kubectl rollout restart deployment backend -n taskapp` — env vars are only
  read at container start, so already-running pods won't pick up a rotated
  secret on their own.

## Failure recovery

- **A worker node dies / is drained:**
  ```bash
  kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
  ```
  Pods on that node terminate; the Deployment controller reschedules them on a
  remaining node. `topologySpreadConstraints` influences placement of the new
  pod, and the `PodDisruptionBudget` (`minAvailable: 1`) guarantees the drain
  itself can't be forced through if it would take a service to zero replicas.
  Expected recovery: well under a minute — new pod scheduling plus the
  `startupProbe`'s grace period before it's marked ready and added back to the
  Service.

- **A backend Pod crashloops:**
  ```bash
  kubectl logs <pod-name> -n taskapp --previous   # the crashed container's own logs
  kubectl describe pod <pod-name> -n taskapp       # Events section — often shows
                                                     # probe failures or scheduling issues
                                                     # logs alone won't show
  ```
  Real example encountered on this project: a backend pod crash-looped with
  `password authentication failed for user "REPLACE_ME_locally_never_commit"`
  — `--previous` logs immediately pointed at a Secret problem, not an app bug.
  Full incident writeup below.

- **A bad migration:** no automated rollback exists for this project (no
  scheduled Postgres backups/snapshots are configured — a known gap, not an
  oversight worth hiding). Manual recovery: `kubectl exec -it postgres-0 -n
  taskapp -- psql -U <user> -d taskapp` to inspect state directly, or exec into
  a backend pod and run `alembic downgrade -1` if the migration is a clean,
  reversible one.

- **Postgres Pod is rescheduled — prove the PVC re-attaches and data is
  intact:** demonstrated live on this project — adding `pg_isready` probes
  to the StatefulSet forced a rolling restart of `postgres-0`. The pod
  terminated and came back with the **same name** (`postgres-0`, not a new
  suffix), `RESTARTS: 0`, ready within 6 seconds, and a browser login
  afterward confirmed every previously-created task was still present.
  **Important caveat, verified via `kubectl get storageclass`:** this
  cluster's default `StorageClass` is k3s's bundled `local-path`
  (`rancher.io/local-path`), which ties the underlying PV to the specific
  node it was first provisioned on (`nodeAffinity`) rather than being a
  true network-attached volume. The test above proves data survives a
  same-node pod restart — it does **not** prove data would survive that
  node being lost or drained entirely, which a real network-attached
  volume (e.g. via the AWS EBS CSI driver) would guarantee and `local-path`
  does not. Documented as a known limitation, not fixed in this project.

## Documented incident — Argo CD pruned the real Secret

**What happened:** `manifests/backend-secret.example.yaml` (a safe,
placeholder-only template meant for the grader/teammates to see the Secret's
shape) originally had `metadata.name: backend-secret` — the exact same name
as the real Secret. `.gitignore` correctly kept the *real* `backend-secret.yaml`
out of git, but had no effect on the *example* file, which was legitimately
committed and sitting inside `manifests/` — the exact directory Argo CD syncs.
Argo CD doesn't consult `.gitignore` at all; it applies whatever YAML objects
physically exist in its watched path. It saw a `Secret` named `backend-secret`
in git, applied it, and overwrote the real credentials with the placeholder
text `REPLACE_ME_locally_never_commit`. `selfHeal: true` then kept
re-enforcing that placeholder state. Backend pods began crash-looping on
Postgres auth failures immediately after.

**Compounding issue:** moving the example file out of `manifests/` fixed the
name collision, but `prune: true` then **deleted the Secret entirely** — Argo
CD had "adopted" it as a tracked resource during the bad sync, and once no
object with that name existed anywhere in git, pruning removed it rather than
just leaving it alone.

**Fix:**
1. Moved the example file to `docs/backend-secret.example.yaml` — permanently
   outside any path Argo CD watches, not just renamed.
2. Recreated the real Secret via `kubectl apply -f manifests/backend-secret.yaml`.
3. Set `prune: false` in `gitops/application.yaml` — accepted going forward,
   since this project intentionally keeps one real Secret out-of-band from
   git; `selfHeal: true` was kept, since it still provides real value for
   every resource that *is* tracked in git.

**Lesson:** GitOps tooling operates on "what's physically in the watched git
path," completely independent of `.gitignore`, build tooling, or intent.
Anything with the same `kind`+`name`+`namespace` as a real, sensitive
resource is a live collision risk the moment it's committed anywhere inside
the synced path — regardless of whether it's "just an example."

## Documented incident — rolling updates weren't actually zero-downtime

**What happened:** while capturing evidence for `EVIDENCE/zero-downtime.log`,
a continuous request loop (1/sec, 3s timeout) against the live app during a
`kubectl rollout restart deployment/frontend` showed real failures —
`502`s and connection-refused (`000`) responses clustered in two tight
bursts, each landing right where you'd expect the two sequential pod
terminations of a 2-replica rollout to happen. `maxUnavailable: 0` /
`maxSurge: 1` alone did not guarantee the zero-downtime behavior it was
assumed to provide.

**Root cause:** a real, well-documented Kubernetes gap between two layers
that don't update in perfect lockstep — the Deployment controller's own
bookkeeping (which `maxUnavailable`/`maxSurge` govern) versus the Service's
list of valid endpoints (propagated via kube-proxy, consumed by Traefik).
When a pod receives `SIGTERM`, it can stop accepting connections almost
immediately, but the Service/Ingress layer takes a brief moment to notice
and stop routing to it — traffic can land on an already-dying pod in that
window.

**Fix:** added a `lifecycle.preStop` hook (`sleep 5`) to both the backend
and frontend Deployments. This delays actual container shutdown after
`SIGTERM` long enough for the Service/Ingress layer to catch up and stop
routing to the pod first — a manifest-level fix, not an application source
change. Re-ran the identical test after the fix: 90/90 requests returned
`200`, zero failures, across the same rollout window that previously
showed real errors.

**How it was found:** not caught by inspecting the manifest — only surfaced
by actually running a live rollout under continuous load while capturing
evidence, rather than assuming `maxUnavailable: 0` was sufficient on its
own. The operator independently noticed the failures consistently
coincided with running the rollout command, before being told the
diagnosis — confirming the pattern was real, not incidental network noise.

**Lesson:** the manifest settings that *look* like they guarantee
zero-downtime (`maxUnavailable: 0`) address only one layer of the problem.
Actually proving zero-downtime requires testing under real, concurrent
load during a real rollout — not just reasoning about what the settings
should theoretically do.