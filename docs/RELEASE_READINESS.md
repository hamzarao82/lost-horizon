# Release Readiness

Tags are explained in [MILESTONE_004.md](MILESTONE_004.md). Statuses are as of 2026-11-03. This is a checklist for the **vertical-slice release candidate**, not a claim that the slice exists.

## 1. Repository and publishing

| Item | Status |
|---|---|
| Public GitHub repository, history clean (no gmail, no secrets, no keystores) | `[IMPLEMENTED]` audit run before publishing |
| Branch protection (no force push or deletion on `master`), secret scanning, push protection, Dependabot, private vulnerability reporting, read-only workflow token | `[IMPLEMENTED]` |
| GitHub Pages site (portfolio at the root, game at `/play/`), deploys from `master` | `[IMPLEMENTED]`; verified loading in about 30 s |
| Web bundle with hashed file names via `tools/package_web.ps1` | `[IMPLEMENTED]` on `master` |
| **v0.1.0 release** (Windows zip 36.7 MB, Android APK 27.5 MB) | **pending: the release was blocked by the permission system and needs the owner's approval** |
| Seven Dependabot pull requests (major version bumps) | open; each needs a build check before merging `[UNVERIFIED]` |
| Branches `milestone-002` and `milestone-003` pushed to GitHub | **not pushed** |
| Backup branch `backup-before-author-rewrite` | local only, contains the old author email; must never be pushed |

## 2. Product readiness (Milestone 004 goals)
| Item | Status |
|---|---|
| Milestones 002 and 003 merged into one release branch | not done |
| Mission acts 4–6, results screen, main menu, inventory screen, death screen | not done (`[NEW-M4]`) |
| Warden complete design | not done |
| Audio for all categories | not done |
| All QA cases in QA_AND_ACCEPTANCE_TESTS.md run with recorded results | not done |
| Performance budgets measured on Windows, Android and web | Windows and desktop web partly; Android none |
| Gamepad bindings complete | not done (known gap) |

## 3. Quality gates (go / no-go)
A release candidate may be tagged only when **all** of these are true:
1. All automated suites pass on the merged branch; flaky failures re-run and logged.
2. The playthrough bot completes the whole mission including the new acts and the results screen.
3. A human completes the mission start to finish on Windows without assistance; time recorded.
4. A human completes at least the first three acts on a physical Android phone; crashes: none.
5. The web build loads in 30 s or less on the reference laptop (fresh profile) and saves persist after a reload.
6. No known crash, soft lock or save-loss bug; known issues are listed in the release notes.
7. Every shipped asset has a recorded licence (`ASSETS.md`); audio and art are either original or licensed.
8. The security checks of section 1 still hold on the release commit (scan for secrets, no personal data).
9. Release notes state the limitations honestly (section 5).

## 4. Release procedure (extends `RELEASE.md`)
1. Create the integration branch from `master`, merge `milestone-002` and `milestone-003`, run all suites.
2. Implement Milestone 004 steps in the order of MILESTONE_004.md section 7; after each step run the suites and the benchmark.
3. Freeze features, run the manual checklist and the device tests, fix blockers only.
4. Export Web (`tools/package_web.ps1`), Windows and Android; build the zip and APK; for Android decide between a debug-signed APK (current) and a properly signed release `[PROPOSED]` (needs a keystore the owner creates and keeps private; never commit it).
5. Update the portfolio page, screenshots and trailer (the existing trailer shows the placeholder characters; record a new one after the merge).
6. Tag `v0.2.0` (or the agreed number), create the GitHub release with the zip, APK and notes, deploy Pages, verify the live game loads.
7. Announce known limitations and how to report bugs (`SECURITY.md` covers security reports).

## 5. Known limitations to state at release
- A single region and one mission; the rest of the island is future work.
- Debug-signed Android build (unless a release keystore is created); no Play Store distribution is planned for the slice.
- Procedural or limited audio unless licensed assets are added.
- Stylized low-poly art, not hand-sculpted detail.
- Patrols use simple navigation; one boss.
- Web first load takes about 30 s on integrated graphics (a fresh browser profile); repeat loads are expected to be faster `[UNVERIFIED]`.
- Phone performance is as measured on the test devices only.

## 6. Risks
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Merge of 002 and 003 is harder than expected | medium | high | do it first; budget a full session; keep tests as the safety net |
| Android performance misses 30 FPS | medium | high | Low quality default, cap animated characters, measure early |
| Web load or memory regresses after the merge | medium | medium | measure with `boot_probe.mjs` after the merge |
| Scope creep (more regions, features) | high | high | scope list in MILESTONE_004.md section 10 |
| Token or time budget | high | medium | sequence by value; use automated tests as proof; agents only with tight briefs |
| Asset licence mistakes | medium | high | licence ledger, owner approval for non-original assets |
| A physical device is not available | medium | medium | state Android as untested in the release notes |

## 7. Approvals the owner must give before release
Release v0.1.0; merge strategy; the version number for the slice; asset sources and licences; any balance change; boss threshold; the Android signing approach; making the repository's release notes public.
