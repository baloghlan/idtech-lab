# IDTECH Kubernetes Scenario Lab

A three-node Kubernetes portal provisioned with Ansible: an Nginx frontend, a Flask backend, and persistent Redis storage on NFS.

## Architecture

```text
Browser → NodePort :30080 → frontend-svc (idtech-frontend)
                              │ Nginx /api/ proxy
                              ▼
                    backend-svc (idtech-backend, ClusterIP :80)
                              │ Flask :5000
                              ▼
                    redis-headless :6379 → redis-0
                                              │ PVC
                                              ▼
                               nfs-idtech → master:/srv/nfs/k8s
```

| Node | IP | Purpose |
|---|---|---|
| master | 192.168.56.10 | Control plane, NFS server, local registry :5000 |
| worker1 | 192.168.56.11 | `tier=frontend`, `app=frontend:NoSchedule`, 2 frontend pods |
| worker2 | 192.168.56.12 | `tier=backend`, backend, Redis, healthcheck CronJob |

The `node-reporter` DaemonSet runs on both workers. The frontend uses required nodeAffinity and a toleration; the backend and Redis use nodeSelector. The backend has no externally exposed Service.

## Directory structure

```text
app/          Flask and Nginx source, Dockerfiles, and .dockerignore files
ansible/      Inventory, roles, and deployment playbooks
k8s/          Namespace, workload, storage, HPA, and RBAC manifests
scripts/      Incus VM provisioning script
screenshots/  Lab results
```

## Prerequisites

- Incus, KVM, and the `incusbr0` network. The provisioning script uses `images:ubuntu/22.04`.
- Ansible on the control machine and Docker or a compatible tool for building and pushing images.
- An `ubuntu` user with sudo and SSH access on each node. The configured key path is `~/.ssh/idtech_k8s`; host key checking is enabled.
- Network access from the nodes to package repositories and Helm chart sources.

Create the VMs from the project directory:

```bash
bash scripts/init-vms.sh
```

After distributing the SSH public key to the nodes:

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
ansible-galaxy collection install community.general
ansible k8s_cluster -m ping
ansible-playbook --syntax-check playbooks/site.yml
```

Node addresses appear in both `inventory/hosts.yml` and `inventory/group_vars/all.yml`; update both when changing environments. Some registry and NFS addresses also appear in manifests and role defaults.

## Deployment sequence

For a fresh installation, prepare the registry and Secret before deploying the application. Run these commands from `ansible/`:

```bash
ansible-playbook playbooks/prepare-nodes.yml
ansible-playbook playbooks/kubeadm-init.yml
ansible-playbook playbooks/install-cni.yml
ansible-playbook playbooks/kubeadm-join.yml
ansible-playbook playbooks/bootstrap.yml
ansible-playbook playbooks/configure-nodes.yml
ansible-playbook playbooks/deploy-base-resources.yml
ansible-playbook playbooks/deploy-registry.yml
ansible-playbook playbooks/install-helm.yml
ansible-playbook playbooks/deploy-nfs-provisioner.yml
ansible-playbook playbooks/install-sealed-secrets.yml
ansible-playbook playbooks/install-kubeseal.yml
```

### Images

Example build and push commands, run from the project directory:

```bash
docker build -t 192.168.56.10:5000/idtech-backend:1.0 app/backend
docker build -t 192.168.56.10:5000/idtech-frontend:1.0 app/frontend
docker push 192.168.56.10:5000/idtech-backend:1.0
docker push 192.168.56.10:5000/idtech-frontend:1.0
```

The registry uses HTTP. Configure the Docker daemon used for pushing to allow `192.168.56.10:5000` as an insecure registry. Ansible configures containerd on the nodes. The backend runs Gunicorn as the non-root user `appuser`. `APP_VERSION` is supplied at runtime through a ConfigMap; the current manifests use `1.0`. Build and push the `1.1` tag separately before deploying that release.

### Redis Secret

The committed `redis-sealed-secret.yaml` was encrypted for an existing controller key. A new cluster may be unable to decrypt it. Restore the matching controller key or seal the Secret again for the new controller.

Example workflow on the master, using Bash, `kubectl`, and `kubeseal`:

```bash
export KUBECONFIG=/etc/kubernetes/admin.conf
read -rs -p 'Redis password: ' REDIS_PASSWORD
printf '\n'
printf '%s' "$REDIS_PASSWORD" | kubectl create secret generic redis-secret \
  -n idtech-backend --from-file=REDIS_PASSWORD=/dev/stdin \
  --dry-run=client -o yaml | kubeseal \
  --controller-name sealed-secrets-controller \
  --controller-namespace sealed-secrets --format yaml \
  > /tmp/redis-sealed-secret.yaml
unset REDIS_PASSWORD
```

Copy the encrypted output to `k8s/backend/redis-sealed-secret.yaml` on the control machine. Keep plaintext Secrets out of Git.

Base64 in a Kubernetes Secret is reversible encoding, not encryption: decoding requires no key. A SealedSecret stores encrypted data that the controller decrypts with its private key. The backend reads the resulting Secret through `envFrom`, and Redis uses `secretKeyRef`.

Once the images and Secret are ready, run from `ansible/`:

```bash
ansible-playbook playbooks/site.yml
```

`site.yml` runs the infrastructure and application playbooks in sequence. Certificate provisioning is performed separately.

## Networking and configuration

Portal address: `http://192.168.56.11:30080`.

```bash
curl http://192.168.56.11:30080/health
curl http://192.168.56.11:30080/api/visits
curl http://192.168.56.11:30080/api/load
```

Nginx uses the FQDN `backend-svc.idtech-backend.svc.cluster.local`. Within a frontend pod, the short name `backend-svc` is initially resolved in its own namespace, `idtech-frontend`, while the backend Service belongs to `idtech-backend`.

The Nginx ConfigMap is mounted using `subPath`. Updating only that ConfigMap requires restarting the frontend pods. Backend variables supplied through `envFrom` are also read only when a new container starts.

The frontend quota allows 2 pods. Its rollout uses `maxSurge: 0` and `maxUnavailable: 1` to stay within that limit. The backend quota allows 15 pods, requests of 2 CPU/2Gi, and limits of 6 CPU/4Gi. Both namespaces define default requests of `50m/64Mi` and default limits of `200m/128Mi` per container.

## Operational checks

Run the following `kubectl` commands on the master with administrative access:

```bash
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl get nodes -o wide
kubectl get pods -n idtech-frontend -o wide
kubectl get pods -n idtech-backend -o wide
kubectl get pvc -n idtech-backend
kubectl get storageclass nfs-idtech
kubectl get daemonset node-reporter -n idtech-backend
kubectl get hpa backend-hpa -n idtech-backend
```

The backend init container waits for an authenticated Redis `PING` response. Both applications use `/health` for readiness and liveness probes. The backend `/health` endpoint does not check Redis health; use `/api/visits` to verify Redis connectivity.

### HPA

Metrics Server is installed. The backend HPA uses a minimum of 2 replicas, a maximum of 4, and a CPU utilization target of 60%. Generate a bounded load from another terminal:

```bash
seq 1 100 | xargs -P 8 -I{} curl -fsS -o /dev/null \
  http://192.168.56.11:30080/api/load
```

On the master, watch scaling with `kubectl get hpa backend-hpa -n idtech-backend -w`. Existing screenshots show 4 replicas under load and 2 replicas after the load ends.

### Redis persistence

Record the `/api/visits` response, run `kubectl delete pod redis-0 -n idtech-backend` on the master, and repeat the request after the replacement pod becomes Ready. The counter should remain above its previous value. Redis uses AOF and `volumeClaimTemplates` with a 1Gi PVC provisioned through the `nfs-idtech` StorageClass. The author reported completing this check manually; no separate screenshot is committed.

### Rolling update

After pushing a new image, update the image tag in the backend manifest, `APP_VERSION` in the ConfigMap, and the Deployment's `kubernetes.io/change-cause` annotation. Apply the changes with `ansible-playbook playbooks/deploy-backend.yml` from `ansible/`.

```bash
kubectl rollout status deployment/backend -n idtech-backend --timeout=180s
kubectl rollout history deployment/backend -n idtech-backend
```

The backend uses `maxUnavailable: 0` and `maxSurge: 1`. The current manifest annotation describes a rollback from `1.1` to `1.0`; live rollout history output is not committed. `kubectl rollout undo` does not revert the ConfigMap: align `APP_VERSION` during rollback and ensure pods start with the updated configuration.

### CronJob

`portal-healthcheck` requests the backend `/health` endpoint with `wget` every 5 minutes. To trigger a manual check:

```bash
kubectl create job "portal-healthcheck-manual-$(date +%s)" \
  --from=cronjob/portal-healthcheck -n idtech-backend
kubectl get jobs -n idtech-backend
```

## Certificates and RBAC

Run the certificate workflow separately from `ansible/`:

```bash
ansible-playbook playbooks/create-intern-csr.yml
ansible-playbook playbooks/approve-intern-csr.yml
ansible-playbook playbooks/configure-intern-kubeconfig.yml
ansible-playbook playbooks/deploy-rbac.yml
```

The workflow is: private key → CSR with `/CN=idtech-intern` → Kubernetes CSR named `idtech-intern-client` → approval → certificate → kubeconfig. The requested certificate validity is 86400 seconds; renewal is required after expiration. Existing key and CSR files are protected with `creates`; changing the CN of an existing CSR requires regenerating the CSR.

The kubeconfig is stored at `/etc/kubernetes/intern/intern.kubeconfig` on the master and references local certificate paths. Run these commands on the master as a user able to read those files:

```bash
export KUBECONFIG=/etc/kubernetes/intern/intern.kubeconfig
kubectl auth whoami
kubectl auth can-i get pods -n idtech-backend          # yes
kubectl auth can-i get services -n idtech-backend      # yes
kubectl auth can-i delete pods -n idtech-backend       # no
kubectl auth can-i get secrets -n idtech-backend       # no
kubectl auth can-i get pods -n idtech-frontend         # no
```

The Role also permits reading pod logs in the backend namespace. A `no` response returns exit code 1. The author confirmed successful verification; no separate output file is committed.

## Evidence and differences from the assignment

| Evidence | Coverage |
|---|---|
| [Virtual machines](screenshots/01.infra-virtual-machines.png) | Infrastructure |
| [Idempotency](screenshots/02.ansible-idempotency.png) | `common` tasks, rather than the complete `site.yml` |
| [Ready nodes](screenshots/03.kubernetes-nodes-ready.png) | Three Ready nodes |
| [HPA under load](screenshots/04.load-test.png) | 4 replicas |
| [HPA after load](screenshots/05.after-load-test.png) | 2 replicas |

- A local HTTP registry is retained instead of Docker Hub or GitLab Registry.
- IP addresses and all versions have not been consolidated exclusively into `group_vars`.
- A second run of the complete `site.yml` with `changed=0` has not been independently confirmed.
- Branch protection is a GitHub setting and cannot be verified from local files.
- The project is the `idtech-k8s-golive/` subdirectory within the `idtech-lab` repository.

## Git and release

Project stages were developed through feature branches and pull requests. The author confirmed that the corrections were merged into `main`. Commit format: `type(scope): description`.

After the documentation is included in `main`, create the release from the repository root:

```bash
git switch main
git tag -a v1.0.0 -m "IDTECH Kubernetes Scenario Lab v1.0.0"
git push origin v1.0.0
```

These commands are instructions. No tag was created or pushed while preparing this documentation.
