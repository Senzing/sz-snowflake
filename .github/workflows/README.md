# Workflows

Two groups. The **standard set** is the organization-wide thin-caller set,
copied unchanged from a sibling repository; each file is a trigger,
`permissions: {}`, and one job whose only content is `permissions:`, optional
`secrets:`, optional `with:`, and a `uses:` naming a reusable workflow in
[senzing-factory/build-resources]. The **repository build** is specific to this
repository and is documented in its own header.

First-party reusables are consumed at the floating major tag `@v4`; third-party
actions are pinned to a full commit SHA.

## Repository build

### docker-build-and-publish.yaml

Builds the evaluation container. A pull request builds only; a published
release builds, pushes to GHCR, signs and attests. There is deliberately no
`workflow_dispatch` on the publish path -- tag creation here is restricted by
ruleset, and that restriction is what separates "merged" from "published".

**This workflow authenticates to nothing outside this repository.** The
application payload is built elsewhere and pushed here as a release asset; the
workflow reads that asset from this repository's own releases with its own
`GITHUB_TOKEN`, and pushes the image to this organization's own registry with
the same token. There is no App key, no token for another repository, and
nothing whose value has to be masked out of these public logs.

That is a reversal of the previous design, which handed a GitHub App private
key to `pull_request` runs. A non-fork pull request receives secrets _and_
runs the workflow definition from the pull request head, so anyone with write
on a public repository in this organization could have added a step that
exfiltrated it. Nothing added to _this_ file can recreate that exposure,
because there is no longer a credential here that reaches anything else -- keep
it that way. The claim is about this workflow only: the standard-set workflows
below still pass secrets on `pull_request`, so the repository as a whole has
not shed that shape.

The publish job refuses to overwrite an image tag that already exists in the
registry. The rulesets stop a tag being created, moved or deleted; they do not
stop a second release being created on an existing tag, so the registry check
is what makes a published version immutable.

## Standard set

### add-labels-standardized.yaml

When an issue is opened or reopened, labels it (`triage`,
`customer-submission`).

- Uses: [senzing-factory/build-resources/.../add-labels-to-issue.yaml]

### add-to-project-senzing.yaml

When an issue is opened or reopened, adds it to the organization project board
as "Backlog".

- Uses: [senzing-factory/build-resources/.../add-to-project.yaml]

### add-to-project-senzing-dependabot.yaml

When a Dependabot pull request is opened against `main`, adds it to the project
board as "In Progress".

- Uses: [senzing-factory/build-resources/.../add-to-project-dependabot.yaml]

### claude-pr-review.yaml

When a pull request is opened or pushed to, posts an automated review.

- Uses: [senzing-factory/build-resources/.../claude-pull-request-review.yaml]

### dependabot-approve-and-merge.yaml

When a Dependabot pull request is opened against `main`, approves and
auto-merges minor and patch updates. Major bumps are never auto-approved.

- Uses: [senzing-factory/build-resources/.../dependabot-approve-and-merge.yaml]

### link-issues-to-pr-post-merge.yaml

When a pull request is merged, links the issues it closes back to it.

- Uses:
  [senzing-factory/build-resources/.../link-issues-to-pull-request-post-merge.yaml]

### lint-workflows.yaml

When a pull request is made against `main`, runs [super-linter] over the
`.github/` tree.

- Configuration:
  - [.jscpd.json]
  - [.yaml-lint.yml]
  - [markdownlint.json]
  - [zizmor.yaml]
- Uses: [senzing-factory/build-resources/.../lint-workflows.yaml]

### move-pr-to-done-dependabot.yaml

When a Dependabot pull request is closed or merged, moves its project-board
item to "Done".

- Uses: [senzing-factory/build-resources/.../move-pr-to-done-dependabot.yaml]

### spellcheck.yaml

When a pull request is made against `main`, runs [cspell]. The word list is
[.vscode/cspell.json].

- Uses: [senzing-factory/build-resources/.../cspell.yaml]

[.jscpd.json]: ../linters/.jscpd.json
[.vscode/cspell.json]: ../../.vscode/cspell.json
[.yaml-lint.yml]: ../linters/.yaml-lint.yml
[cspell]: https://cspell.org/
[markdownlint.json]: ../linters/markdownlint.json
[senzing-factory/build-resources]: https://github.com/senzing-factory/build-resources
[senzing-factory/build-resources/.../add-labels-to-issue.yaml]: https://github.com/senzing-factory/build-resources/blob/main/.github/workflows/add-labels-to-issue.yaml
[senzing-factory/build-resources/.../add-to-project-dependabot.yaml]: https://github.com/senzing-factory/build-resources/blob/main/.github/workflows/add-to-project-dependabot.yaml
[senzing-factory/build-resources/.../add-to-project.yaml]: https://github.com/senzing-factory/build-resources/blob/main/.github/workflows/add-to-project.yaml
[senzing-factory/build-resources/.../claude-pull-request-review.yaml]: https://github.com/senzing-factory/build-resources/blob/main/.github/workflows/claude-pull-request-review.yaml
[senzing-factory/build-resources/.../cspell.yaml]: https://github.com/senzing-factory/build-resources/blob/main/.github/workflows/cspell.yaml
[senzing-factory/build-resources/.../dependabot-approve-and-merge.yaml]: https://github.com/senzing-factory/build-resources/blob/main/.github/workflows/dependabot-approve-and-merge.yaml
[senzing-factory/build-resources/.../link-issues-to-pull-request-post-merge.yaml]: https://github.com/senzing-factory/build-resources/blob/main/.github/workflows/link-issues-to-pull-request-post-merge.yaml
[senzing-factory/build-resources/.../lint-workflows.yaml]: https://github.com/senzing-factory/build-resources/blob/main/.github/workflows/lint-workflows.yaml
[senzing-factory/build-resources/.../move-pr-to-done-dependabot.yaml]: https://github.com/senzing-factory/build-resources/blob/main/.github/workflows/move-pr-to-done-dependabot.yaml
[super-linter]: https://github.com/super-linter/super-linter
[zizmor.yaml]: ../linters/zizmor.yaml
