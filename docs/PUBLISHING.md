# Publishing tx02v2

Checklist for making the repository public with the v2 protections. Follow the order;
each item names its command or verification point.

## Before publishing

- [ ] `HARNESS_STRICT=1 make verify` passes in the devcontainer or on Linux.
- [ ] Set executable bits on entry points before the first commit (Windows does not record them):
      `git add --chmod=+x platform/install.sh platform/render-manifests.sh platform/uninstall.sh scripts/harness.sh scripts/install-tools.sh scripts/leftovers.sh scripts/repo-guardrails.sh scripts/update-tool-checksums.sh`
      (`repo-structure` checks the Git index).
- [ ] Make and push the first commit to private `main`; CI passes (`static`, `test`).
- [ ] `gitleaks git` reports no findings in the full history (the `gitleaks` check runs it when commits exist).
- [ ] No real identifiers: `policy-identifiers` passes (GUIDs, IPs, emails), followed by a human review
      of `docs/`. The real name suffix, `tx02v2lab<suffix>`, also identifies your subscription.
- [ ] Review the README status matrix: change `verified locally` to `verified in CI` only after
      the first successful CI run. Every cloud item stays `not run in the cloud (v2)` until a
      `cloud_run_report` supplies evidence.
- [ ] Set the repository description and topics
      (`gh repo edit maringelix/tx02v2 --description ... --add-topic terraform`).

## Publish

- [ ] `gh repo edit maringelix/tx02v2 --visibility public --accept-visibility-change-consequences`
- [ ] `scripts/repo-guardrails.sh maringelix/tx02v2` enables vulnerability alerts, Dependabot security
      updates, squash-only merges, `delete_branch_on_merge`, issues, a read-only default
      `GITHUB_TOKEN` without PR approval permission, the `main` ruleset, secret scanning and push
      protection, private vulnerability reporting, approval of external contributors' fork PR
      workflows, and environment `lab` (the person running the script reviews deployments; only
      `main` may deploy). It fails while Actions is disabled and identifies remaining fork setup
      (`FORK.md`). It reports applied/skipped settings, notes, and failures.

## Main ruleset (`.github/rulesets/main.json`)

- Blocks deletion and force pushes; requires PRs (zero approvals for a solo maintainer,
  `dismiss_stale_reviews_on_push`, `required_review_thread_resolution`); squash merges only.
- Required checks (strict mode, GitHub Actions app): `static`, `test`, `e2e` (the local lab).
- Bypass: repository administrator role, `pull_request` mode, **emergencies only**, such as an
  external failure blocking a security fix. Record the reason in the PR. This does not authorize
  bypassing failed or pending required checks during normal delivery.

## Stable job IDs

Changing an ID breaks protection. Current IDs:

| Workflow | Job | Required by ruleset |
|---|---|---|
| `ci.yml` | `static` | yes |
| `ci.yml` | `test` | yes |
| `ci.yml` | `e2e` | yes |
| `terraform-plan.yml` | `plan` | no; runs only with `AZURE_PLAN_CLIENT_ID` and same-repository PRs |
| `terraform-apply.yml` | `apply` | no |
| `platform.yml` | `platform` | no |
| `terraform-destroy.yml` | `destroy` | no |

## After publishing

- [ ] Public `main` CI passes and the badge works; update the matrix to `verified in CI`.
- [ ] Configure GitHub variables after bootstrap (`docs/RUNBOOK.md`, section 3), including dx02v2.
- [ ] Record the first cloud run in a `cloud_run_report`.
