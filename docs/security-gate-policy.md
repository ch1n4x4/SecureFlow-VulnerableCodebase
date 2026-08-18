# Security Gate Policy

## Purpose

The security gate is the single policy decision point for the repository's security scanners. Scanner jobs publish findings; the `security-gate` job aggregates those findings, attributes them to an owning team, comments on the pull request, and determines whether the gate fails.

## Ownership and blocking

| Scanner | Owner | Blocking condition |
|---|---|---|
| Gitleaks | DevSecOps | Any finding is treated as `CRITICAL` because Gitleaks detects exposed secrets |
| Trivy | DevSecOps | `CRITICAL` |
| Checkov | DevSecOps | `CRITICAL` |
| SonarQube | AppSec | Never blocks this gate |
| ZAP | AppSec | Never blocks this gate |

The gate exits non-zero only when the downloaded scanner results contain a `CRITICAL` finding attributed to Gitleaks, Trivy, or Checkov.

AppSec-owned findings are always non-blocking in this gate. They are rendered in the PR comment under an AppSec section and linked to the configured AppSec intake template.

## Existing pipeline integration

The repository already has scanner jobs for Gitleaks, SonarQube, Trivy image scanning, Trivy Kubernetes configuration scanning, and Checkov Terraform scanning.

The integration changes those jobs in one important way: scanner findings no longer cause the scanner job itself to fail. Instead, findings are uploaded as artifacts and evaluated centrally by `security-gate`.

This separation is intentional. It prevents the same finding from being evaluated under different blocking rules in different scanner jobs.

Operational failures such as inability to install a scanner, build an image, authenticate to SonarQube, or otherwise execute a scanner can still fail their scanner job. The gate itself is not an exception path for broken CI infrastructure.

## Scanner result inputs

The current workflow downloads these artifacts when present:

- `gitleaks-report`
- `sonar-findings`
- `trivy-report`
- `trivy-kubernetes-report`
- `checkov-terraform-report`
- `zap-findings`

The gate recognizes the native JSON structures currently produced by these scanners and also accepts the normalized envelope:

```json
{
  "scanner": "trivy",
  "findings": [
    {
      "id": "CVE-2026-12345",
      "severity": "CRITICAL",
      "title": "Example finding",
      "package": "example-package",
      "path": "optional/path",
      "url": "https://example.invalid/finding"
    }
  ]
}
```

## Severity handling

For Gitleaks, each detected secret is treated as `CRITICAL`. Gitleaks findings do not provide a vulnerability severity equivalent to Trivy/Sonar/Checkov, and the repository policy treats an exposed secret as a blocking security event.

For SonarQube and ZAP, severities are normalized for display only. These scanners remain non-blocking regardless of severity.

## Pull-request comment

The gate upserts a managed PR comment containing two sections:

### DevSecOps-owned scanners

This section shows Gitleaks, Trivy, and Checkov findings and states the hard-fail rule. A PR fails when at least one of these findings is `CRITICAL`.

### AppSec-owned scanners

This section shows SonarQube and ZAP findings, attributes them to the **AppSec team**, and links to the AppSec intake template.

The comment contains a management marker so repeated PR runs update the same comment rather than creating comment spam.

The AppSec intake URL is configurable with the repository variable:

`APPSEC_INTAKE_URL`

A default GitHub issue-template URL is used when the variable is not configured.

## `/security-exception`

A pull-request timeline comment beginning with `/security-exception` starts an exception request workflow.

Required form:

```text
/security-exception
reason: <why the bypass is needed>
ticket: <tracking ticket URL or ID>
expires: <YYYY-MM-DD>
scope: <exact finding(s) or scanner(s)>
```

Requests are accepted only from commenters whose GitHub `author_association` is `OWNER`, `MEMBER`, or `COLLABORATOR`.

The workflow labels the PR with `security-exception-requested` and records the request in a reply.

A request **never automatically bypasses the security gate**. Approval must be handled by the designated security approver and documented in the referenced ticket.

## Repository configuration still required

The following values are not present in the supplied workflow and must be confirmed before the repository is considered fully configured:

- `SONAR_TOKEN` — already referenced by the existing SonarQube job.
- `APPSEC_INTAKE_URL` — repository variable pointing to the actual AppSec intake template.
- `ZAP_BASE_URL` — repository variable for the deployable application URL/environment to scan with ZAP.
- GitHub branch protection/ruleset — the `security-gate` check should be required for merges to the protected branch.
- GitHub Actions permissions — the workflow must be allowed to use `issues: write` for PR comments.
- If ZAP requires authentication, the required credentials/header strategy must be provided.

## Suggested branch protection check

Require the check named:

`security-gate`

Do not separately require Gitleaks, SonarQube, Trivy, or Checkov as merge-blocking checks if the intention is that this gate is the single security policy decision point.

## Files added/changed

- `.github/workflows/devops-pipeline.yml`
- `.github/workflows/security-exception.yml`
- `pipeline/scripts/security-gate.sh`
- `docs/security-gate-policy.md`
