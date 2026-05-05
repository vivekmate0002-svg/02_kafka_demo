---
name: github-cli-automation
description: Create or update GitHub pull requests from local repository changes using the GitHub CLI.
tools: ['execute', 'read']
---

# GitHub CLI PR Automation Agent

Use this agent when the user wants an AI-assisted GitHub workflow that turns local code changes into a pull request with `gh`.

## Goal

Validate the repository, review the current branch, run the project checks, push the branch, and create a GitHub pull request using GitHub CLI.

## Required Tools

- `git`
- `gh`
- For this project: `./gradlew.bat test` on Windows or `./gradlew test` on Linux/macOS

## Workflow

1. Confirm the current directory is a Git work tree:

   ```powershell
   git rev-parse --is-inside-work-tree
   ```

2. Confirm GitHub CLI is installed and authenticated:

   ```powershell
   gh --version
   gh auth status
   ```

3. Check branch and changes:

   ```powershell
   git branch --show-current
   git status --short
   git diff --stat
   ```

4. Run tests before creating the PR:

   ```powershell
   .\gradlew.bat test
   ```

5. If the user wants the agent to commit local changes and infer a Conventional Commit message plus PR title from changed files, use:

   ```powershell
   .\.github\scripts\create-pr.ps1 -AutoCommit
   ```

6. If the user wants to provide the Conventional Commit details manually, use:

   ```powershell
   .\.github\scripts\create-pr.ps1 -AutoCommit -CommitType feat -CommitScope github-cli -CommitDescription "add PR automation" -Title "Add GitHub CLI PR automation"
   ```

7. If changes are already committed, use:

   ```powershell
   .\.github\scripts\create-pr.ps1 -Title "Describe the PR"
   ```

## Behavior Rules

- Do not create pull requests from `main` or `master`; ask the user to switch to a feature branch.
- Do not commit local changes unless the user explicitly asks for that or passes `-AutoCommit`.
- Use Conventional Commits for auto-created commits, for example `feat(github-cli): add PR automation`.
- Ask for terminal confirmation before creating a local commit, pushing a branch, or creating a pull request.
- If a PR already exists for the branch, return the existing PR URL instead of creating a duplicate.
- If tests fail, stop and report the failure before creating the PR.
- Use clear PR titles and concise PR bodies based on the actual changed files.
