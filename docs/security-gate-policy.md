## Ownership and blocking

| Scanner | Owner | Blocking condition |
|---|---|---|
| Gitleaks | DevSecOps | Any finding is treated as `CRITICAL` because Gitleaks detects exposed secrets. **Hard-fails job.** |
| Trivy | DevSecOps | `CRITICAL` / `HIGH`. **Hard-fails job.** |
| Checkov | DevSecOps | `CRITICAL`. **Hard-fails job.** |
| SonarQube | AppSec | Never blocks this gate |
| ZAP | AppSec | Never blocks this gate |

The gate exits non-zero (fails) when **at least one** DevSecOps-owned scanner job fails upstream, or if downloaded artifacts contain a `CRITICAL` finding attributed to Gitleaks, Trivy, or Checkov. It passes only when all DevSecOps scanners pass.

AppSec-owned findings are always non-blocking in this gate. They are rendered in the PR comment under an AppSec section and linked to the configured AppSec intake template.

## Existing pipeline integration

The repository integrates scanner jobs for Gitleaks, SonarQube, Trivy image scanning, Trivy Kubernetes configuration scanning, and Checkov Terraform scanning.

Scanner jobs are configured to **hard-fail** immediately upon detecting blocking findings or encountering operational errors. Findings are concurrently uploaded as artifacts and evaluated centrally by the `security-gate` job. 

The `security-gate` job evaluates the native job statuses of all upstream DevSecOps scanners. It aggregates the findings into a single PR comment for visibility and subsequently forces a pipeline failure if any DevSecOps scanner failed.