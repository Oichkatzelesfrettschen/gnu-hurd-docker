@AGENTS.md

# Claude Code Loader for gnu-hurd-docker

## Loading rule

`AGENTS.md` owns the gnu-hurd-docker rules; the `@AGENTS.md` import above loads
them. The import path is spelled in that exact case: imports resolve literally,
and this filesystem is case-sensitive. This file carries Claude Code operating
notes only; shared doctrine lands in `AGENTS.md`.

Nested `AGENTS.md` files add narrower rules for their subtree and control only
inside it. Loader files hold the import plus tool-specific notes, because copied
doctrine drifts into conflicting instructions.

## Gate entry points

- Shell: `make lint` (calls `scripts/check-maintained-shell.sh`, the single
  ShellCheck mechanism; `SHELLCHECK_SEVERITY` defaults to `error`)
- Repo invariants: `make validate`
- Compose posture: `make security`
- Docs links: `make links` (asserts the broken-link count; the scanner alone
  exits 0 whatever it finds)
- Host smoke: `make smoke-host`
- Release product: `scripts/build-release-archive.sh --version vX.Y.Z --commit <sha>`

Active workflows: `static-gates.yml`, `release-archive-check.yml`,
`docs-build-check.yml`. The rest, including `validate.yml`,
`validate-config.yml`, `quality-and-security.yml`, and `release-artifacts.yml`,
are `disabled_manually` and produce no evidence, so changes to them are reasoned
rather than observed and are reported that way.

## Boot entry point

    make minty-up

`compose.minty.yaml` overlays the canonical `gnu-hurd-dev` service and declares
none of its own, so one QEMU container runs. `make topology` asserts that from
the rendered configuration; `AGENTS.md` section `Booting the Minty Profile`
carries the composition and the accelerator decision record.

## Claude Code operating notes

Inspect the real repository and the live system with Claude Code tools before
editing. Memory, prior summaries, and recalled context are leads; `AGENTS.md`,
the source, and the running system are authority.

Inspect the diff after every edit. The adversarial staged-diff read runs before
any commit or completion claim.

Claude Code task tracking is transient working state; durable state lands in
code, commit messages, findings, documentation, or qcow2 snapshots. For any task
involving two or more steps, track progress under durable mechanism names and
rescope as discoveries land.

Snapshot a guest image before mutating it and name the snapshot that is the
rollback; `AGENTS.md` section `Guest Image Discipline` carries the sequence.

## Response shape

Responses report the changed mechanism, the evidence used, the validation run,
the checks not run and why, and the remaining risks or unresolved falsifiers.
Observed and inferred stay separated.

Chained reasoning appears when it explains the next action or a validation
requirement; the rest of the deliberation lives in thoughtspace. Responses are
plain ASCII mechanism prose under durable names.

## Orientation pointers

- Roadmap: `ROADMAP.md`
- Findings: `docs/audits/`
- Minty guest: `MINTY-HURD-README.md`, `compose.minty.yaml`
- Docs site: `docs/index.md`, `mkdocs.yml`
