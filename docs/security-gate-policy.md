# SecureFlow Differentiated Security Gate Policy

## 1. Ownership and Blocking Matrix

| Scanner | Stage | Owner | Blocking Condition | Pipeline Behavior |
|---|---|---|---|---|
| **Gitleaks** | Stage 1 | DevSecOps | Any secret finding (`CRITICAL`) | **Hard-fails job & blocks merge.** |
| **SonarQube (SAST)** | Stage 2 | AppSec | `CRITICAL` / `BLOCKER` only | **Soft-fails (`MAJOR`/`MINOR`)**; exports JSON artifact and routes findings to AppSec via PR comment. |
| **Trivy (Image)** | Stage 3 | DevSecOps | `CRITICAL` / `HIGH` CVEs | **Hard-fails job & blocks merge.** |
| **Trivy (K8s)** | Stage 4 | DevSecOps | `CRITICAL` / `HIGH` misconfigurations | **Hard-fails job & blocks merge.** |
| **Checkov (IaC)** | Stage 4 | DevSecOps | `CRITICAL` / `HIGH` failed checks | **Hard-fails job & blocks merge.** |
| **OWASP ZAP (DAST)** | Stage 7 | AppSec | Never blocks merge | **Non-blocking**; archives HTML/JSON reports and routes `HIGH`/`MEDIUM` findings to AppSec. |

The gate exits non-zero (`FAIL`) when **at least one** DevSecOps-owned scanner job fails upstream, or if downloaded artifacts contain a `CRITICAL` finding attributed to Gitleaks, Trivy, or Checkov. It passes (`PASS`) only when all DevSecOps scanners pass.

AppSec-owned findings (`AV-*`, `TV-*`, `FV-*`) are non-blocking in this gate. They are rendered in the Pull Request comment under the **AppSec-owned scanners** section and linked directly to the AppSec intake template.

## 2. Security Exception Process (`/security-exception`)

When an urgent release requires a temporary, time-bounded bypass for a known finding whose remediation is scheduled for the next release:
1. A developer or lead comments on the Pull Request using the trigger:
   `/security-exception <written justification, compensating runtime control, and target remediation date>`
2. The `.github/workflows/security-exception.yml` workflow validates that a written justification is present, tags the PR with `security-exception-requested`, and posts an immutable audit record containing the requester's GitHub handle, UTC timestamp, and justification.
3. Exceptions are strictly time-bounded to one release cycle and must be resolved before the subsequent sprint release.

## 3. AppSec Handoff & Intake Template

All application-layer findings surfaced by SonarQube (SAST) and OWASP ZAP (DAST) are handed off to the Application Security team with:
- **Vulnerability Index ID** (`AV-01`–`AV-08`, `TV-01`–`TV-07`, `FV-01`–`FV-07`)
- **Scanner & Severity** (`HIGH` / `MAJOR` / `MEDIUM`)
- **Service & File/Endpoint Location** (`services/auth-service/app.py`, `services/transaction-service/app.py`, `services/frontend/app.py`)
- **Runtime Compensating Control** (Active Falco eBPF rules `SECUREFLOW-RUNTIME-01` through `04` and Kubernetes NetworkPolicies)