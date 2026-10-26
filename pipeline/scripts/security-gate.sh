#!/usr/bin/env bash
set -euo pipefail

COMMENT_MARKER="<!-- security-gate:managed -->"
APPSEC_INTAKE_URL="https://github.com/${GITHUB_REPOSITORY:-ch1n4x4/SecureFlow-VulnerableCodebase}/issues/new?template=appsec-intake.md"
POLICY_URL="https://github.com/${GITHUB_REPOSITORY:-ch1n4x4/SecureFlow-VulnerableCodebase}/blob/main/docs/security-gate-policy.md"

ARTIFACTS_DIR="${ARTIFACTS_DIR:-./artifacts}"

dev_count=0
critical_dev_count=0
app_count=0
unknown_count=0

dev_section=""
app_section=""

# ---------------------------------------------------------------------------
# 1. Parse DevSecOps-Owned Scanners (Gitleaks, Trivy Image, Trivy K8s, Checkov)
# ---------------------------------------------------------------------------

# Gitleaks (Any secret finding is treated as CRITICAL)
if [[ -f "${ARTIFACTS_DIR}/gitleaks-report.json" ]]; then
  gl_count=$(jq 'if type=="array" then length else 0 end' "${ARTIFACTS_DIR}/gitleaks-report.json" 2>/dev/null || echo 0)
  dev_count=$((dev_count + gl_count))
  critical_dev_count=$((critical_dev_count + gl_count))
  dev_section+="- **Gitleaks (Secrets):** ${gl_count} finding(s) (${gl_count} CRITICAL)"$'\n'
else
  dev_section+="- **Gitleaks (Secrets):** 0 findings (Clean)"$'\n'
fi

# Trivy Image Scan
if [[ -f "${ARTIFACTS_DIR}/trivy-image-report.json" ]]; then
  ti_crit=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length' "${ARTIFACTS_DIR}/trivy-image-report.json" 2>/dev/null || echo 0)
  ti_high=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="HIGH")] | length' "${ARTIFACTS_DIR}/trivy-image-report.json" 2>/dev/null || echo 0)
  ti_total=$((ti_crit + ti_high))
  dev_count=$((dev_count + ti_total))
  critical_dev_count=$((critical_dev_count + ti_crit))
  dev_section+="- **Trivy (Container Images):** ${ti_total} finding(s) (${ti_crit} CRITICAL, ${ti_high} HIGH)"$'\n'
else
  dev_section+="- **Trivy (Container Images):** 0 CRITICAL/HIGH findings"$'\n'
fi

# Trivy K8s Manifest Scan
if [[ -f "${ARTIFACTS_DIR}/trivy-k8s-report.json" ]]; then
  tk_crit=$(jq '[.Results[]?.Misconfigurations[]? | select(.Severity=="CRITICAL")] | length' "${ARTIFACTS_DIR}/trivy-k8s-report.json" 2>/dev/null || echo 0)
  tk_high=$(jq '[.Results[]?.Misconfigurations[]? | select(.Severity=="HIGH")] | length' "${ARTIFACTS_DIR}/trivy-k8s-report.json" 2>/dev/null || echo 0)
  tk_total=$((tk_crit + tk_high))
  dev_count=$((dev_count + tk_total))
  critical_dev_count=$((critical_dev_count + tk_crit))
  dev_section+="- **Trivy (Kubernetes Manifests):** ${tk_total} finding(s) (${tk_crit} CRITICAL, ${tk_high} HIGH)"$'\n'
else
  dev_section+="- **Trivy (Kubernetes Manifests):** 0 CRITICAL/HIGH findings"$'\n'
fi

# Checkov Terraform IaC Scan
if [[ -f "${ARTIFACTS_DIR}/checkov-report.json" ]]; then
  ck_failed=$(jq '[.. | objects | select(has("failed_checks")) | .failed_checks[]] | length' "${ARTIFACTS_DIR}/checkov-report.json" 2>/dev/null || echo 0)
  dev_count=$((dev_count + ck_failed))
  critical_dev_count=$((critical_dev_count + ck_failed))
  dev_section+="- **Checkov (Terraform IaC):** ${ck_failed} failed check(s)"$'\n'
else
  dev_section+="- **Checkov (Terraform IaC):** 0 failed checks"$'\n'
fi

# ---------------------------------------------------------------------------
# 2. Parse AppSec-Owned Scanners (SonarQube SAST & OWASP ZAP DAST — Non-blocking)
# ---------------------------------------------------------------------------

# SonarQube SAST
if [[ -f "${ARTIFACTS_DIR}/sonarqube-report.json" ]]; then
  sq_count=$(jq '.issues | if type=="array" then length else 0 end' "${ARTIFACTS_DIR}/sonarqube-report.json" 2>/dev/null || echo 0)
  app_count=$((app_count + sq_count))
  app_section+="- **SonarQube (SAST):** ${sq_count} application-layer finding(s) routed to AppSec (AV-01, AV-02, AV-05, AV-07, AV-08, TV-03, TV-04)"$'\n'
else
  app_section+="- **SonarQube (SAST):** Report archived in workflow artifacts (Routed to AppSec)"$'\n'
fi

# OWASP ZAP DAST
if [[ -f "${ARTIFACTS_DIR}/zap-report.json" ]]; then
  zap_count=$(jq '[.site[]?.alerts[]?] | length' "${ARTIFACTS_DIR}/zap-report.json" 2>/dev/null || echo 0)
  app_count=$((app_count + zap_count))
  app_section+="- **OWASP ZAP (DAST):** ${zap_count} runtime HTTP alert(s) routed to AppSec (FV-01, FV-02, FV-05, FV-06, FV-07)"$'\n'
else
  app_section+="- **OWASP ZAP (DAST):** Scheduled/Staging scan routed to AppSec"$'\n'
fi

# ---------------------------------------------------------------------------
# 3. Upstream Job Status & Gate Verdict Evaluation
# ---------------------------------------------------------------------------
UPSTREAM_FAILED=0
if [[ "${GITLEAKS_STATUS:-success}" == "failure" ]] || \
   [[ "${TRIVY_SCAN_STATUS:-success}" == "failure" ]] || \
   [[ "${TRIVY_K8S_STATUS:-success}" == "failure" ]] || \
   [[ "${CHECKOV_STATUS:-success}" == "failure" ]]; then
  UPSTREAM_FAILED=1
fi

# Gate fails if artifacts contain criticals OR if upstream jobs hard-failed
if ((critical_dev_count > 0)) || ((UPSTREAM_FAILED == 1)); then
  status="FAIL"
else
  status="PASS"
fi

summary="${COMMENT_MARKER}
## Security gate - ${status}

### DevSecOps-owned scanners
Hard-fail policy: **CRITICAL** findings from Gitleaks, Trivy, or Checkov fail this gate.
Findings: **${dev_count}** | DevSecOps CRITICAL: **${critical_dev_count}**

${dev_section}
### AppSec-owned scanners
Non-blocking summary; ownership: **AppSec team**.
Findings: **${app_count}**

${app_section}
For AppSec triage, use the [AppSec intake template](${APPSEC_INTAKE_URL}).
[Security gate policy](${POLICY_URL})
"

if ((unknown_count > 0)); then
  summary+="
> **Warning:** ${unknown_count} finding(s) came from an unclassified scanner/report and are non-blocking until the ownership map is updated.
"
fi

if ((UPSTREAM_FAILED == 1)); then
  summary+="
> **Error:** One or more DevSecOps scanner jobs failed upstream (either due to a crash or critical findings). The pipeline is blocked until all DevSecOps jobs pass.
"
fi

# PR comments are only possible for pull_request events. Push builds still
# receive the same exit-code policy but do not attempt a PR comment.
if [[ -n "${PR_NUMBER:-}" ]]; then
  export GH_TOKEN="$GITHUB_TOKEN"
  comments="$(gh api --paginate \
    "repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/comments?per_page=100" \
    --jq '.[] | select(.body | contains("<!-- security-gate:managed -->")) | .id' || true)"
  comment_id="$(printf '%s\n' "$comments" | head -n1)"
  if [[ -n "$comment_id" ]]; then
    gh api -X PATCH "repos/$GITHUB_REPOSITORY/issues/comments/$comment_id" \
      -H 'Accept: application/vnd.github+json' \
      -f body="$summary" >/dev/null
  else
    gh api -X POST "repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/comments" \
      -H 'Accept: application/vnd.github+json' \
      -f body="$summary" >/dev/null
  fi
else
  echo "::notice::No PR number; skipping PR comment."
fi

# Final Job Evaluation
if [[ "$status" == "FAIL" ]]; then
  echo "::error::Security gate failed: DevSecOps scanner(s) failed upstream or CRITICAL findings were detected."
  exit 1
fi

echo "Security gate passed: All DevSecOps scanners passed. DevSecOps=$dev_count AppSec=$app_count Unknown=$unknown_count"