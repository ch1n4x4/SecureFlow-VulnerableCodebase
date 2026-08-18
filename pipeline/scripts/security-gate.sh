#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set}"
: "${GITHUB_TOKEN:?GITHUB_TOKEN must be set}"

SCAN_DIR="${SCAN_DIR:-security-results}"
APPSEC_INTAKE_URL="${APPSEC_INTAKE_URL:-https://github.com/${GITHUB_REPOSITORY}/issues/new?template=appsec-security-intake.md}"
POLICY_REF="${POLICY_REF:-main}"
POLICY_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY}/blob/${POLICY_REF}/docs/security-gate-policy.md"
COMMENT_MARKER='<!-- security-gate:managed -->'
DEVSECOPS='["gitleaks","trivy","checkov"]'
APPSEC='["sonarqube","zap"]'

mkdir -p "$SCAN_DIR"

shopt -s nullglob
files=("$SCAN_DIR"/*.json)
shopt -u nullglob

# The gate is allowed to run when a scanner job failed operationally. The
# scanner job itself remains failed, while this job is responsible only for
# the policy decision represented by the scanner output.
if ((${#files[@]} == 0)); then
  echo "::warning::No scanner JSON reports were downloaded. Scanner job status must be reviewed."
  exit 0
fi

normalize_file() {
  local file="$1"
  local fallback="$2"

  jq -c --arg fallback "$fallback" '
    def up: tostring | ascii_upcase;
    def sev:
      (.severity // .Severity // .level // .risk // .riskdesc // "INFO")
      | tostring | ascii_upcase
      | if startswith("CRITICAL") or startswith("BLOCKER") then "CRITICAL"
        elif startswith("HIGH") then "HIGH"
        elif startswith("MEDIUM") or startswith("MAJOR") then "MEDIUM"
        elif startswith("LOW") or startswith("MINOR") then "LOW"
        else "INFO" end;

    # Gitleaks JSON: top-level array
    if type == "array" and (length == 0 or .[0].RuleID? != null) then
      [ .[] | {
        scanner: "gitleaks",
        id: ((.RuleID // .ruleID // .Fingerprint // "gitleaks-finding") | tostring),
        severity: "CRITICAL",
        title: ((.Description // .RuleID // "Secret detected") | tostring),
        package: "",
        path: ((.File // "") | tostring),
        url: ""
      } ]

    # SonarQube JSON: .issues[]
    elif (.issues? | type) == "array" then
      [ .issues[] | {
        scanner: "sonarqube",
        id: ((.key // .rule // "sonarqube-finding") | tostring),
        severity: sev,
        title: ((.message // .rule // "SonarQube finding") | tostring),
        package: "",
        path: ((.component // .project // "") | tostring),
        url: ((.url // "") | tostring)
      } ]

    # Trivy combined image report: .Reports[].Results[].Vulnerabilities[]
    elif (.Reports? | type) == "array" then
      [
        .Reports[] as $report |
        ($report.Results // [])[] |
        (.Vulnerabilities // [])[] |
        {
          scanner: "trivy",
          id: ((.VulnerabilityID // .PkgID // "trivy-finding") | tostring),
          severity: sev,
          title: ((.Title // .PkgName // .VulnerabilityID // "Trivy vulnerability") | tostring),
          package: ((.PkgName // .PkgID // "") | tostring),
          path: ((.Target // $report.Target // "") | tostring),
          url: ((.PrimaryURL // "") | tostring)
        }
      ]

    # Trivy config report: .Results[].Misconfigurations[]
    elif (.Results? | type) == "array" and ([.Results[]?.Misconfigurations?] | any) then
      [
        .Results[] as $result |
        ($result.Misconfigurations // [])[] |
        {
          scanner: "trivy",
          id: ((.ID // "trivy-config-finding") | tostring),
          severity: sev,
          title: ((.Title // .Description // .ID // "Trivy configuration finding") | tostring),
          package: ((.Type // "") | tostring),
          path: ((.Target // "") | tostring),
          url: ((.PrimaryURL // .References[0] // "") | tostring)
        }
      ]

    # Checkov JSON: .results.failed_checks[]
    elif (.results?.failed_checks? | type) == "array" then
      [
        .results.failed_checks[] |
        {
          scanner: "checkov",
          id: ((.check_id // "checkov-finding") | tostring),
          severity: sev,
          title: ((.check_name // .check_id // "Checkov finding") | tostring),
          package: ((.resource // "") | tostring),
          path: ((.file_path // "") | tostring),
          url: ((.guideline // "") | tostring)
        }
      ]

    # ZAP JSON: .site[].alerts[]
    elif (.site? | type) == "array" then
      [
        .site[] |
        (.alerts // [])[] |
        {
          scanner: "zap",
          id: ((.pluginid // .pluginId // "zap-finding") | tostring),
          severity: sev,
          title: ((.alert // .name // "ZAP finding") | tostring),
          package: "",
          path: (((.instances[0].uri // "") | tostring)),
          url: ""
        }
      ]

    else
      # Normalized envelope or generic array/object.
      if type == "object" and (.scanner? != null) and ((.findings? | type) == "array") then
        [ .findings[] | {
          scanner: ((.scanner // $fallback) | tostring | ascii_downcase),
          id: ((.id // .ruleId // .check_id // "finding") | tostring),
          severity: sev,
          title: ((.title // .message // .rule // .name // .id // "Finding") | tostring),
          package: ((.package // .artifact // .component // .image // "") | tostring),
          path: ((.path // .file // .location // "") | tostring),
          url: ((.url // .html_url // .more_info // "") | tostring)
        } ]
      elif type == "array" then
        [ .[] | {
          scanner: $fallback,
          id: ((.id // .ruleId // .check_id // "finding") | tostring),
          severity: sev,
          title: ((.title // .message // .rule // .name // .id // "Finding") | tostring),
          package: ((.package // .artifact // .component // .image // "") | tostring),
          path: ((.path // .file // .location // "") | tostring),
          url: ((.url // .html_url // .more_info // "") | tostring)
        } ]
      else
        []
      end
    end
  ' "$file"
}

normalized='[]'
for file in "${files[@]}"; do
  base="$(basename "$file" .json | tr '[:upper:]' '[:lower:]')"

  if ! jq -e . "$file" >/dev/null 2>&1; then
    echo "::warning::Ignoring invalid JSON report: $file"
    continue
  fi

  case "$base" in
    gitleaks-report) fallback="gitleaks" ;;
    sonar-findings) fallback="sonarqube" ;;
    trivy-report|trivy-kubernetes-report) fallback="trivy" ;;
    checkov-report) fallback="checkov" ;;
    zap-report) fallback="zap" ;;
    *) fallback="$base" ;;
  esac

  rows="$(normalize_file "$file" "$fallback")"
  normalized="$(jq -c --argjson rows "$rows" '. + $rows' <<<"$normalized")"
done

critical_dev_count="$(jq --argjson dev "$DEVSECOPS" '
  [ .[] | select((.scanner as $s | $dev | index($s)) != null)
        | select(.severity == "CRITICAL") ] | length
' <<<"$normalized")"

dev_count="$(jq --argjson dev "$DEVSECOPS" '
  [ .[] | select((.scanner as $s | $dev | index($s)) != null) ] | length
' <<<"$normalized")"

app_count="$(jq --argjson app "$APPSEC" '
  [ .[] | select((.scanner as $s | $app | index($s)) != null) ] | length
' <<<"$normalized")"

unknown_count="$(jq --argjson dev "$DEVSECOPS" --argjson app "$APPSEC" '
  [ .[] | select(
      ((.scanner as $s | $dev | index($s)) == null)
      and
      ((.scanner as $s | $app | index($s)) == null)
    ) ] | length
' <<<"$normalized")"

render_rows() {
  local scanners_json="$1"
  jq -r --argjson scanners "$scanners_json" '
    [ .[] | select((.scanner as $s | $scanners | index($s)) != null) ]
    | if length == 0 then "_No findings reported._"
      elif length > 50 then
        (.[0:50][] |
          "- **\(.severity)** — \(.scanner): \(.title)" +
          (if .package != "" then " — `\(.package)`" else "" end) +
          (if .path != "" then " — `\(.path)`" else "" end) +
          (if .url != "" then " ([details](\(.url)))" else "" end))
        + "\n\n_Only the first 50 findings are shown._"
      else
        .[] |
        "- **\(.severity)** — \(.scanner): \(.title)" +
        (if .package != "" then " — `\(.package)`" else "" end) +
        (if .path != "" then " — \(.path)" else "" end) +
        (if .url != "" then " ([details](\(.url)))" else "" end)
      end
  ' <<<"$normalized"
}

dev_section="$(render_rows "$DEVSECOPS")"
app_section="$(render_rows "$APPSEC")"

if ((critical_dev_count > 0)); then
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

if ((critical_dev_count > 0)); then
  echo "::error::Security gate failed: $critical_dev_count DevSecOps CRITICAL finding(s)."
  exit 1
fi

echo "Security gate passed: no DevSecOps CRITICAL findings. DevSecOps=$dev_count AppSec=$app_count Unknown=$unknown_count"
