# SecureFlow DevSecOps — Troubleshooting & Operational Runbook

This runbook documents the root causes and verified fixes for every technical issue encountered across Docker Compose, GitHub Actions, Gitleaks, Trivy, Checkov, OPA Gatekeeper, HashiCorp Vault, and Prometheus Pushgateway.

---

## 1. Docker Compose: `postgres:14` SHA256 Digest Not Found & Obsolete `version` Warning

### Symptom
```text
WARN[0000] docker-compose.yml: the attribute `version` is obsolete
Error response from daemon: failed to resolve reference "docker.io/library/postgres@sha256:88fb66...": not found
```

### Root Cause
1. Docker Compose v2 deprecates the top-level `version: "3.8"` key.
2. The initial placeholder SHA256 digest did not match a live manifest digest on Docker Hub.

### Resolution
Pull `postgres:14`, inspect its live `RepoDigests` hash (`sha256:34afac84a15415ebec6271fa9615e7dfbf96e1aa9783f1af527b7d3fd933f1f2`), remove `version: "3.8"`, and pin the live digest in `docker-compose.yml` and `infra/kubernetes/base/databases.yaml`.

**PowerShell:**
```powershell
docker pull postgres:14
$PG_DIGEST = (docker inspect --format='{{index .RepoDigests 0}}' postgres:14).Split('@')[1]
Write-Host "Live Digest: $PG_DIGEST"
```

**Bash:**
```bash
docker pull postgres:14
PG_DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' postgres:14 | cut -d'@' -f2)
echo "Live Digest: $PG_DIGEST"
```

---

## 2. GitHub Actions: `aquasecurity/setup-trivy@v0.2.2` Returns 404 Not Found

### Symptom
```text
Error: Unable to resolve action `aquasecurity/setup-trivy@v0.2.2`, unable to find version `v0.2.2`
```

### Root Cause
The `aquasecurity/setup-trivy` repository does not publish a `v0.2.2` tag.

### Resolution
Update all three occurrences in `.github/workflows/devsecops-pipeline.yml` (Stage 3, Stage 4, and Stage 6) to `@v0.2.6`.

---

## 3. Stage 1 (Gitleaks): False Positive on Terraform `db_password = var.db_password`

### Symptom
`gitleaks-report.json` fails Stage 1 on `infra/terraform/main.tf` line 72:
```json
{
  "RuleID": "postgres-connection-string",
  "Match": "db_password = var.db_password",
  "Secret": "var.db_password"
}
```

### Root Cause
The custom rule `postgres-connection-string` in `.gitleaks.toml` matches any assignment to `db_password = ...`, and the global `[allowlist]` did not exclude Terraform input variable references (`var.*`).

### Resolution
Add `var\.[a-zA-Z0-9_]+` and `\$\{[a-zA-Z0-9_]+` to the `[allowlist]` regexes in `.gitleaks.toml`:
```toml
[allowlist]
description = "Global allowlist for SecureFlow"
regexTarget = "line"
regexes = [
    '''secrets\.[a-zA-Z0-9_]+''',
    '''os\.getenv\(''',
    '''\$\{SONAR_TOKEN\}''',
    '''var\.[a-zA-Z0-9_]+''',
    '''\$\{[a-zA-Z0-9_]+'''
]
```

---

## 4. Stage 3 (Trivy Image Scan): Debian 13 OS Packages & `PyJWT==2.8.0` CVEs

### Symptom
1. First run: Trivy flagged 8 `HIGH` CVEs in Debian 13.6 packages (`gzip`, `libpcre2-8-0`, `libsqlite3-0`, `openssl`) with `"Status": "fixed"`.
2. Second run: After patching OS packages, Trivy flagged `CRITICAL` and `HIGH` CVEs in `PyJWT==2.8.0` (`CVE-2026-102268`, `GHSA-pxh4-856f-4h89`, `CVE-2026-102267`, `CVE-2026-102271`).

### Root Cause
1. Base image layers contained unupgraded Debian packages prior to building the container.
2. `services/auth-service/requirements.txt` pinned `PyJWT==2.8.0` instead of the patched `PyJWT==2.14.0` release.

### Resolution
1. Add `RUN apt-get update && apt-get dist-upgrade -y --no-install-recommends && rm -rf /var/lib/apt/lists/*` to all three `Dockerfile`s.
2. Upgrade `PyJWT==2.14.0` in `services/auth-service/requirements.txt` and `requests==2.34.2` in `transaction-service` and `frontend`.
3. Track accepted/mitigated upstream advisories in `.trivyignore`.

---

## 5. Stage 4 (Trivy K8s Scan): `KSV-0014` (`readOnlyRootFilesystem`) on `databases.yaml`

### Symptom
`trivy-k8s-report.json` reported 2 `HIGH` failures on `infra/kubernetes/base/databases.yaml`:
```text
KSV-0014: Container 'postgres' of Deployment 'auth-db' should set 'securityContext.readOnlyRootFilesystem' to true
KSV-0014: Container 'postgres' of Deployment 'transaction-db' should set 'securityContext.readOnlyRootFilesystem' to true
```

### Root Cause
`auth-service`, `transaction-service`, and `frontend` had `readOnlyRootFilesystem: true`, but `auth-db` and `transaction-db` omitted it because PostgreSQL writes runtime lock/socket files to `/var/run/postgresql`, `/tmp`, and `/var/lib/postgresql/data`.

### Resolution
Set `readOnlyRootFilesystem: true` on both `postgres` containers in `databases.yaml` and mount writable `emptyDir` volumes at `/var/lib/postgresql/data`, `/var/run/postgresql`, and `/tmp`.

---

## 6. Stage 5 (`security-gate.sh`): Windows CRLF (`\r\n`) Line Ending Failure on Linux Runners

### Symptom
```text
/usr/bin/env: ‘bash\r’: No such file or directory
```

### Root Cause
Editing shell scripts on Windows introduces carriage returns (`\r\n`), which breaks the Linux shebang interpreter on `ubuntu-latest` GitHub Actions runners.

### Resolution
1. Commit `.gitattributes` enforcing `* text=auto` and `*.sh text eol=lf`.
2. Add `sed -i 's/\r$//' pipeline/scripts/security-gate.sh` in Stage 5 of `.github/workflows/devsecops-pipeline.yml`.

---

## 7. Observability: Prometheus Pushgateway `HTTP/1.1 400 Bad Request` & `sh` Backquote Error

### Symptom
```text
wget: server returned error: HTTP/1.1 400 Bad Request
sh: syntax error: EOF in backquote substitution
```

### Root Cause
1. BusyBox `wget` inside the Pushgateway container does not interpret `--post-data="@-"` as `stdin`.
2. PowerShell single-quoted strings pass literal backticks (`` `n ``) into Linux `sh`, which `sh` interprets as unclosed command substitution, and Windows CRLF (`\r\n`) line endings are rejected by Prometheus Pushgateway.

### Resolution
Strip `\r` inside the container using `tr -d "\r"` and push via port-forward or `--post-file`:

**PowerShell:**
```powershell
$PF_JOB = Start-Job -ScriptBlock { kubectl port-forward -n observability svc/prometheus-pushgateway 9091:9091 }
Start-Sleep -Seconds 3
$CLEAN_PAYLOAD = ($METRICS_PAYLOAD -replace "`r", "") + "`n"
Invoke-RestMethod -Method Post -Uri "http://localhost:9091/metrics/job/secureflow_devsecops" -Body $CLEAN_PAYLOAD -ContentType "text/plain"
Stop-Job $PF_JOB; Remove-Job $PF_JOB
```

**Bash:**
```bash
kubectl port-forward -n observability svc/prometheus-pushgateway 9091:9091 &
PF_PID=$!
sleep 3
tr -d '\r' < metrics.txt | curl -sS --data-binary @- http://localhost:9091/metrics/job/secureflow_devsecops
kill "$PF_PID"
```