# SDD ledger — plan: docs/superpowers/plans/2026-09-12-milestone-1-boots-and-is-cedar.md

Spec: docs/superpowers/specs/2026-09-12-cedar-cosmic-design.md (read; binding authority)
Branch: milestone-1 (created from main @ 95ff2ca, feature-branch-in-place per user)
Baseline: docs-only, no test suite, clean.

## Pre-flight conflict scan

### Shared files across tasks

| File | Tasks | Producer → consumer | Finding |
|---|---|---|---|
| `Containerfile` | 2 create, 3/5/6 modify | Each appends before `bootc container lint` | OK — Global Constraint requires lint last; all three inserts respect it |
| `test/test-image.sh` | 2 create, 5 append | 5 appends before `summary` | OK — plan states `summary` must stay last (sets exit status) |
| `test/boot-chain.sh` | 4 create, 5 modify | 5 removes `initramfs.img` from the hash set | OK sequentially; see Ruling 2 |
| `Justfile` | 2 create | `test` recipe calls `boot-chain.sh` (Task 4) | OK — plan states it reports missing until Task 4; Tasks 2 and 3 invoke `./test/test-image.sh` directly, not `just test` |
| `branding/` | 5 create, 6 adds policy files | Disjoint filenames | OK |

### Interfaces

| Producer | Consumer | Finding |
|---|---|---|
| T1 → base digest | T2 `FROM`, T4 `CEDAR_BASE`, T6 CI env | **Three substitution sites for one value** — see Ruling 1 |
| T1 → EFI payload paths | T4 hardcoded `find` paths | OK — T1 Step 5 records them, T4 Step 2 says fix the script if they differ |
| T2 → `check`, `check_file_exists` | T3, T5 | OK — signatures defined once in `lib.sh` |
| Prereq → `NAMESPACE` | T2 README, T6 policy.json/CI, T7 rebase | OK — bound once in Prerequisites, stated as global |

### Per-task self-consistency

| Task | Finding |
|---|---|
| 1 | Consistent. Notes dir created in Prerequisites (was a gap in draft 1). |
| 2 | Consistent. Test asserts `OSTREE_VERSION` present and expects it to PASS on the base — correct, rpm-ostree injects it during the base compose. |
| 3 | Consistent. Three load-bearing seds called out explicitly. |
| 4 | Consistent, and correctly declines the red/green framing — a guard is green on a correct image. |
| 5 | Consistent. Step 6 deliberately shows the guard going red and then narrows it, with the reason stated. |
| 6 | Consistent. |
| 7a/7b | Consistent. Requires hardware the plan does not provision — flagged in Prerequisites. |

## Rulings

- **Ruling 1: the base digest is recorded once and referenced, not retyped.** Task 1 writes it to the notes file; Tasks 2, 4 and 6 must copy it from there verbatim. Three independent transcriptions of one sha256 is a divergence waiting to happen — and a divergence between the `FROM` digest and `CEDAR_BASE` makes the boot-chain guard compare Cedar against an image it was not built from, which is exactly the failure the digest pin exists to prevent. Cost if wrong: a false-failing or false-passing Secure Boot guard.
- **Ruling 2: Task 4's red-proof goes stale after Task 5.** Task 4 Step 3 proves the guard can fail by appending to `initramfs.img`; Task 5 Step 6 then removes `initramfs.img` from the hash set, so re-running that proof later would silently pass. The proof is still valid when performed (Task 4 completes before Task 5), so the plan is not wrong — but I am recording that any future re-proof must mutate a file still in the set (an EFI binary or `vmlinuz`). Cost if wrong: a future reader re-runs a proof that cannot fail and concludes the guard works.
- **Ruling 3: GitHub repository creation moves from Prerequisites to immediately before Task 6.** Tasks 1–5 are entirely local and need no remote. Creating a repo under the user's GitHub account and pushing to it is an outward-facing side effect, which this skill lists as a stop-and-ask condition. Deferring it lets Tasks 1–5 run unattended and puts the ask at the point of genuine need. Cost if wrong: none material; the plan's own Prerequisites note says only Task 6 pushes.
- **Ruling 4: Task 7 is out of scope for this execution.** It requires a VM with Secure Boot on x86_64 hardware that cannot be provisioned from here. Execution stops after Task 6 and hands the user a checklist. Cost if wrong: none — the plan already isolates 7a/7b as manual.

## Progress

## Updates from user (18:48)

- **Deployment target is x86_64 hardware running VMware ESXi**, not this Mac. The
  Mac is a build host only. Task 7's VM is an ESXi guest.
- **GitHub: authed as `cedarlinux`, repo creation authorised by the user.**

- **Ruling 3 SUPERSEDED.** The user authorised repo creation directly, so it no
  longer waits for Task 6. Created `cedarlinux/cedar` (private), remote `origin`
  set, `main` and `milestone-1` pushed. `NAMESPACE=cedarlinux`, so the image is
  `ghcr.io/cedarlinux/cedar` — which matches the `cedarlinux.org` URLs already in
  the spec's os-release fields. Execution no longer stops before Task 6.
- **Ruling 5: repo starts private.** Nothing is built yet and a half-finished
  distro repo is not worth publishing; flipping to public later is free. Note
  this is independent of the *package* visibility, which Task 6 Step 8 must set
  to public regardless, or `rpm-ostree rebase` fails anonymously with a 401.
  Cost if wrong: none, reversible in one click.
- **Ruling 6: the local `gh` token lacks `write:packages`** (scopes are gist,
  read:org, repo, workflow). This does not block anything — CI pushes to ghcr.io
  using Actions' `GITHUB_TOKEN` with the workflow's `packages: write` permission,
  and nothing pushes packages from this machine. Recorded so a later failure is
  not misdiagnosed. Cost if wrong: a local `podman push` would 403; use CI.

- **RISK for Task 7, new: COSMIC on ESXi graphics.** cosmic-comp is a Wayland
  compositor and needs working DRM/KMS. ESXi's virtual GPU (`vmwgfx`) provides
  that, but 3D acceleration is limited and COSMIC may fall back to software
  rendering — with the 1.3+ frosted-glass effects that could be slow or broken.
  This is not a milestone 1 blocker (Task 7 only needs it to reach the greeter)
  but it must be verified before Cedar is treated as a daily driver, and it is a
  question the spec never considered because the spec assumed bare metal.
  Recorded as input to Task 7 and to the milestone 5 decision.

## Update from user (18:50) — test target changed again

Task 7 target is now a **spare x86 mini PC, bare metal**, currently running
Omarchy and erasable. This supersedes the ESXi plan for Task 7.

- **The ESXi graphics risk is downgraded, not closed.** Bare metal gives real
  DRM/KMS, so COSMIC is tested honestly. If ESXi remains a deployment target
  later, the vmwgfx/software-rendering question returns and must be answered
  then.
- **Bare metal makes Task 7 a materially better test.** Real UEFI firmware, real
  Secure Boot implementation, real GPU — the milestone's central claim
  ("boots with Secure Boot enabled") is now tested against the thing it claims
  about rather than a hypervisor's emulation of it.
- **Open, blocking Task 7 (not Tasks 1-6):**
  1. GPU vendor. NVIDIA makes the MOK-enrollment problem live at first boot
     and there is no X11 fallback (Plasma 6.8 removed it; COSMIC is Wayland
     only). Intel/AMD is clean.
  2. Whether the firmware is UEFI and whether Secure Boot is available and
     currently enabled. Omarchy is Arch-based and is commonly installed with
     Secure Boot off; if so it must be re-enabled or Task 7b tests nothing.
  3. Whether anything on the Omarchy install needs preserving before erasure.
- **No erasure is needed yet.** Tasks 1-6 are build-host work. The machine is
  only required at Task 7.

### Task 7 hardware confirmed (18:51)

| | |
|---|---|
| GPU | Intel HD Graphics 520, Skylake-U GT2 (`8086:1916`) |
| Firmware | UEFI |
| Secure Boot | **disabled, in SETUP MODE** |
| Disk | 1.8 TB SanDisk SSD (`sda`, SATA) |

- **NVIDIA risk is CLOSED for this machine.** Integrated Intel, driven by `i915`
  — in-kernel, signed by Fedora, Wayland-mature. No DKMS, no MOK enrollment, no
  black-screen-at-first-boot scenario. The single worst item in the spec does not
  apply to Cedar's own test hardware. (It returns the moment Cedar runs on an
  NVIDIA machine, so the spec's open item stands.)
- **Secure Boot is in SETUP MODE, which is not the same as merely disabled.**
  Setup mode means the Platform Key has been cleared — typical after an Arch
  install that wiped keys. Enabling Secure Boot is therefore not a single
  toggle: firmware must first **restore/enroll factory default keys** (usually
  "Restore Factory Keys" or "Enroll default Secure Boot keys" in BIOS setup) so
  Microsoft's CA is present, and only then can Secure Boot be enabled. Without
  Microsoft's CA, Fedora's shim will not validate and Cedar will not boot.
  **This is a prerequisite for Task 7b and must be done in firmware, before
  installing.** Cost if skipped: Task 7b silently tests nothing.
- Disk is ample. Note `sda` (SATA), not NVMe — irrelevant to correctness, but
  installs and image pulls will be slower than on NVMe.
- Skylake supports x86-64-v3, so any Fedora baseline raise is not a concern.

- **Ruling 7: Task 6 verifies CI via `workflow_dispatch` on `milestone-1`, not by
  merging to main first.** The workflow triggers on `push: branches: [main]`, and
  we are on `milestone-1`, so a push will not fire it. Merging an unverified CI
  workflow to main just to test it is backwards. The workflow already declares
  `workflow_dispatch`, so Task 6 Step 7 becomes
  `gh workflow run build.yml --ref milestone-1 && gh run watch`. The `on: push`
  trigger stays as written and starts working naturally at merge.
  Cost if wrong: none — manual dispatch exercises the identical job graph.

## Task 1

Result: DONE_WITH_CONCERNS, commit c76f7dd. COSMIC **1.8.0-1.fc44** confirmed
from the composed image — staleness risk closed, base choice validated.
CEDAR_BASE = quay.io/fedora-ostree-desktops/cosmic-atomic@sha256:2535cf2c9b20c4827537baa08605e6ae0254118e1b1a8ca19a1ada250e9cd293

- **Ruling 8: Task 4's hash set is redefined.** The plan's EFI paths were wrong —
  a reviewer asserted them and I wrote them in without verifying. Reality in this
  image: `/usr/lib/ostree-boot/efi` is EMPTY; `/usr/lib/bootupd/updates/{EFI,BIOS}.json`
  are bootupd metadata, not binaries; the signed payload is at
  `/usr/lib/efi/grub2/<evr>/EFI/fedora/` and `/usr/lib/efi/shim/<evr>/EFI/{BOOT,fedora}/`,
  with rpm EVRs baked into the path segments.

  Task 4 hashes, via `find` over whole trees so the EVR segments need no globbing:
    * `/usr/lib/efi` — the actual signed binaries (~15 files)
    * `/usr/lib/bootupd/updates/*.json` — bootupd's manifest; it records
      `grub2-1:2.12-64.fc44,shim-16.1-5`, so a payload version change trips it
    * `/usr/lib/modules/*/vmlinuz`
  and deliberately does NOT hash:
    * `/usr/lib/ostree-boot/efi` — empty, nothing to guard
    * `/usr/lib/bootupd/grub2-static/` — GRUB config fragments, not signed
      binaries, and plausibly something Cedar edits later; guarding them would
      produce a false failure on legitimate work
  MIN_FILES rises from 6 to 12 (observed count is ~26), so a partial result is
  still caught while leaving headroom if Fedora restructures.
  Cost if wrong: the guard watches the wrong files and the Secure Boot
  constraint goes unenforced — the exact failure this guard exists to prevent.

- Task 1: minor (deferred): my dispatch told the implementer
  `docs/superpowers/notes/` already existed. It did not — I listed the `mkdir` as
  a Prerequisite and never ran it. The implementer created it. No impact.
Task 1: review clean (spec ✅, quality approved).
Task 1: minor (deferred): report claims "full command transcripts for Steps 3-6"
  but Step 6 is recorded as prose conclusions only. Notes content is correct and
  the brief only asked for terse values there; the report's self-description
  overstates it. No action.
Task 1: complete (commits f909d30..c76f7dd, review clean)

## Secure Boot (user, 18:57)

User ran `sbctl create-keys` + `sbctl enroll-keys --microsoft` on the target
machine. Microsoft CA is enrolled (`Vendor Keys: microsoft`) but `sbctl status`
still reports Setup Mode enabled and Secure Boot disabled — PK enrolment has not
taken effect yet; needs a reboot and a firmware toggle.

- **Ruling 9: Task 7b's Secure Boot result must be reported precisely.** The
  machine will carry the user's own PK/KEK plus Microsoft's CA in db, not factory
  keys. Fedora's shim validates fine against Microsoft's CA, so the test is valid
  — but it proves "Cedar boots under Secure Boot with Microsoft's CA enrolled",
  NOT "Cedar boots on stock factory-key firmware". Those differ, and the spec's
  claim is about the latter. Task 7b records which was tested.
  Cost if wrong: an overstated Secure Boot claim in the spec.

## Task 2

Result: DONE, commit 63c6332. Scaffold, test harness, Justfile, README.
Review: spec ✅, quality approved, no Critical/Important. Reviewer independently
RAN the artifacts rather than reading the diff: confirmed check() captures the
exit code (avoiding the `local x=$(cmd)` antipattern that masks $?), FAILURES
increments survive, summary's return becomes the script exit status (verified
exit 1), and `just test` runs BOTH suites when the first fails — the shebang
recipe works as intended. Controller separately verified the Containerfile digest
matches Task 1's notes and no `<namespace>`/`<DIGEST_FROM_TASK_1>` placeholder
survived into a committed file.

Task 2: minor (deferred): report says `<namespace>` was replaced "in both
  occurrences" in README.md; only one occurrence exists. Report-only, cosmetic.
Task 2: confirmed for Task 3: the base os-release has NO `ID_LIKE` line at all
  (verified twice — implementer and reviewer). Task 3's sed replaces `ID=fedora`
  with `ID=cedar` + `ID_LIKE="fedora"`, i.e. it ADDS the key. No duplicate risk.
Task 2: complete (commits 6f4e6e4..63c6332, review clean)

## Task 3

Result: DONE, commit fb1070e. Identity layer: 9 seds on /usr/lib/os-release,
/etc/system-release written, EFIDIR pinned to "fedora" in grub2-switch-to-blscfg.
All 4 test-image.sh checks pass (the 3 identity assertions flipped red->green and
OSTREE_VERSION stayed green, i.e. the in-place sed preserved it as intended).
bootc container lint passed (13 checks, 1 skipped) and remains the final
instruction. Touched only Containerfile.

Implementer flagged an unrecognised unstaged diff on the plan file — that was the
controller's Ruling 7 commit (ce041a0) landing mid-task. Benign; correct to flag.
Review scoped to ce041a0..fb1070e so the controller's own edit is not reviewed as
Task 3's work.
Task 3: review clean (spec ✅, quality approved). Reviewer verified against the
  BASE image, not just the diff: original EFIDIR was a dynamic derivation
  `EFIDIR=$(grep ^ID= /etc/os-release ...)`, now static `EFIDIR="fedora"` —
  positive proof the sed fired rather than matching nothing.
  OSTREE_VERSION='44.20260912.0' intact.

- **Ruling 10: three stale Fedora keys in os-release, handled in Task 5, not by
  reopening Task 3.** Reviewer found `CPE_NAME`, `DEFAULT_HOSTNAME=fedora` and
  `LOGO=fedora-logo-icon` survive and now contradict `ID=cedar`. This is a gap in
  the brief I wrote, not an implementer deviation. Disposition, per key:
    * `CPE_NAME` **stays as Fedora deliberately.** It feeds CPE-based CVE and
      asset scanners, and Cedar's packages genuinely ARE Fedora 44 packages, so
      matching Fedora 44 advisories is the *accurate* result. Changing it to
      `cpe:/o:cedarlinux:cedar:44` would match no known CVE database and silently
      make Cedar look vulnerability-free. My spec's draft os-release had the
      cedarlinux CPE; that was wrong and the spec should be corrected.
    * `DEFAULT_HOSTNAME` → `cedar`. New installs otherwise come up named
      "fedora". Real, user-visible, trivial.
    * `LOGO` → `cedar-logo-icon`, but only in Task 5, which is where the logo is
      actually installed. Setting it in Task 3 would point at a nonexistent icon.
  Cost if wrong: CPE choice is the load-bearing one — getting it backwards means
  either false-clean vulnerability scans or noisy false positives.

Task 3: complete (commits ce041a0..fb1070e, review clean)

## Task 4

Result: DONE, commit bc2182e. test/boot-chain.sh only; Containerfile clean.
Exit codes observed 0 -> 1 -> 0 across Steps 2/3/4; the Step 3 failure diff named
only the initramfs.img line. 17 files hashed, which reconciles exactly against
Task 1's inventory: 13 under /usr/lib/efi (2 grub2 + 4 shim/BOOT + 7
shim/fedora), 2 bootupd manifests, vmlinuz, initramfs.img.

Controller independently verified:
  * exit 0, 17 files on the correct image
  * **exit 2 (not 0) on a nonexistent image** — the fails-open defect from the
    first draft is confirmed fixed; a broken guard can no longer print ok
  * no rpm EVR is hardcoded in any executable line; the only occurrence of
    `2.12-64`/`16.1-5` is inside an explanatory comment, and the hashing lines
    walk `/usr/lib/efi` wholesale so the version segments need no globbing
Task 4: fix round 1/5 (7 addressed, 0 open — MIN_FILES gap, off-by-9 comment,
  misconfig exit code, just-test-cannot-pass, symlinks, cosmetic padding, new
  EFIDIR assertion; commits bc2182e..48df988)
  Controller verified: MIN_FILES=17; per-subtree non-empty assertions for
  /usr/lib/efi/{grub2,shim} inside the manifest sh -c; CEDAR_BASE now defaults
  from the Containerfile's own FROM line (resolves to the correct digest), so
  the guard is structurally incapable of comparing against an image the build
  did not use — Ruling 1 enforced mechanically rather than by transcription;
  find now catches symlinks; EFIDIR content assertion added to test-image.sh.

- **Ruling 11: this guard is necessary but NOT sufficient for milestone 2, and
  the spec must say so.** The review established that it validates the bytes
  sitting in the image and says nothing about how those bytes reach an ESP.
  Three concrete blind spots, each verified green while broken:
    * `/usr/sbin/grub2-switch-to-blscfg` — Cedar edits it today; it selects the
      ESP vendor directory. Now covered by a content assertion, not a diff.
    * `/usr/lib/bootupd/grub2-static/*` — deliberately unhashed, but these files
      BECOME the ESP's grub.cfg, so Cedar can change what signed GRUB executes
      while the guard stays green by design. Defensible for milestone 1;
      materially riskier for an ISO.
    * Unsigned kernel modules under /usr/lib/modules/<kv>/extra/.
  Milestone 2 needs a second check that mounts the generated ESP and asserts
  EFI/BOOT/BOOTX64.EFI and EFI/fedora/grubx64.efi hash-match /usr/lib/efi/.
  Cost if wrong: an ISO that bricks a machine while CI is green.
Task 4: fix round 1 re-review — all 7 ADDRESSED, no new breakage. Verified by
  execution: grub2-absent-from-both-sides now exits 2 (was 0 with 15 files);
  a flipped byte in grubx64.efi (0x30->0xAA, confirmed different first) exits 1
  naming the file; an EFIDIR="wrongvendor" image makes the new assertion FAIL,
  proving it is not a tautology; malformed Containerfile with CEDAR_BASE unset
  exits 2 rather than guessing; an explicit bogus override is honoured, not
  silently replaced by the derived default.
Task 4: minor (deferred): `CEDAR_BASE=""` with a readable Containerfile falls
  back to the derived default, because ${VAR:-…} treats empty and unset alike.
  Defensible ("no override" ≈ "use default") but an explicit empty override is
  not itself flagged. Not blocking.
Task 4: complete (commits fb1070e..48df988, review clean)

- **Ruling 12: Task 5 must lower MIN_FILES 17 -> 16 in the same edit that drops
  initramfs.img.** This conflict did not exist at pre-flight — fix round 1
  created it by raising the floor from 12 to 17. Composition verified by
  execution: 13 files under /usr/lib/efi + 2 bootupd manifests + vmlinuz = 16
  once initramfs.img is removed. Leaving the floor at 17 makes the guard exit 2
  and report ITSELF broken, which would read as Task 5 having damaged it, and
  the likely reaction is to weaken the guard rather than fix the floor. Plan
  amended so the brief carries it. Cost if wrong: a self-inflicted exit 2 that
  invites exactly the well-intentioned weakening this guard's history is about.

## Task 5

Result: complete, commit 8268208. boot-chain exit 0 with **16 files** — Ruling 12's
floor adjustment landed correctly. `just test` full pass, 13/13 checks.

- **CONTROLLER ERROR (mine): `git add -A` in a shared working directory while a
  subagent was mid-task.** Commit aedc8e7, whose message describes a plan-file
  correction, also contains 18 lines of Task 5's `test/test-image.sh` work that
  the implementer had already written to disk. Content is correct and the
  implementer verified it byte-identical to its intent, but commit attribution is
  now misleading: Task 5's changes to that file are split across aedc8e7 and
  8268208. The implementer caught it and flagged it, which is the only reason it
  is recorded rather than silently wrong.
  Lesson: stage explicit paths, never `-A`, while a subagent shares the tree.
  Task 5's review is therefore scoped 362b4fb..8268208, with the reviewer told
  which parts of aedc8e7 are the controller's and which are Task 5's.

- Task 5: minor (deferred): podman machine's default 2 GiB RAM caused flaky
  ENOMEM failures on branding COPY steps; the implementer raised it to 4 GiB.
  Local environment only — no image change, and CI runners are unaffected. Worth
  noting in the README if anyone else builds locally.
Task 5: review clean (spec ✅, quality approved, NO findings). Verified live:
  initramfs regenerated at /usr/lib/modules/7.2.4-200.fc44.x86_64/initramfs.img
  with --add ostree confirmed effective via lsinitrd finding ostree-prepare-root
  (not merely the flag being present); watermark genuinely replaced (Cedar 1388
  bytes / 8120e15e vs base spinner 3726 bytes / 5cc9961a); MIN_FILES 17->16 in
  the same edit with comment updated; guard exit 0 at 16 files; CPE assertion
  present and not inverted; DEFAULT_HOSTNAME=cedar, LOGO=cedar-logo, and
  /usr/share/pixmaps/cedar-logo.svg exists; 13/13 checks; just test passes;
  Containerfile still ends with bootc container lint; no scope creep.
Task 5: complete (commits 362b4fb..8268208, review clean)

## Task 6

Result: Steps 1-6 complete, commit 4466990 pushed. Step 7 BLOCKED by a real
GitHub constraint. Image NOT built, pushed or signed; no CI run occurred.

Done: cosign key generated, SIGNING_SECRET stored, cosign.key deleted and
verified absent from all commits; policy.json, ghcr.yaml, build.yml, nightly.yml
created; Containerfile still ends with bootc container lint; explicit-path
staging used (no `git add -A`).

- **Ruling 7 was WRONG, and this supersedes it.** I ruled that Task 6 would
  verify CI via `workflow_dispatch` on milestone-1 rather than merging an
  unverified workflow to main. That mechanism does not exist: GitHub only
  catalogs a workflow for `workflow_dispatch` once it is present on the DEFAULT
  branch; `--ref` chooses which ref's content runs but cannot discover an
  un-indexed workflow. Verified independently by API: `actions/workflows`
  total_count = 0, origin/main contains no `.github/` at all, origin/milestone-1
  has both workflow files, branch is 13 commits ahead, default branch is main.
  I reasoned about what ought to be true instead of checking what GitHub does.
  Cost of the error: one blocked task and a decision pushed to the user, no
  wasted implementation.

- **Ruling 13: CI cannot be verified before milestone-1 reaches main, so the
  final whole-branch review runs FIRST and the merge becomes the user's call.**
  Both routes to a CI run (merge, or seed the workflow onto main) are pushes to
  a shared branch, which this skill lists as stop-and-ask. Running the final
  review before asking means the branch the user is deciding about has been
  reviewed as a whole rather than only task by task. Cost if wrong: none — the
  review is needed regardless of which route is chosen.

## Final whole-branch review — VERDICT: do not merge, fix first

3 Critical, 7 Important, 9 Minor. All Criticals verified by execution and all
three surface only on the first real CI run — the run that publishes a signed
public image. Merging before this review would have made Cedar's first published
artifact a broken one.

- C1 the committed Containerfile DOES NOT BUILD: `bootc container lint` rejects
  /usr/etc. localhost/cedar:dev predates Task 6, so Task 6's Containerfile edits
  had never been built by anyone — including in my own "verification" runs, which
  I reported as current against a stale image. Plan was wrong (/usr/etc);
  implementation was faithful.
- C2 cosign 3.x writes OCI referrers; containers/image reads the legacy
  sha256-<digest>.sig tag. Proven against a local registry with two negative
  controls. Cedar's policy/matchRepository/ghcr.yaml are all CORRECT; the cosign
  version is the bug. CI would publish, report a green sign step, and every
  signed rebase would fail.
- C3 COSIGN_PASSWORD unset -> cosign takes the terminal path and dies on a runner.
- I5 the "initramfs regenerated" check is a TAUTOLOGY — the untouched base
  already has that file. Drop --add ostree and everything stays green while the
  image is unbootable.
- I6 the SPEC still names the EFI paths Task 1 disproved. I fixed the plan in
  aedc8e7 and the ledger, and left the spec asserting the payload lives in an
  empty directory. Second time I fixed an instance and left the source.
- I2 nightly.yml is broken (permissions) AND harmful: FROM is digest-pinned, so a
  weekly rebuild picks up no updates but mints a new digest, pushing a ~6 GB
  no-op upgrade to every Cedar machine weekly.

Ledger triage accepted as given: Rulings 2, 4, 6, 9, 11 stand as recorded; the
aedc8e7 history error is not to be rewritten on a pushed branch; Ruling 5 and
Task 5's 4 GiB note move into the runbook/README.

- **Ruling 14: Task 7 never ran, and that must be stated wherever milestone 1 is
  called complete.** Nothing has rebased onto Cedar, booted it, run
  `bootupctl update`, or tested rollback. The milestone's central claim —
  "it boots and it is Cedar" — is untested. Cost if wrong: declaring a milestone
  complete on the strength of a guard that has never faced firmware.

## Final fix wave

Commit d6634f0 (4466990..d6634f0), pushed to origin/milestone-1. main untouched.
All 11 items done in a single wave: C1 /usr/etc->/etc + policy keyPath;
C3 COSIGN_PASSWORD=""; C2 cosign pinned v2.4.3 with an explanatory comment;
C4 new CI step verifying the pushed digest through Cedar's OWN policy.json and
ghcr.yaml; I4 signature-policy assertions in test-image.sh; I3 cancel-in-progress
PR-only; I7 free-disk-space pinned to SHA 54081f1 (v1.3.1); I1 two-hop README
install + 4 GiB podman note; I2 nightly.yml deleted with the intended
scheduled-digest-bump replacement recorded as a comment; I5 tautological
initramfs check replaced with a real ostree-prepare-root content check;
I6 spec EFI paths and initramfs-hash claim corrected.

Implementer verification (executed): bootc container lint 13 passed / 1 skipped;
just test full pass; a second image built WITHOUT --add ostree makes the new
initramfs check FAIL while the old one stayed green; a throwaway registry proved
cosign v3's signature is rejected under Cedar's own policy.json while the same
digest signed with v2.4.3 verifies.

Controller verification (executed): policy files present at /etc with /usr/etc
absent from the image; keyPath correct; nightly.yml gone; cosign-release v2.4.3,
COSIGN_PASSWORD "", cancel-in-progress PR-gated, action SHA-pinned in build.yml.

## Fix-wave re-review — 10 of 11 ADDRESSED

Verified by execution throughout. Finding 10 confirmed genuinely fixed, not a
replacement tautology: in an image built without --add ostree, lsinitrd parses
4950 entries and finds 0 ostree-prepare-root (vs 3 in the good image) and the
check FAILS, while the old check exits 0 on that same broken image. Finding 11
spec paths verified real in the image. No new breakage: lint 13/1, all 18
assertions pass, boot-chain still exits 1 on a byte appended to BOOTX64.EFI,
exactly seven files touched, cosign.key absent from every reachable git object
(history scanned for private-key headers).

- **Finding 4 NOT ADDRESSED.** The CI verify step cannot pass on a runner:
  branding/policy.json's keyPath is the absolute /etc/pki/containers/cedar.pub,
  which exists only inside the Cedar image; Ubuntu has no /etc/pki at all. Every
  push to main goes red AFTER push and sign succeed, and verify-public
  (needs: build) is skipped. The guard I demanded to prove C2/C3 delivers zero
  coverage while turning CI red. Its design is otherwise correct — right digest,
  real policy files, set -euo pipefail, and a missing signature genuinely fails
  it rather than being swallowed.

- **Ruling 15: fix finding 4 before merge rather than parking it.** The reviewer
  confirms the published artifact is NOT compromised — the step fails on a
  missing file before signature evaluation, so it can neither reject a good
  signature nor mask a bad one, and a Cedar machine rebasing off that artifact
  verifies fine. So this is parkable in principle. I am ruling to fix it anyway:
  it is one reviewer-specified line, Task 7 depends on trusting the published
  image, and merging with a known-red CI means the very first signal Cedar ever
  emits is a false alarm — which trains everyone to ignore it. Cost if wrong:
  one extra commit before merge.

- Deferred, recorded, not blocking: policy scope hardcodes ghcr.io/cedarlinux/cedar
  while the workflow computes ghcr.io/${OWNER,,}, so on a fork the default
  insecureAcceptAnything makes verification a vacuous pass; Push precedes Sign,
  leaving a window where a pull gets an unsigned image (pre-existing); only :44's
  digest is signed, same manifest as :latest today but not if they diverge; both
  skopeo steps assume it is preinstalled on ubuntu-24.04, unverified.
