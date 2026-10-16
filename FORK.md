# Fork this lab

`tx02v2` is the infrastructure half of the Azure pair of this lab; the application half is
[`dx02v2`](https://github.com/maringelix/dx02v2). This page takes you from a fork to a running lab:
first on your own machine (free, no cloud account), then, if you want, in your own Azure subscription
(that costs money). Each repository has its own FORK.md: start here, the app page only adds what is
specific to the app.

What is proven, and how, is in the [status matrix](README.md#status-matrix). In short: the harness
and the local lab are `verified in CI`; the cloud path of v2 is `not run in the cloud (v2)`. If you
run it in Azure you are one of its first tests: follow [docs/RUNBOOK.md](docs/RUNBOOK.md) step by
step and report what happened (step 8). Most documents under `docs/` are in Brazilian Portuguese;
this page, the README, AGENTS.md and CONTRIBUTING.md are in English.

## What a fork does not bring along

GitHub copies the code and its history, nothing else:

| Not copied | What to do |
|---|---|
| Repository settings: the ruleset (pull requests only, required checks), secret scanning, private vulnerability reporting, the `lab` environment and its reviewer | step 3 applies them with one script |
| Running workflows: a fork keeps its workflows disabled until you enable them, and scheduled workflows stay off in a fork | step 2 |
| Issues: they start disabled in a fork | step 3 turns them on (the bug report and cloud run report forms) |
| Dependabot: security updates start disabled; version updates do not run in a fork by default | step 3 turns security updates on; version bumps arrive when you sync (step 9) |
| Repository variables and secrets | the lab never needs a secret; the cloud path needs variables (step 7) |

A fork of a public repository is public, and so are its workflow logs.

## 1. Fork the pair

Fork both [`maringelix/tx02v2`](https://github.com/maringelix/tx02v2) and
[`maringelix/dx02v2`](https://github.com/maringelix/dx02v2) into your **personal account** and **keep
the names**: the federated credentials that the bootstrap creates trust exactly `<you>/tx02v2` and
`<you>/dx02v2`. Clone both next to each other:

```bash
git clone https://github.com/<you>/tx02v2.git
git clone https://github.com/<you>/dx02v2.git
```

You need Linux or WSL 2 (Ubuntu) with bash >= 4.4, curl, unzip, xz, git, make, Docker and the GitHub
CLI signed in as yourself (`gh auth login`). On Windows or macOS you can open each clone in its
devcontainer instead (VS Code with Docker Desktop): it has Docker-in-Docker and installs the tools,
and `make e2e` runs inside it (verified locally with `LOCAL_PROFILE=core`).

## 2. Enable Actions

In each fork, open the **Actions** tab and click **I understand my workflows, go ahead and enable
them**. Until you do, the required checks never report and no pull request can be merged.

## 3. Apply the repository settings

```bash
cd tx02v2 && scripts/repo-guardrails.sh <you>/tx02v2
cd ../dx02v2 && scripts/repo-guardrails.sh <you>/dx02v2
```

The script is idempotent and applies what the original repository has: vulnerability alerts and
Dependabot security updates, issues, squash-only merges, a read-only default `GITHUB_TOKEN`, the
ruleset of `.github/rulesets/main.json` (pull requests only; here the required checks are `static`,
`test` and `e2e`), secret scanning with push protection, private vulnerability reporting, approval of
workflow runs from forks of external contributors, and the `lab` environment (you as the required
reviewer, deployments from `main` only). It stops with a clear message while Actions are still
disabled, and its notes list what you should change by hand (step 5). Run it again after any change
of the ruleset. On Windows, run it from WSL or Git Bash.

## 4. Run the local lab (free)

```bash
make tools                     # the pinned tools into .tools/, each one SHA256-verified
HARNESS_STRICT=1 make verify   # static checks and terraform test: what the CI jobs static and test run
make e2e                       # the whole local lab: apply, platform, 34 probes, destroy
```

`make e2e` builds the platform of [docs/LAB_LOCAL.md](docs/LAB_LOCAL.md) on Docker: a kind cluster
with an emulated container registry, PostgreSQL (TLS only), object storage (an S3 API emulator in
place of Blob Storage), load balancer and git server, then Istio ambient, cert-manager, External
Secrets, Prometheus/Alertmanager/Grafana, Loki/Alloy, Argo CD, Gatekeeper, Trivy Operator, Velero and
Chaos Mesh. It proves each piece with real traffic and always destroys the lab, also after a failure.
It needs about 8 GB of memory for Docker and takes 20-40 minutes on a laptop (about 10 in CI): run
one lab at a time. With 7 GB, `LOCAL_SIZE=small` installs the same platform with smaller limits
and short retention (proved with the app of dx02v2, [docs/LAB_LOCAL.md](docs/LAB_LOCAL.md)). To keep
the lab up while you study it:

```bash
LOCAL_PROFILE=core make local-up   # core, observability, operations or full (the default)
make local-check                   # the probes of what is installed
make local-down                    # destroy, then the leftover check
```

The app comes next: in your `dx02v2` clone, `make e2e-platform` deploys it on this platform the
GitOps way (see its [FORK.md](https://github.com/maringelix/dx02v2/blob/main/FORK.md)).

## 5. Make the fork yours

`main` takes pull requests only now. Open one that replaces `@maringelix` with your user in
`.github/CODEOWNERS`; its CI (`static`, `test`, `e2e`) takes about 15 minutes and you merge it
yourself. The README badge, the family table and the security contact keep pointing to the original
repositories: change them if you like, nothing depends on them.

## 6. Keep your changes testable

Every pull request of your fork runs the same harness as the original, so
`HARNESS_STRICT=1 make verify` before a push saves a CI round. A change to `platform/local` or
`terraform/envs/local` is proven only by `make e2e`. To try such a change with the app, run
`make e2e-platform` in `dx02v2` with `TX02V2_DIR=../tx02v2` (your checkout as it is), or let the CI
of your `dx02v2` fork clone your `tx02v2` (its FORK.md, step 5).

## 7. Your own Azure subscription (costs money)

Before the first apply:

- Read the [cost section of the README](README.md#cloud-path-costs-money) and [docs/CUSTOS.md](docs/CUSTOS.md) (reference
  prices: check the current ones). Application Gateway for Containers with its WAF policy (the
  biggest item), the AKS nodes and PostgreSQL Flexible Server bill by the hour while the lab is up.
  The bootstrap creates a monthly budget with alerts, but a budget only warns, it stops nothing.
  Destroy on the same day.
- **Free Trial subscriptions restrict this lab**: v1 found PostgreSQL Flexible Server blocked in every
  region tried, AKS VM sizes refused and low quotas that cannot be raised
  ([docs/RUNBOOK.md](docs/RUNBOOK.md), section 1, and [docs/LICOES_APRENDIDAS.md](docs/LICOES_APRENDIDAS.md)).
  Upgrading to pay-as-you-go lifts the offer restrictions and keeps the remaining credit.
- Use a **dedicated subscription** (the budget and the leftover check cover all of it) where you are
  **Owner**, the Azure CLI and `jq`.

Then, from the root of your `tx02v2` clone:

1. **Bootstrap** (once, from your machine, as Owner): `az login` and
   `az account set --subscription <SUBSCRIPTION_ID>`; copy
   `terraform/bootstrap/terraform.tfvars.example` to `terraform.tfvars` (git-ignored) and set
   `subscription_id`, `github_owner` (your GitHub user) and `budget_alert_emails` (an address you
   read). `github_owner` and the e-mail have no usable default: the placeholders are refused, so the
   identities can only trust your forks. Set the three numeric GitHub IDs too (`github_owner_id`,
   `tx02v2_repository_id`, `dx02v2_repository_id`): GitHub writes them into the OIDC subject of every
   repository created after 2026-07-15 (your fork), and the federated credentials trust that exact
   subject. `scripts/repo-guardrails.sh` prints them, or: `gh api users/<you> --jq .id`,
   `gh api repos/<you>/tx02v2 --jq .id`, `gh api repos/<you>/dx02v2 --jq .id`. A repository that
   predates 2026-07-15 must opt in to immutable subject claims first (Settings > Actions > General >
   OpenID Connect).

   ```bash
   export PATH="$PWD/.tools/bin:$PATH"   # terraform, kubectl and kubelogin from make tools
   cd terraform/bootstrap && terraform init && terraform apply
   terraform output -raw backend_hcl >../envs/lab/backend.hcl
   ```

   The bootstrap state stays local (git-ignored): keep a backup of it. The role on the state
   container takes a few minutes to propagate: a 403 right after the bootstrap goes away if you wait
   ([docs/RUNBOOK.md](docs/RUNBOOK.md), section 2).
2. **Repository variables**: the bootstrap prints the ones it knows, ready for `gh`:

   ```bash
   terraform output -json github_variables_tx02v2 | jq -r 'to_entries[] | "\(.key)=\(.value)"' >/tmp/tx02v2.env
   gh variable set -f /tmp/tx02v2.env -R <you>/tx02v2
   terraform output -json github_variables_dx02v2 | jq -r 'to_entries[] | "\(.key)=\(.value)"' >/tmp/dx02v2.env
   gh variable set -f /tmp/dx02v2.env -R <you>/dx02v2
   ```

   The lists that name the people and the address that operate the lab are **secrets**, not
   variables (the logs of a public repository are public, and a secret is masked):

   ```bash
   terraform output -json github_secrets_tx02v2 | jq -r 'to_entries[] | "\(.key)=\(.value)"' >/tmp/tx02v2.secrets.env
   gh secret set -f /tmp/tx02v2.secrets.env -R <you>/tx02v2
   gh secret set LAB_API_SERVER_AUTHORIZED_IP_RANGES -R <you>/tx02v2   # a JSON list, e.g. ["0.0.0.0/0"]
   ```

   Then add your own object ID to `LAB_CLUSTER_ADMIN_PRINCIPAL_IDS` (the secret above holds only the
   apply identity) and the variables you choose (`LAB_ALLOW_API_SERVER_FROM_ANYWHERE`):
   [docs/RUNBOOK.md](docs/RUNBOOK.md), section 3. Variables are not secret: never put a credential or
   your address in one.
3. **Run**: from the Actions tab, `terraform-plan`, `terraform-apply` and `platform` (each one waits
   for your approval of the `lab` environment), the app deploy from your `dx02v2`, the smoke test,
   then `terraform-destroy`, which ends with the leftover check: [docs/RUNBOOK.md](docs/RUNBOOK.md),
   sections 4 to 9. The workflows take `github_owner` from the owner of the repository. For the full
   platform profile, set `LAB_NODE_VM_SIZE=Standard_D2as_v5` and `LAB_NODE_COUNT=2` before plan and
   apply; keep these values through destroy. The workflows pass them to plan/apply/destroy, while
   unset values preserve the cheaper core defaults.

Your fork is public, and so are its workflow logs. The workflows mask the tenant, subscription and
client IDs ([docs/GUARDRAILS.md](docs/GUARDRAILS.md), CI-07); never paste credentials or those IDs
into an issue or a pull request.

## 8. Report the run

Open a **Cloud run report** (date, region, commits, duration, cost, problems and the redacted output
of `scripts/leftovers.sh`) in your fork or, better, in the
[original repository](https://github.com/maringelix/tx02v2/issues/new/choose): every report makes the
lab better for the next person.

## 9. Keep the fork up to date

Use **Sync fork** on the GitHub page of each fork, or pull the original into a branch and open a pull
request. Run `scripts/repo-guardrails.sh` again when `.github/rulesets/main.json` changed.

## Troubleshooting

| Symptom | Fix |
|---|---|
| A pull request waits forever for `static`, `test` or `e2e` | Actions are still disabled in the fork: step 2 |
| `repo-guardrails.sh` fails with "the workflows of this fork are not enabled yet" | step 2, then run it again |
| `make e2e` gets killed or Docker freezes | give Docker about 8 GB of memory (Docker Desktop on WSL 2: `memory=8GB` under `[wsl2]` in `%UserProfile%\.wslconfig`, then `wsl --shutdown`) and run one lab at a time; with 7 GB, `LOCAL_SIZE=small make local-up`; with less memory, `LOCAL_PROFILE=core make e2e` proves the base layers |
| Port 5002 is already in use | another local lab or registry is running: `make local-down`, `docker ps` |
| Something of the local lab is left after an interruption | `make local-down` (destroy and leftover check) |
| Bootstrap: `Set github_owner ...` or `Replace the placeholder ...` | put your values in `terraform/bootstrap/terraform.tfvars` |
| `LocationIsOfferRestricted` or a refused VM size | a Free Trial restriction: upgrade to pay-as-you-go ([docs/RUNBOOK.md](docs/RUNBOOK.md), section 1) |
| 403 `AuthorizationPermissionMismatch` on the state right after the bootstrap | the role is still propagating: wait a few minutes and retry |

## Contributing back

Pull requests to the original repository are welcome: see [CONTRIBUTING.md](CONTRIBUTING.md). Their
workflow runs wait for the maintainer's approval, and the same harness decides.
