# --- REPLACE FROM LINE 163 DOWNWARDS ---

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
## Security gate — ${status}

### DevSecOps-owned scanners
Hard-fail policy: **CRITICAL** findings from Gitleaks, Trivy, or Checkov fail this gate.

Findings: **${dev_count}** · DevSecOps CRITICAL: **${critical_dev_count}**

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