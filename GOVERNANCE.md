# Governance

IPTether is an open-source project started and sponsored by And AI Platforms. It's run by its
maintainers, listed in [MAINTAINERS.md](MAINTAINERS.md).

## Roles

- **Users and contributors**: anyone who uses IPTether, reports issues, joins discussions or sends
  pull requests. Contributions are welcome from everyone under the
  [Code of Conduct](CODE_OF_CONDUCT.md).
- **Maintainers**: review and merge pull requests, triage issues, cut releases and enforce the Code
  of Conduct. They're the members of the `@andai/iptether-maintainers` team on GitHub.

## How decisions are made

- Most decisions happen in pull requests and issues. A change merges once CI passes and a
  maintainer approves it.
- Bigger changes go in an issue or discussion first, and stay open long enough for others to
  comment. Bigger means new cloud providers, changes to what IPTether is allowed to modify, new
  permissions, or breaking config changes.
- Maintainers aim for consensus. If they can't reach it, the maintainers employed by And AI
  Platforms make the final call and record why in the issue.
- Some rules don't change without a public discussion: IPTether only edits rules carrying its own
  marker, and it never handles cloud credentials.

## Releases

- Maintainers cut releases from `main`, version them with
  [Semantic Versioning](https://semver.org/), and record changes in [CHANGELOG.md](CHANGELOG.md).
- Release builds are signed and notarized by And AI Platforms.

## Becoming a maintainer

Contributors who've made sustained, high-quality contributions (code, reviews, docs or triage) can
be nominated by an existing maintainer. The maintainers decide together, and the new maintainer is
added to the GitHub team and to [MAINTAINERS.md](MAINTAINERS.md). Inactive maintainers may step
down or be moved to emeritus.

## Changes to this document

Changes to governance go through a pull request that stays open for at least a week, and need
approval from a majority of maintainers.
