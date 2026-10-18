# Contributing

Thanks for helping. This lab only claims what its harness proves, so every change goes through it.

Forking the lab to run it on your own machine and cloud account? Start with [FORK.md](FORK.md).

## Workflow

1. Open an issue for anything non-trivial (bugs: use the bug report form).
2. Branch from `main`; use [Conventional Commits](https://www.conventionalcommits.org/)
   (`feat:`, `fix:`, `docs:`, `chore:`, `ci:`, `refactor:`, `test:`).
3. `make tools` once, then `HARNESS_STRICT=1 make verify` before pushing. Windows/macOS: use the
   devcontainer.
4. Optional fast feedback: `pre-commit install` (hooks in `.pre-commit-config.yaml`).
5. Open a PR and complete the Definition of Done in the template. Merges are squash-only.

## Rules that matter most

- No secrets or real identifiers (subscription, tenant, object or client IDs, name suffixes, IPs,
  e-mails) anywhere, including examples. GUIDs in examples use one repeated digit
  (`00000000-0000-0000-0000-000000000000`).
- Do not weaken checks or add scanner ignores without `statement` and `expired_at`.
- Explain any Azure role, network, Kubernetes RBAC or CORS widening in the PR.
- Contract changes (`docs/CONTRACT.md`) need a coordinated PR in `dx02v2` and a version bump.
- Pin new actions (full commit SHA + `# vX.Y.Z`), charts and images (SHA256/digest) and tools
  (version + SHA256).
- All public documentation, examples, comments and user-facing messages must be in English. Preserve technical identifiers and historical evidence. Start with the [central getting-started guide](https://github.com/maringelix/tx00v2/blob/main/docs/GETTING_STARTED.md).

## Cloud runs

You never need an Azure subscription to contribute. If you run the lab in your own subscription,
follow `docs/RUNBOOK.md` (read the cost section first) and share the result with the
**Cloud run report** issue form.

The full rule list is in [docs/GUARDRAILS.md](docs/GUARDRAILS.md); agents and humans also follow
[AGENTS.md](AGENTS.md).
