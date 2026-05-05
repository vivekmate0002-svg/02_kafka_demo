param(
  [string]$BaseBranch = "main",
  [string]$Title = "",
  [string]$Body = "",
  [string]$CommitMessage = "",
  [switch]$AutoCommit,
  [switch]$Draft,
  [switch]$SkipTests
)

$ErrorActionPreference = "Stop"

function Write-Step {
  param([string]$Message)
  Write-Host ""
  Write-Host "==> $Message"
}

function Fail {
  param([string]$Message)
  Write-Error $Message
  exit 1
}

function Require-Command {
  param([string]$Name)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    Fail "Required command '$Name' was not found on PATH."
  }
}

Write-Host "GitHub CLI PR automation started"

Write-Step "Validating tools"
Require-Command "git"
Require-Command "gh"

Write-Step "Validating Git repository"
git rev-parse --is-inside-work-tree *> $null
if ($LASTEXITCODE -ne 0) {
  Fail "This directory is not a Git repository. Run the script from the repository root."
}

$repoRoot = (git rev-parse --show-toplevel).Trim()
Set-Location $repoRoot

Write-Step "Validating GitHub CLI authentication"
gh auth status
if ($LASTEXITCODE -ne 0) {
  Fail "GitHub CLI is not authenticated. Run: gh auth login"
}

Write-Step "Reading branch state"
$branch = (git branch --show-current).Trim()
if ([string]::IsNullOrWhiteSpace($branch)) {
  Fail "Could not determine the current branch."
}

if ($branch -eq $BaseBranch -or $branch -eq "master") {
  Fail "Refusing to create a PR from '$branch'. Switch to a feature branch first."
}

Write-Host "Current branch: $branch"
Write-Host "Base branch: $BaseBranch"

$status = git status --porcelain
if ($status) {
  Write-Host ""
  Write-Host "Uncommitted changes:"
  git status --short

  if (-not $AutoCommit) {
    Fail "Uncommitted changes found. Commit them first, or rerun with -AutoCommit -CommitMessage `"your message`"."
  }

  if ([string]::IsNullOrWhiteSpace($CommitMessage)) {
    Fail "-CommitMessage is required when using -AutoCommit."
  }

  Write-Step "Committing local changes"
  git add -A
  git commit -m $CommitMessage
  if ($LASTEXITCODE -ne 0) {
    Fail "Git commit failed."
  }
}

if (-not $SkipTests) {
  Write-Step "Running Gradle tests"
  if ($IsWindows -or $env:OS -eq "Windows_NT") {
    & ".\gradlew.bat" test
  } else {
    & "./gradlew" test
  }

  if ($LASTEXITCODE -ne 0) {
    Fail "Tests failed. Fix the test failure before creating a PR."
  }
}

Write-Step "Fetching base branch"
git fetch origin $BaseBranch
if ($LASTEXITCODE -ne 0) {
  Fail "Could not fetch origin/$BaseBranch."
}

$aheadCount = (git rev-list --count "origin/$BaseBranch..HEAD").Trim()
if ([int]$aheadCount -eq 0) {
  Fail "Branch '$branch' has no commits ahead of origin/$BaseBranch."
}

Write-Step "Changed files"
git diff --name-only "origin/$BaseBranch...HEAD"

Write-Step "Change summary"
git diff --stat "origin/$BaseBranch...HEAD"

Write-Step "Pushing branch"
git push -u origin $branch
if ($LASTEXITCODE -ne 0) {
  Fail "Push failed. Check your remote permissions and branch name."
}

Write-Step "Checking for an existing pull request"
$existingPrUrl = (gh pr list --head $branch --base $BaseBranch --state open --json url --jq ".[0].url").Trim()
if (-not [string]::IsNullOrWhiteSpace($existingPrUrl)) {
  Write-Host "Open pull request already exists:"
  Write-Host $existingPrUrl
  exit 0
}

if ([string]::IsNullOrWhiteSpace($Title)) {
  $Title = $CommitMessage
}

if ([string]::IsNullOrWhiteSpace($Title)) {
  $Title = "Update from $branch"
}

if ([string]::IsNullOrWhiteSpace($Body)) {
  $changedFiles = (git diff --name-only "origin/$BaseBranch...HEAD") -join "`n"
  $Body = @"
Automated PR created with GitHub CLI.

Base: $BaseBranch
Branch: $branch

Changed files:
$changedFiles
"@
}

Write-Step "Creating pull request"
$ghArgs = @(
  "pr", "create",
  "--base", $BaseBranch,
  "--head", $branch,
  "--title", $Title,
  "--body", $Body
)

if ($Draft) {
  $ghArgs += "--draft"
}

gh @ghArgs
if ($LASTEXITCODE -ne 0) {
  Fail "Pull request creation failed."
}

Write-Host ""
Write-Host "PR automation completed"
