# Branch and release rules (proposal)

Status: **proposal**. Nothing on GitHub has been changed. The maintainer applies these rules in the repository settings after reading this page. Each rule says what it protects.

## Branches

| Branch | Use | Rule |
|---|---|---|
| `main` | The product, as released or about to be | Protected: see below |
| `alpha/windows`, `alpha/android`, `alpha/ios` | Alpha work for one system | Not merged through a pull request until it lands on `main`. No force-push, no deletion |
| `feat/*`, `fix/*`, `chore/*`, `docs/*` | Short work branches | Named by topic, never after an agent or a tool. Deleted after merge |
| `release/*` | A release line when two versions must be kept | No force-push |

Name branches after the work, not after the tool that made them.

## `main`

- A pull request is required to change `main`. Direct pushes are refused, including by the maintainer.
- Required status check: **`Checks`**, the single verdict of `.github/workflows/ci.yml` (the rules, and every Mac job when Swift changed). The old names `Mac / tests`, `Mac / checks` and `Mac / Swift tests` no longer exist.
- A job skipped by its path filter counts as passing for a required check in GitHub. `Checks` always runs (`if: always()`), so it is never skipped.
- Review: the code owners in `.github/CODEOWNERS` are the maintainer. The maintainer cannot approve their own pull request, so the approval count stays at **0** while the maintainer is the only reviewer. Raise it to 1 when a second reviewer exists.
- Conversations must be resolved before merging.
- Force-push and deletion are blocked.
- Merge commits stay allowed: the existing history uses them, and rewriting it is not needed.

## Tags and releases

- Protect tags matching `v*` and `*-v*`, for example `v0.5.0` and `windows-v0.1.0-alpha.1`. Only the maintainer creates them.
- A release is created by `scripts/release.sh`, run by the maintainer. CI checks the code and does not publish anything. See the release section of [development](development.md#release-packaging).
- A release tag never moves. A fix is a new version.

## Commits and identity

- Commits are made with the project identity. Keep the authors of imported commits unchanged, as [CONTRIBUTING](../../CONTRIBUTING.md) explains.
- Signed commits are **not** required now. Requiring them is a later choice, once the maintainer's signing key is set up outside the repository.

## Decisions to take before applying

1. Accept the single required check `Checks`.
2. Confirm that a skipped job satisfies the required check, on a test pull request.
3. Choose the approval count: 0 while the maintainer is alone.
4. Decide whether administrators are bound by the rules. The recommendation is yes, so that no rule can be bypassed silently.

State read on 25 November 2026, read-only: no repository ruleset, and `main` has no branch protection (the API answers 404). Tags exist for the releases already published, for example `v0.5.0-beta.3`, `windows-v0.1.0-alpha.1` and `ios-v0.1.0-alpha.1`. Read the state again before applying anything.
