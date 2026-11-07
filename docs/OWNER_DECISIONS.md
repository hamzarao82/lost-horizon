# Decisions waiting on the owner

Status date: 2026-11-08. Each item blocks or shapes work; none has been decided by the project on its own.

## Story and campaign
| # | Decision | Why it matters | Recommendation |
|---|---|---|---|
| 1 | Is the campaign **five regions** (Outpost 17, Dead Coast, Blackwood, Research Complex, Iron Fortress) or the **three** named in the Milestone 11 and 12 briefs? | Dead Coast and Blackwood already exist and are required by the unlock chain; every acceptance list assumes one answer | five |
| 2 | Approve the protagonist backstory used in the ending (a witness aboard the transport) | it is the narrative bible's proposal; no existing text establishes the protagonist's reason for being on the island | approve, or supply your own |
| 3 | Resolve the five open contradictions in `CAMPAIGN_AUDIT.md` (the first mission's terminal points to the Research Complex while the next destination is Dead Coast; "Project Black Site is no longer a secret" in Act I weakens Act III; the radio voice has two identities; Subject 14 is in two facilities with different timelines; "R. Hale" and "Dr. Hale" are unconnected) | each is a text edit that changes the story | pick one resolution per item; the audit proposes one |

## Gameplay numbers
| # | Decision | Notes |
|---|---|---|
| 4 | Arena completion reward: 100 XP and 120 credits once | chosen by an agent, not requested; keep, change or remove |
| 5 | Boss and elite difficulty, XP curve, loot rates | all come from formulas and bots; nobody has played them; a human playtest is the only real check |

## Release and publishing
| # | Decision | Notes |
|---|---|---|
| 6 | Create the **v0.1.0** public release (Windows zip, Android APK; assets exist locally) | a public release was blocked by the permission system and needs explicit approval |
| 7 | Seven Dependabot pull requests (major version bumps) | each needs a build check before merging |
| 8 | Push order: `master` was last pushed before Milestones 9 to 12 work; the later work is merged locally only | push after the full suite is clean |
| 9 | Android signing: debug-signed APK today | a release keystore must be created and kept private by the owner; never committed |

## Product direction
| # | Decision | Notes |
|---|---|---|
| 10 | Ads: Android first, rewarded ads only, with a consent flow and test ids; or none | a plan is not written; best after Milestone 14 |
| 11 | Backend scope: cloud saves and an optional leaderboard, or something else | saves are versioned, so cloud saves fit; secrets must stay out of the public repository |
| 12 | Whether Milestone 13 (graphics) can use art you provide | free libraries reachable here have no rigged characters or detailed foliage and vehicles |

## Things only a person can do
- Play through the game from the menu to the ending and write down what feels wrong (combat feel, difficulty, navigation, readability). Nothing beyond the first minutes has ever been played.
- Run the Android build on a phone.
- Listen to the audio; every sound is generated and unheard.
