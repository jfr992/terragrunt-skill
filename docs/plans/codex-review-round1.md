Locations below refer to `docs/plans/2026-10-24-v1.9-v2.0.md`.

1. **high — Task 1, line 116: CLI rewrite breaks examples.** Replacing `run --all plan` literally produces `run --all -- plan --provider-cache`, forwarding Terragrunt flags to OpenTofu. Evidence: `references/performance.md:53,150,165`. **Fix:** move every Terragrunt flag before `--`; verify complete commands.

2. **high — Task 2, line 150: orphan cleanup guidance is incomplete.** Git-filter destruction requires `--filter-allow-destroy` with `plan`/`apply`; changes from environment variables or external values files cannot identify orphans. Evidence: [Git expressions](https://docs.terragrunt.com/features/filter/git/#destroying-removed-components). **Fix:** document the guarded plan/apply workflow and explicitly require manual cleanup for changes outside Git.

3. **med — Task 2, line 150: “growing adds only new elements” overgeneralizes expansion safety.** With `count`, list edits can shift existing identities; generated paths also determine state continuity. Evidence: [expansion rules](https://docs.terragrunt.com/reference/hcl/blocks/#expansion). **Fix:** scope the guarantee to stable `for_each` keys and unchanged paths; explain count reindexing and migration from unexpanded units.

4. **med — Task 1, lines 108–109: fallback guarantees are too broad.** Missing state objects do not receive native retry; render commands treat mocks differently; encrypted-state fallback depends on a binary capable of decrypting it. Evidence: [state-read failure handling](https://docs.terragrunt.com/reference/experiments/completed/#dependency-fetch-output-from-state). **Fix:** include these exceptions; remove unconditional “result correct.”

5. **high — Task 4, line 174: locking test is nondeterministic.** Two concurrent plans can finish sequentially and both succeed without testing exclusion; an arbitrary error does not prove correct locking. **Fix:** use disposable state, deliberately hold the first lock, verify the second fails specifically on lock acquisition, then verify acquisition succeeds after release.

6. **high — Tasks 1/8 omit an existing destructive example.** `references/performance.md:162` runs `rm -rf $TG_PROVIDER_CACHE_DIR/* $TG_DOWNLOAD_DIR/*`; unset variables expand to `/*`. **Fix:** replace with guarded, quoted, explicitly disposable cache paths before publishing the updated performance reference.

7. **med — Task 8, lines 213–219: broken bootstrap workflow remains.** `SKILL.md:122` passes `backend bootstrap` after `run --all --`, and runs before stack files exist. Evidence: [bootstrap command](https://docs.terragrunt.com/reference/cli/commands/backend/bootstrap/). **Fix:** create/generate units first, then use `terragrunt backend bootstrap --all`.

8. **med — Task 0, lines 76–88: prerequisite missing.** The script imports PyYAML without installing or documenting it; this checkout’s Python raises `ModuleNotFoundError: No module named 'yaml'`, before the promised stale-flag failure. **Fix:** declare/install a pinned dependency or use an available parser; verify the intended failure explicitly.

9. **med — Task 0, lines 83–85: lint can pass errors and miss broken links.** A grep error inside `if` is treated like “no matches”; the link regex ignores anchored links such as `(references/missing.md#section)`. **Fix:** distinguish grep statuses 0/1/2 and parse all local links, stripping fragments before checking existence.

10. **med — Tasks 3–7, green checks: commands are not runnable as written.** Bare `dependencies.md`, `patterns.md`, etc. are absent at repo root; `…`, `≥1`, and `= 0` are prose, not assertions. `grep -c` also exits 1 on zero matches. **Fix:** provide executable, root-relative assertions with deliberate zero-match handling.

11. **med — Task 3, line 167: ordering check passes unchanged content.** `dependencies.md:9` already contains “Autoinclude” in the contents, before the first `"../` example. **Fix:** compare actual section-heading positions and verify the revised recommendation, excluding contents tables.

12. **med — Task 9, line 234; v2 gate, line 306: eval checks prove little.** Counting 14 entries permits duplicates or empty expectations; testing only three positive queries misses regressions in the existing eight positives and three negatives (`evaluations/evaluations.json:3–18`). **Fix:** validate unique queries and required expectations, then record results for the full suite per supported agent.

13. **high — Task 13, line 301: CI trigger updates are missing.** `.github/workflows/validate.yml:5–14` excludes scripts, workflow files, evaluations, assets, and `agents/openai.yaml`. Changes solely to the new validator or metadata therefore bypass validation. **Fix:** expand both push and PR path filters.

14. **med — Task 13, line 302: packaging check does not enforce its requirements.** `find skills -size +100k` normally exits successfully even when it finds oversized files; it also allows 50–100 KB images and does not reject misplaced images or `test-output/`. **Fix:** explicitly fail on nonempty findings and check each stated constraint separately.

15. **high — Release gates, lines 237/282/295: release automation is not updated.** `.github/workflows/automated-release.yml:40–84` synchronizes only plugin JSON versions, leaving new `metadata.version` stale. One merge containing both phases also provides no separate v1.9 release boundary. **Fix:** add metadata synchronization and separate phase merges/releases; verify the Angular preset recognizes the intended breaking-change commit.

16. **med — Wave A, lines 310–312: hidden dependencies invalidate independent review.** Every task reviewer must run the global lint, which remains red until Task 1 removes stale flags. Task 11 concurrently installs contributor instructions requiring that lint before commits. **Fix:** finish baseline repairs first or scope intermediate checks to each task; defer contributor-policy changes until the global check passes.

17. **med — Task 11, lines 266–268: moving contributor guidance preserves contradictions.** `CLAUDE.md:53` forbids teaching `--no-hooks` and Azure until GA; line 59 says neither wiring pattern is the default. Tasks 3/7 explicitly reverse those positions. Evidence: [v1.2.0 release](https://github.com/gruntwork-io/terragrunt/releases/tag/v1.2.0). **Fix:** explicitly update these policies and schedule that work after the content decisions.

18. **low — Task 10, lines 253–254: marketplace installation is incomplete.** It adds the marketplace but omits `/plugin install terragrunt-skill@jfr992`, currently present at `README.md:100`. **Fix:** retain both commands and verify installation in a fresh session.
---

## Triage (Juan / Grok Bot, 2026-10-24)

| # | Verdict | Reason / action |
|---|---|---|
| 1 | Accept | Flags must go before `--`. Rule and grep check added to T1 and T7. |
| 2 | Accept | Context7 confirms `--filter-allow-destroy` is required. Workflow added to T2, plus a manual path for changes not tracked in Git. |
| 3 | Accept | Guarantee limited to `for_each` with stable keys; count reindexing documented. The path or state continuity on conversion is marked UNVERIFIED. |
| 4 | Accept (amended) | Context7: missing state uses `mock_outputs` only when mocks are allowed, otherwise it fails. Codex's "native retry" wording is replaced with the documented behaviour. |
| 5 | Accept | The lock test now deliberately holds the first lock. |
| 6 | Accept | Verified at `performance.md:162`. Replaced with a guarded `${VAR:?}`. |
| 7 | Accept | Verified at `SKILL.md:122`. `backend bootstrap` is a Terragrunt command. `--all` is UNVERIFIED and needs a `--help` check. |
| 8 | Accept | `import yaml` fails on the box. The script now parses with awk. |
| 9 | Accept | grep rc 2 is now handled; `#fragment` links are now checked. |
| 10 | Accept | Checks are now executable and root-relative, with `|| true`. |
| 11 | Accept | The order check now compares headings, not the TOC. |
| 12 | Accept | Eval checks now require unique queries and non-empty expectations, and the release gate runs the full suite. |
| 13 | Accept | Verified that `validate.yml` paths are narrow. Filters widened. |
| 14 | Accept | Explicit `test -z "$(find …)"` checks added. |
| 15 | Accept | Metadata version sync added. v1.9 and v2.0 are released separately. |
| 16 | Accept | Wave A reviewers use per-task checks. T11 moved to Wave B. |
| 17 | Accept | Verified at `CLAUDE.md:53,59`. T11 rewrites both policies. |
| 18 | Accept | Verified at `README.md:100`. Both commands kept. |

Result: 18 findings, 18 accepted (2 amended: #4 and #7), 0 rejected.
