# SecureFlow DevSecOps Platform — Step-by-Step Setup & Reproduction Guide

This guide provides the complete sequence of commands (in both **PowerShell** and **Bash**) to deploy, test, harden, and verify every layer of the **SecureFlow** DevSecOps platform locally and in Kubernetes.

---

## Prerequisites

Ensure the following tools are installed on your workstation:
* **Docker Desktop** (with Docker Compose v2)
* **Git** & **Python 3.10+** (`pip install git-filter-repo checkov`)
* **kubectl**, **kind** (Kubernetes in Docker), and **Helm v3**
* **Trivy CLI** & **Cosign CLI** (optional locally; automated in GitHub Actions)

---

## Step 1: Clone the Repository & Run with Docker Compose

**PowerShell:**
```powershell
git clone https://github.com/ch1n4x4/SecureFlow-VulnerableCodebase.git
Set-Location .\SecureFlow-VulnerableCodebase

# Build and start all 5 containers
docker compose up -d --build

# Verify health endpoints on ports 5000, 5001, and 5002
Invoke-RestMethod -Uri "http://localhost:5000/health"
Invoke-RestMethod -Uri "http://localhost:5001/health"
Invoke-RestMethod -Uri "http://localhost:5002/health"
```

**Bash:**
```bash
git clone https://github.com/ch1n4x4/SecureFlow-VulnerableCodebase.git
cd SecureFlow-VulnerableCodebase

# Build and start all 5 containers
docker compose up -d --build

# Verify health endpoints on ports 5000, 5001, and 5002
curl -s http://localhost:5000/health
curl -s http://localhost:5001/health
curl -s http://localhost:5002/health
```

---

## Step 2: Run Local Security Scanners (Pre-Flight Verification)

Verify that **Gitleaks**, **Trivy (Images & K8s)**, **Checkov (Terraform IaC)**, and the **Differentiated Security Gate (`security-gate.sh`)** pass locally before pushing.

**PowerShell:**
```powershell
# 1. Stage 1: Gitleaks full Git history scan
docker run --rm -v "${PWD}:/repo" zricethezav/gitleaks:latest `
  detect --source=/repo --config=/repo/.gitleaks.toml --log-opts="--all" --verbose

# 2. Stage 3: Trivy Container Image Scan (0 blocking CRITICAL CVEs)
foreach ($svc in @("auth-service", "transaction-service", "frontend")) {
  docker build -t "secureflow/${svc}:v1.0.0" "./services/${svc}"
  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v "${PWD}:/repo" `
    aquasec/trivy:latest image --ignorefile /repo/.trivyignore --ignore-unfixed `
    --severity CRITICAL --exit-code 1 "secureflow/${svc}:v1.0.0"
}

# 3. Stage 4: Trivy Kubernetes Manifest Scan & Checkov Terraform Scan
docker run --rm -v "${PWD}:/repo" aquasec/trivy:latest config /repo/infra/kubernetes/base --severity CRITICAL,HIGH --exit-code 1
docker run --rm -v "${PWD}:/repo" bridgecrew/checkov --config-file /repo/.checkov.yaml
```

**Bash:**
```bash
# 1. Stage 1: Gitleaks full Git history scan
docker run --rm -v "$(pwd):/repo" zricethezav/gitleaks:latest \
  detect --source=/repo --config=/repo/.gitleaks.toml --log-opts="--all" --verbose

# 2. Stage 3: Trivy Container Image Scan (0 blocking CRITICAL CVEs)
for svc in auth-service transaction-service frontend; do
  docker build -t "secureflow/${svc}:v1.0.0" "./services/${svc}"
  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v "$(pwd):/repo" \
    aquasec/trivy:latest image --ignorefile /repo/.trivyignore --ignore-unfixed \
    --severity CRITICAL --exit-code 1 "secureflow/${svc}:v1.0.0"
done

# 3. Stage 4: Trivy Kubernetes Manifest Scan & Checkov Terraform Scan
docker run --rm -v "$(pwd):/repo" aquasec/trivy:latest config /repo/infra/kubernetes/base --severity CRITICAL,HIGH --exit-code 1
docker run --rm -v "$(pwd):/repo" bridgecrew/checkov --config-file /repo/.checkov.yaml
```

---

## Step 3: Create Local Kubernetes Cluster (`kind`) & Install OPA Gatekeeper

**PowerShell:**
```powershell
# 1. Create kind cluster and load built service images
kind create cluster --name secureflow
kind load docker-image secureflow/auth-service:v1.0.0 --name secureflow
kind load docker-image secureflow/transaction-service:v1.0.0 --name secureflow
kind load docker-image secureflow/frontend:v1.0.0 --name secureflow

# 2. Install OPA Gatekeeper via Helm
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
helm repo update
helm upgrade --install gatekeeper gatekeeper/gatekeeper `
  --namespace gatekeeper-system --create-namespace --wait

# 3. Apply the 4 ConstraintTemplates and Constraints
kubectl apply -f .\gatekeeper-policies.yaml
kubectl get constrainttemplates
kubectl get constraints
```

**Bash:**
```bash
# 1. Create kind cluster and load built service images
kind create cluster --name secureflow
kind load docker-image secureflow/auth-service:v1.0.0 --name secureflow
kind load docker-image secureflow/transaction-service:v1.0.0 --name secureflow
kind load docker-image secureflow/frontend:v1.0.0 --name secureflow

# 2. Install OPA Gatekeeper via Helm
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
helm repo update
helm upgrade --install gatekeeper gatekeeper/gatekeeper \
  --namespace gatekeeper-system --create-namespace --wait

# 3. Apply the 4 ConstraintTemplates and Constraints
kubectl apply -f gatekeeper-policies.yaml
kubectl get constrainttemplates
kubectl get constraints
```

---

## Step 4: Deploy HashiCorp Vault & Configure Per-Service Secret Injection

**PowerShell:**
```powershell
# 1. Install HashiCorp Vault in dev mode with Agent Injector enabled
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
helm upgrade --install vault hashicorp/vault `
  --namespace vault --create-namespace `
  --set "server.dev.enabled=true" `
  --set "injector.enabled=true"

kubectl wait --for=condition=Ready pod/vault-0 -n vault --timeout=120s

# 2. Enable file audit logging and KV-v2 secrets engine at 'secureflow/'
kubectl exec -n vault vault-0 -- vault audit enable file file_path=/tmp/vault_audit.log
kubectl exec -n vault vault-0 -- vault secrets enable -path=secureflow kv-v2

# 3. Store rotated per-service secrets in Vault
kubectl exec -n vault vault-0 -- vault kv put secureflow/auth-service `
  DB_PASSWORD="RotatedAuthDbPass_2026!Secure" `
  JWT_SECRET="RotatedJwtSigningKey_2026_HighEntropy99!"

kubectl exec -n vault vault-0 -- vault kv put secureflow/transaction-service `
  DB_PASSWORD="RotatedTxDbPass_2026!Secure"

kubectl exec -n vault vault-0 -- vault kv put secureflow/frontend `
  SESSION_SECRET="RotatedFlaskSessionSecret_2026!Secure"

# 4. Copy and apply per-service HCL policies
kubectl cp .\infra\kubernetes\vault\policies\auth-service-policy.hcl vault/vault-0:/tmp/auth-service-policy.hcl
kubectl cp .\infra\kubernetes\vault\policies\transaction-service-policy.hcl vault/vault-0:/tmp/transaction-service-policy.hcl
kubectl cp .\infra\kubernetes\vault\policies\frontend-policy.hcl vault/vault-0:/tmp/frontend-policy.hcl

kubectl exec -n vault vault-0 -- vault policy write auth-service /tmp/auth-service-policy.hcl
kubectl exec -n vault vault-0 -- vault policy write transaction-service /tmp/transaction-service-policy.hcl
kubectl exec -n vault vault-0 -- vault policy write frontend /tmp/frontend-policy.hcl

# 5. Enable Kubernetes authentication and bind ServiceAccounts
kubectl exec -n vault vault-0 -- vault auth enable kubernetes
kubectl exec -n vault vault-0 -- sh -c 'vault write auth/kubernetes/config \
  kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
  token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
  disable_iss_validation=true'

foreach ($svc in @("auth-service", "transaction-service", "frontend")) {
  kubectl exec -n vault vault-0 -- vault write "auth/kubernetes/role/${svc}" `
    "bound_service_account_names=${svc}" `
    bound_service_account_namespaces=secureflow `
    "policies=${svc}" `
    ttl=24h
}
```

**Bash:**
```bash
# 1. Install HashiCorp Vault in dev mode with Agent Injector enabled
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
helm upgrade --install vault hashicorp/vault \
  --namespace vault --create-namespace \
  --set "server.dev.enabled=true" \
  --set "injector.enabled=true"

kubectl wait --for=condition=Ready pod/vault-0 -n vault --timeout=120s

# 2. Enable file audit logging and KV-v2 secrets engine at 'secureflow/'
kubectl exec -n vault vault-0 -- vault audit enable file file_path=/tmp/vault_audit.log
kubectl exec -n vault vault-0 -- vault secrets enable -path=secureflow kv-v2

# 3. Store rotated per-service secrets in Vault
kubectl exec -n vault vault-0 -- vault kv put secureflow/auth-service \
  DB_PASSWORD="RotatedAuthDbPass_2026!Secure" \
  JWT_SECRET="RotatedJwtSigningKey_2026_HighEntropy99!"

kubectl exec -n vault vault-0 -- vault kv put secureflow/transaction-service \
  DB_PASSWORD="RotatedTxDbPass_2026!Secure"

kubectl exec -n vault vault-0 -- vault kv put secureflow/frontend \
  SESSION_SECRET="RotatedFlaskSessionSecret_2026!Secure"

# 4. Copy and apply per-service HCL policies
kubectl cp infra/kubernetes/vault/policies/auth-service-policy.hcl vault/vault-0:/tmp/auth-service-policy.hcl
kubectl cp infra/kubernetes/vault/policies/transaction-service-policy.hcl vault/vault-0:/tmp/transaction-service-policy.hcl
kubectl cp infra/kubernetes/vault/policies/frontend-policy.hcl vault/vault-0:/tmp/frontend-policy.hcl

kubectl exec -n vault vault-0 -- vault policy write auth-service /tmp/auth-service-policy.hcl
kubectl exec -n vault vault-0 -- vault policy write transaction-service /tmp/transaction-service-policy.hcl
kubectl exec -n vault vault-0 -- vault policy write frontend /tmp/frontend-policy.hcl

# 5. Enable Kubernetes authentication and bind ServiceAccounts
kubectl exec -n vault vault-0 -- vault auth enable kubernetes
kubectl exec -n vault vault-0 -- sh -c 'vault write auth/kubernetes/config \
  kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
  token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
  disable_iss_validation=true'

for svc in auth-service transaction-service frontend; do
  kubectl exec -n vault vault-0 -- vault write "auth/kubernetes/role/${svc}" \
    "bound_service_account_names=${svc}" \
    bound_service_account_namespaces=secureflow \
    "policies=${svc}" \
    ttl=24h
done
```

---

## Step 5: Deploy Hardened Kubernetes Manifests & Verify Vault + Gatekeeper

**PowerShell:**
```powershell
# 1. Apply all hardened manifests and NetworkPolicies via Kustomize
kubectl apply -k .\infra\kubernetes\base
kubectl get pods -n secureflow
kubectl get constraint --all-namespaces

# 2. Confirm secrets are mounted as files in /vault/secrets/ and NOT in env vars
$AUTH_POD = kubectl get pod -n secureflow -l svc=auth-service -o jsonpath="{.items[0].metadata.name}"
kubectl exec -n secureflow $AUTH_POD -c auth-service -- cat /vault/secrets/config
kubectl describe pod $AUTH_POD -n secureflow
```

**Bash:**
```bash
# 1. Apply all hardened manifests and NetworkPolicies via Kustomize
kubectl apply -k infra/kubernetes/base
kubectl get pods -n secureflow
kubectl get constraint --all-namespaces

# 2. Confirm secrets are mounted as files in /vault/secrets/ and NOT in env vars
AUTH_POD=$(kubectl get pod -n secureflow -l svc=auth-service -o jsonpath="{.items[0].metadata.name}")
kubectl exec -n secureflow "$AUTH_POD" -c auth-service -- cat /vault/secrets/config
kubectl describe pod "$AUTH_POD" -n secureflow
```

---

## Step 6: Deploy Falco Runtime Security & Trigger Test Alerts

**PowerShell:**
```powershell
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update
helm upgrade --install falco falcosecurity/falco `
  --namespace falco --create-namespace `
  -f .\infra\kubernetes\falco\custom-rules.yaml

kubectl rollout status daemonset/falco -n falco --timeout=120s

$AUTH_POD = kubectl get pod -n secureflow -l svc=auth-service -o jsonpath="{.items[0].metadata.name}"
kubectl exec -n secureflow $AUTH_POD -c auth-service -- /bin/sh -c "id"
kubectl exec -n secureflow $AUTH_POD -c auth-service -- /bin/sh -c "cat /etc/shadow || true"
kubectl exec -n secureflow $AUTH_POD -c auth-service -- python -c "import urllib.request; urllib.request.urlopen('http://93.184.216.34:80', timeout=2)" 2>$null
kubectl exec -n secureflow $AUTH_POD -c auth-service -- /bin/sh -c "apt-get update || true"

kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=100 | Select-String "SECUREFLOW-RUNTIME"
```

**Bash:**
```bash
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update
helm upgrade --install falco falcosecurity/falco \
  --namespace falco --create-namespace \
  -f infra/kubernetes/falco/custom-rules.yaml

kubectl rollout status daemonset/falco -n falco --timeout=120s

AUTH_POD=$(kubectl get pod -n secureflow -l svc=auth-service -o jsonpath="{.items[0].metadata.name}")
kubectl exec -n secureflow "$AUTH_POD" -c auth-service -- /bin/sh -c "id"
kubectl exec -n secureflow "$AUTH_POD" -c auth-service -- /bin/sh -c "cat /etc/shadow || true"
kubectl exec -n secureflow "$AUTH_POD" -c auth-service -- python -c "import urllib.request; urllib.request.urlopen('http://93.184.216.34:80', timeout=2)" || true
kubectl exec -n secureflow "$AUTH_POD" -c auth-service -- /bin/sh -c "apt-get update || true"

kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=100 | grep "SECUREFLOW-RUNTIME"
```

---

## Step 7: Deploy Prometheus, Loki, Pushgateway & the 8-Panel Grafana Dashboard

**PowerShell:**
```powershell
# 1. Deploy the Observability stack and dashboard ConfigMap
kubectl apply -f .\infra\kubernetes\observability\observability-stack.yaml
kubectl create configmap secureflow-security-dashboard `
  --from-file=secureflow-dashboard.json=.\infra\kubernetes\observability\grafana-security-dashboard.json `
  -n observability --dry-run=client -o yaml | kubectl apply -f -
kubectl label configmap secureflow-security-dashboard grafana_dashboard="1" -n observability --overwrite

kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=grafana -n observability --timeout=180s
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=prometheus-pushgateway -n observability --timeout=120s

# 2. Port-forward Grafana to http://localhost:3000 (Login: admin / admin)
kubectl port-forward -n observability svc/monitoring-grafana 3000:80
```

**Bash:**
```bash
# 1. Deploy the Observability stack and dashboard ConfigMap
kubectl apply -f infra/kubernetes/observability/observability-stack.yaml
kubectl create configmap secureflow-security-dashboard \
  --from-file=secureflow-dashboard.json=infra/kubernetes/observability/grafana-security-dashboard.json \
  -n observability --dry-run=client -o yaml | kubectl apply -f -
kubectl label configmap secureflow-security-dashboard grafana_dashboard="1" -n observability --overwrite

kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=grafana -n observability --timeout=180s
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=prometheus-pushgateway -n observability --timeout=120s

# 2. Port-forward Grafana to http://localhost:3000 (Login: admin / admin)
kubectl port-forward -n observability svc/monitoring-grafana 3000:80
```