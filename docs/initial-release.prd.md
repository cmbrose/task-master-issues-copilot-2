# Product Requirements Document  
**Project**: Task-Planning GitHub Action Template  
**Doc version**: **v1.0 (2025-07-02)**  
**Author**: ChatGPT (with Caleb)  
**Status**: **Final**

---

## 1. Purpose & Goals

| Goal | Description | Success Metric |
|------|-------------|----------------|
| **Automated task graph** | On every PRD commit, generate a hierarchical task graph that breaks work into ≈ ≤ 4 h chunks. | Action runtime ≤ 5 min (p95); ≥ 90 % of leaf tasks flagged “≤ 4 h”. |
| **Single source of truth** | Keep the markdown PRD as the living spec; re-runs re-sync Issues when the doc changes. | ≤ 1 stale Issue / 100 after PRD change (via analytics sidecar). |
| **Friction-free execution** | Contributors pick any unblocked Issue immediately; blocked Issues unblock automatically when dependencies close. | Median “blocked → unblocked” latency < 15 min. |
| **On-demand drill-down** | Users can request further breakdown of an Issue when they spot excessive scope. | `/breakdown` completion ≤ 2 min for ≤ 20 sub-tasks; idempotent. |

---

## 2. Scope

* **In-scope (v0)**
  * Single repo; multiple PRDs.  
  * Issue creation, sub-issues, dependency labels, durable artifact.  
  * Dual-mode watcher (webhook + 10-min cron).  
  * Configurable recursion depth & complexity.  
  * Slash-command–triggered manual breakdown.

* **Deferred**
  * Cross-repo graphs, LLM-powered diff updates, automatic Projects board wiring.

---

## 3. Stakeholders

| Role | Responsibility |
|------|----------------|
| Maintainers | Configure workflows, secrets, branch protections. |
| Contributors | Commit PRDs, work Issues, invoke `/breakdown`. |
| Taskmaster CLI team | Provide deterministic binary & docs. |

---

## 4. User Stories

1. **PM** commits `docs/notifications.prd.md`, wants Issues created within minutes.  
2. **Engineer** searches unblocked Issues, trusts they’re bite-sized.  
3. **Tech lead** edits a PRD; obsolete Issues auto-sync.  
4. **Engineer** comments `/breakdown` on an oversized Issue and gets child tasks.  
5. **SRE** replays a failed run via artifact.

---

## 5. Functional Requirements

| # | Requirement | Priority |
|---|-------------|----------|
| **F-1** | Trigger on `push` to `docs/**.prd.md`; path glob configurable. | Must |
| **F-2** | Parse PRD via pinned Taskmaster CLI; stop when complexity ≤ `40` (default) or depth cap hit. | Must |
| **F-3** | Create/patch Issues with YAML front-matter (`id`, `parent`, `dependents`), labels `task`, `blocked`. | Must |
| **F-4** | Use Sub-issues REST API for hierarchy; fail hard if unavailable. | Must |
| **F-5** | Upload `artifacts/taskmaster/task-graph.json` every run. | Must |
| **F-6** | Watcher workflow removes `blocked` via `issues.closed` webhook + cron `*/10`. | Must |
| **F-7** | Recovery workflow `taskgraph-replay.yml` accepts artifact URL; idempotent. | Should |
| **F-8** | Expose inputs: `complexity-threshold`, `max-depth`, `prd-path-glob`, `taskmaster-args`. | Should |
| **F-9** | Dry-run on `pull_request` posts comment with would-create graph. | Nice |
| **F-10** | **Manual breakdown**: comment `/breakdown [--depth N] [--threshold X]` on any open Issue. Breakdown workflow runs Taskmaster on that node, creates sub-issues, links them, and closes/marks parent. Idempotent; respects `breakdown-max-depth` (default 2). | Should |

---

## 6. Non-Functional Requirements

* **Performance**: 1 000-line PRD (< 500 tasks) completes within 5 min typical; GitHub’s 6 h job ceiling respected.  
* **Idempotency**: No Issue churn on re-run with unchanged PRD.  
* **Observability**: Structured logs, job-failure annotations, replay artifact.  
* **Security**: Uses `GITHUB_TOKEN`; any external LLM keys via repo/org secrets.  
* **Responsiveness**: `/breakdown` workflow starts ≤ 1 min after comment.

---

## 7. Workflows

<details>
<summary>Text diagram</summary>
push docs/*.prd.md
└── taskmaster-generate
1. checkout
2. Taskmaster → task-graph.json
3. create/patch Issues, link hierarchy
4. upload artifact
5. status ✔/✖

issue_comment starts “/breakdown”
└── taskmaster-breakdown
1. parse args
2. fetch parent YAML
3. Taskmaster on node
4. create sub-issues, link via sub-issue API
5. close or convert parent
6. react 👍

issues.closed OR cron(*/10)
└── taskmaster-watcher
1. gather dependents (payload YAML or scan)
2. if all blockers closed → remove ‘blocked’
</details>

---

## 8. Configuration & Defaults

| Input | Default | Notes |
|-------|---------|-------|
| `complexity-threshold` | `40` | Medium–low band. |
| `max-depth` | `3` | Initial auto recursion cap. |
| `prd-path-glob` | `docs/**.prd.md` | POSIX glob. |
| `breakdown-max-depth` | `2` | Additional depth for `/breakdown`. |
| Watcher cron | `*/10 * * * *` | Editable. |

---

## 9. Acceptance Criteria

1. **Happy path**: Commit sample PRD → full graph created, artifact uploaded, runtime ≤ 5 min.  
2. **Dependency**: Closing blocker clears `blocked` within 10 min (or instantly).  
3. **Rate-limit recovery**: Force failure, run replay → graph completes without dupes.  
4. **Config override**: `complexity-threshold: 20` halves avg hours in sample leaf tasks.  
5. **Dry-run**: PR shows preview comment; no Issues created.  
6. **Manual `/breakdown`**: Generates child Issues, links hierarchy, parent closed/converted.

---

## 10. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Sub-issues API change | Workflow break | Pin REST version; fail fast. |
| API quota exhaustion | Partial graph | Batch + replay workflow. |
| Taskmaster regression | Incorrect graph | Pin checksum; CI smoke test. |

---

## 11. Milestones

| Phase | Deliverable | ETA |
|-------|-------------|-----|
| **0.1 PoC** | Scripted Action (leaf Issues only) | **Aug 2025 W1** |
| **0.5 Beta** | Full graph, blocked labels, artifact, watcher, `/breakdown` | **Sep 2025 W3** |
| **1.0 GA** | Recovery workflow, dry-run, docs, CI suite | **Oct 2025 W3** |

---

## 12. Open Items

| # | Question | Owner | Due |
|---|----------|-------|-----|
| 1 | Final mapping of Taskmaster score → hour estimate table (docs) | Caleb | Pre-Beta |

*(All other design questions closed.)*

---

### Appendix A – Example `/breakdown` Usage

```text
/breakdown --depth 1 --threshold 30
```
Triggers sub-issues up to 1 extra level, using a stricter complexity threshold of 30.
