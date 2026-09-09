# ADR 0002 — Folio is licensed GPL v3

- **Status:** Accepted (2026-09-09)
- **Wayfinder ticket:** [D2 — License reconciliation](https://github.com/sarthakpranit/Folio/issues/22) · map [#19](https://github.com/sarthakpranit/Folio/issues/19)

## Context

The repository is internally inconsistent about its license:

- `LICENSE` contains the **MIT** license (© 2026 Sarthak Pranit), added in a deliberate commit (`d1f86eb`).
- The README license badge and body, `docs/overview.md`, `docs/requirements.md`, `AGENTS.md`, and `CLAUDE.md` all state **GPL v3**, framed as "open source, transparent, community-driven (Calibre integration)".

Neither choice is forced by dependencies: Swifter is BSD-3-Clause, SwiftyJSON is MIT, and Calibre is invoked only as an external CLI process (ADR 0001) — no Calibre code is linked or bundled, so no copyleft obligation is inherited.

## Decision

**Folio is licensed under the GNU General Public License, version 3.**

Rationale:
- Every stated project value already names GPL v3 and a community/Calibre-adjacent ethos. The MIT `LICENSE` file is the outlier and is treated as the mistake to correct, not the standard to spread.
- Copyleft keeps forks and derivatives open — it prevents a closed-source or paid "Folio Pro" fork, which matches the maintainer's intent for the project.
- Cultural fit with the ebook / Calibre ecosystem, which is predominantly GPL.

## Consequences

Implementation-phase work (tracked as an `audit-finding` issue):

1. Replace `LICENSE` with the official GPL v3 text; keep the copyright line (`Copyright (C) 2026 Sarthak Pranit`).
2. Fix every stale reference so all say GPL v3 consistently: README badge + body, `docs/overview.md`, `docs/requirements.md`, `AGENTS.md`, `CLAUDE.md`.
3. Add an in-app **About / Acknowledgements** entry stating the license and listing third-party components with their licenses (Swifter — BSD-3, SwiftyJSON — MIT, and Calibre as an external optional dependency).
4. `CONTRIBUTING.md` (DOC2, [#29](https://github.com/sarthakpranit/Folio/issues/29)) states the inbound=outbound contribution terms (contributions accepted under GPL v3) and the standard per-file license header convention for new source files.
5. No code change is required by the license itself; the Swift Package manifests carry no license field today and none is added beyond the `LICENSE` file.
