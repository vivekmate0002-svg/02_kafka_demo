param(
  [string]$BaseBranch = "main",
  [string]$Title = "",
  [string]$Body = "",
  [string]$CommitMessage = "",
  [ValidateSet("feat", "fix", "docs", "style", "refactor", "perf", "test", "build", "ci", "chore", "revert")]
  [string]$CommitType = "",
  [string]$CommitScope = "",
  [string]$CommitDescription = "",
  [switch]$BreakingChange,
  [switch]$AutoCommit,
  [switch]$Draft,
  [switch]$SkipTests,
  [switch]$VerboseLogs,
  [switch]$Yes
)

$ErrorActionPreference = "Stop"

function Write-Header {
  param([string]$Message)
  Write-Host ""
  Write-Host "============================================================"
  Write-Host " $Message"
  Write-Host "============================================================"
}

function Write-Step {
  param([string]$Message)
  Write-Host ""
  Write-Host "[..] $Message"
}

function Write-Ok {
  param([string]$Message)
  Write-Host "[OK] $Message"
}

function Write-Info {
  param([string]$Message)
  Write-Host "     $Message"
}

function Fail {
  param(
    [string]$Message,
    [object[]]$Details = @()
  )

  Write-Host ""
  Write-Host "[FAILED] $Message" -ForegroundColor Red
  if ($Details -and $Details.Count -gt 0) {
    Write-Host ""
    Write-Host "Details:"
    $Details | ForEach-Object { Write-Host $_ }
  }
  exit 1
}

function Require-Command {
  param([string]$Name)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    Fail "Required command '$Name' was not found on PATH."
  }
}

function Show-OutputIfVerbose {
  param([object[]]$Output)
  if ($VerboseLogs -and $Output) {
    $Output | ForEach-Object { Write-Host $_ }
  }
}

function Invoke-Checked {
  param(
    [string]$FailureMessage,
    [scriptblock]$Command
  )

  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $output = & $Command 2>&1
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }

  if ($exitCode -ne 0) {
    Fail $FailureMessage $output
  }
  Show-OutputIfVerbose $output
  return $output
}

function Confirm-Action {
  param(
    [string]$Prompt,
    [string]$CancelMessage = "Cancelled."
  )

  if ($Yes) {
    Write-Ok "Confirmation skipped because -Yes was provided"
    return
  }

  Write-Host ""
  $answer = Read-Host "$Prompt Type YES to continue"
  if ($answer -ne "YES") {
    Write-Host ""
    Write-Host $CancelMessage
    exit 0
  }
}

function Test-ConventionalCommit {
  param([string]$Message)
  return $Message -match '^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-z0-9-]+\))?!?: .+'
}

function New-ConventionalCommitMessage {
  param(
    [string]$Type,
    [string]$Scope,
    [string]$Description,
    [bool]$IsBreaking
  )

  if ([string]::IsNullOrWhiteSpace($Type) -and [string]::IsNullOrWhiteSpace($Description)) {
    return ""
  }

  if ([string]::IsNullOrWhiteSpace($Type)) {
    Fail "-CommitType is required when using -CommitDescription."
  }

  if ([string]::IsNullOrWhiteSpace($Description)) {
    Fail "-CommitDescription is required when using -CommitType."
  }

  $normalizedDescription = $Description.Trim()
  if ($normalizedDescription.EndsWith(".")) {
    Fail "Conventional commit descriptions should not end with a period." @(
      "Use: $Type`: $($normalizedDescription.TrimEnd('.'))"
    )
  }

  $scopePart = ""
  if (-not [string]::IsNullOrWhiteSpace($Scope)) {
    $normalizedScope = $Scope.Trim().ToLowerInvariant()
    if ($normalizedScope -notmatch '^[a-z0-9-]+$') {
      Fail "-CommitScope must use lowercase letters, numbers, and hyphens only." @(
        "Example: github-cli, kafka, api"
      )
    }
    $scopePart = "($normalizedScope)"
  }

  $breakingPart = ""
  if ($IsBreaking) {
    $breakingPart = "!"
  }

  return "$Type$scopePart$breakingPart`: $normalizedDescription"
}

function Get-ChangeSummary {
  param([string[]]$Files)

  $summary = @{
    Type = "chore"
    Scope = "repo"
    Description = "update project files"
    Title = "Update project files"
  }

  if ($Files | Where-Object { $_ -like ".github/scripts/*" }) {
    $summary.Type = "feat"
    $summary.Scope = "github-cli"
    $summary.Description = "update PR automation script"
    $summary.Title = "Update GitHub CLI PR automation"
    return $summary
  }

  if ($Files | Where-Object { $_ -like ".github/workflows/*" }) {
    $summary.Type = "ci"
    $summary.Scope = "github-actions"
    $summary.Description = "update PR automation workflow"
    $summary.Title = "Update GitHub Actions PR automation"
    return $summary
  }

  if ($Files | Where-Object { $_ -like ".github/agents/*" }) {
    $summary.Type = "docs"
    $summary.Scope = "github-cli"
    $summary.Description = "update automation agent instructions"
    $summary.Title = "Update GitHub CLI automation agent"
    return $summary
  }

  if ($Files | Where-Object { $_ -like "src/test/*" }) {
    $summary.Type = "test"
    $summary.Scope = "kafka"
    $summary.Description = "update test coverage"
    $summary.Title = "Update test coverage"
    return $summary
  }

  if ($Files | Where-Object { $_ -like "src/main/*" }) {
    $summary.Type = "feat"
    $summary.Scope = "kafka"
    $summary.Description = "update application behavior"
    $summary.Title = "Update Kafka demo behavior"
    return $summary
  }

  if ($Files | Where-Object { $_ -in @("build.gradle", "settings.gradle") -or $_ -like "gradle/*" }) {
    $summary.Type = "build"
    $summary.Scope = "gradle"
    $summary.Description = "update build configuration"
    $summary.Title = "Update Gradle build configuration"
    return $summary
  }

  if ($Files | Where-Object { $_ -like "*.md" }) {
    $summary.Type = "docs"
    $summary.Scope = "repo"
    $summary.Description = "update documentation"
    $summary.Title = "Update documentation"
    return $summary
  }

  return $summary
}

Write-Header "GitHub Pull Request Automation"

Write-Step "Checking required tools"
Require-Command "git"
Require-Command "gh"
Write-Ok "git and gh are available"

Write-Step "Checking repository"
Invoke-Checked "This directory is not a Git repository. Run the script from the repository root." {
  git rev-parse --is-inside-work-tree
} *> $null

$repoRoot = (git rev-parse --show-toplevel).Trim()
Set-Location $repoRoot
Write-Ok "Repository found"
Write-Info $repoRoot

Write-Step "Checking GitHub CLI login"
Invoke-Checked "GitHub CLI is not authenticated. Run: gh auth login" {
  gh auth status
} *> $null

$ghUser = ""
$ghUserOutput = & gh api user --jq ".login" 2>$null
if ($LASTEXITCODE -eq 0) {
  $ghUser = ($ghUserOutput | Select-Object -First 1).Trim()
}

if ($ghUser) {
  Write-Ok "Logged in to GitHub as $ghUser"
} else {
  Write-Ok "GitHub CLI is authenticated"
}

Write-Step "Reading branch"
$branch = (git branch --show-current).Trim()
if ([string]::IsNullOrWhiteSpace($branch)) {
  Fail "Could not determine the current branch."
}

if ($branch -eq $BaseBranch -or $branch -eq "master") {
  Fail "Refusing to create a PR from '$branch'. Switch to a feature branch first."
}

Write-Ok "Using branch '$branch' -> '$BaseBranch'"

$commitCreated = $false
$status = git status --porcelain
if ($status) {
  Write-Step "Preparing local changes"
  $changedWorkingTreeFiles = git status --short
  $changedWorkingTreePaths = @(git status --porcelain | ForEach-Object { $_.Substring(3).Trim() })
  Write-Info "Files currently changed:"
  $changedWorkingTreeFiles | ForEach-Object { Write-Info $_ }

  if (-not $AutoCommit) {
    Fail "Uncommitted changes found." @(
      "Commit the files manually, or rerun with:",
      ".\.github\scripts\create-pr.ps1 -AutoCommit -CommitMessage `"your message`" -Title `"your PR title`""
    )
  }

  if ([string]::IsNullOrWhiteSpace($CommitMessage)) {
    $CommitMessage = New-ConventionalCommitMessage `
      -Type $CommitType `
      -Scope $CommitScope `
      -Description $CommitDescription `
      -IsBreaking $BreakingChange.IsPresent
  }

  if ([string]::IsNullOrWhiteSpace($CommitMessage)) {
    $autoSummary = Get-ChangeSummary -Files $changedWorkingTreePaths
    $CommitMessage = New-ConventionalCommitMessage `
      -Type $autoSummary.Type `
      -Scope $autoSummary.Scope `
      -Description $autoSummary.Description `
      -IsBreaking $BreakingChange.IsPresent

    if ([string]::IsNullOrWhiteSpace($Title)) {
      $Title = $autoSummary.Title
    }
  }

  if ([string]::IsNullOrWhiteSpace($CommitMessage)) {
    Fail "A commit message is required when using -AutoCommit." @(
      "Option 1: -CommitMessage `"feat(github-cli): add PR automation`"",
      "Option 2: -CommitType feat -CommitScope github-cli -CommitDescription `"add PR automation`"",
      "Option 3: omit commit message fields and let the script infer them from changed files"
    )
  }

  if (-not (Test-ConventionalCommit $CommitMessage)) {
    Fail "Commit message must follow Conventional Commits." @(
      "Expected: type(optional-scope): description",
      "Examples:",
      "feat(github-cli): add PR automation",
      "fix(kafka): handle consumer retry",
      "docs: update setup instructions",
      "Allowed types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert"
    )
  }

  Write-Header "Permission Required"
  Write-Host "The next step will create a local Git commit."
  Write-Host ""
  Write-Host "Commit message: $CommitMessage"
  Write-Host "PR title      : $(if ([string]::IsNullOrWhiteSpace($Title)) { $CommitMessage } else { $Title })"
  Write-Host ""
  Write-Host "Files:"
  $changedWorkingTreeFiles | ForEach-Object { Write-Host "- $_" }

  Confirm-Action "Allow local commit?" "Cancelled. No commit, branch push, or pull request was created."

  Invoke-Checked "Git commit failed." {
    git add -A
    git commit -m $CommitMessage
  } | Out-Null

  $commitCreated = $true
  Write-Ok "Committed local changes"
  Write-Info $CommitMessage
} else {
  Write-Ok "Working tree is clean"
}

if (-not $SkipTests) {
  Write-Step "Running tests"
  if ($IsWindows -or $env:OS -eq "Windows_NT") {
    Invoke-Checked "Tests failed. Fix the test failure before creating a PR." {
      & ".\gradlew.bat" test
    } | Out-Null
  } else {
    Invoke-Checked "Tests failed. Fix the test failure before creating a PR." {
      & "./gradlew" test
    } | Out-Null
  }
  Write-Ok "Tests passed"
} else {
  Write-Ok "Tests skipped by request"
}

Write-Step "Comparing with base branch"
Invoke-Checked "Could not fetch origin/$BaseBranch." {
  git fetch origin $BaseBranch
} | Out-Null

$aheadCount = (git rev-list --count "origin/$BaseBranch..HEAD").Trim()
if ([int]$aheadCount -eq 0) {
  Fail "Branch '$branch' has no commits ahead of origin/$BaseBranch."
}

$changedFiles = @(git diff --name-only "origin/$BaseBranch...HEAD")
$changeStat = @(git diff --stat "origin/$BaseBranch...HEAD")

Write-Ok "$aheadCount commit(s) ready for PR"
Write-Info "Changed files:"
$changedFiles | ForEach-Object { Write-Info "- $_" }

if ($VerboseLogs -and $changeStat.Count -gt 0) {
  Write-Host ""
  Write-Host "Change summary:"
  $changeStat | ForEach-Object { Write-Host $_ }
}

Write-Header "Permission Required"
Write-Host "The next steps will publish this work to GitHub."
Write-Host ""
Write-Host "Branch       : $branch"
Write-Host "Base         : $BaseBranch"
Write-Host "Commits      : $aheadCount"
Write-Host "Tests        : $(if ($SkipTests) { 'Skipped' } else { 'Passed' })"
Write-Host "Draft PR     : $(if ($Draft) { 'Yes' } else { 'No' })"
Write-Host ""
Write-Host "Actions:"
Write-Host "- Push branch to origin/$branch"
Write-Host "- Create a new PR, or show the existing open PR"

Confirm-Action "Allow GitHub push and PR operation?" "Cancelled. No branch was pushed and no pull request was created."

Write-Step "Pushing branch to GitHub"
Invoke-Checked "Push failed. Check your remote permissions and branch name." {
  git push -u origin $branch
} | Out-Null
Write-Ok "Branch pushed to origin/$branch"

Write-Step "Checking pull request"
$existingPrUrl = (gh pr list --head $branch --base $BaseBranch --state open --json url --jq ".[0].url").Trim()
if (-not [string]::IsNullOrWhiteSpace($existingPrUrl)) {
  Write-Ok "Open pull request already exists"
  Write-Header "Result"
  Write-Host "Status       : Existing PR"
  Write-Host "URL          : $existingPrUrl"
  Write-Host "Branch       : $branch"
  Write-Host "Base         : $BaseBranch"
  Write-Host "Tests        : $(if ($SkipTests) { 'Skipped' } else { 'Passed' })"
  Write-Host "Auto-commit  : $(if ($commitCreated) { 'Yes' } else { 'No' })"
  exit 0
}

if ([string]::IsNullOrWhiteSpace($Title)) {
  $Title = $CommitMessage
}

if ([string]::IsNullOrWhiteSpace($Title)) {
  $Title = "Update from $branch"
}

if ([string]::IsNullOrWhiteSpace($Body)) {
  $changedFileList = $changedFiles -join "`n"
  $Body = @"
Automated PR created with GitHub CLI.

Base: $BaseBranch
Branch: $branch

Changed files:
$changedFileList
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

$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
  $createOutput = & gh @ghArgs 2>&1
  $createExitCode = $LASTEXITCODE
} finally {
  $ErrorActionPreference = $previousErrorActionPreference
}

if ($createExitCode -ne 0) {
  Fail "Pull request creation failed." $createOutput
}

$prUrl = ($createOutput | Select-String -Pattern "https://github.com/\S+" | Select-Object -Last 1).Matches.Value
if ([string]::IsNullOrWhiteSpace($prUrl)) {
  $prUrl = ($createOutput | Select-Object -Last 1)
}

Write-Ok "Pull request created"

Write-Header "Result"
Write-Host "Status       : Created PR"
Write-Host "URL          : $prUrl"
Write-Host "Title        : $Title"
Write-Host "Branch       : $branch"
Write-Host "Base         : $BaseBranch"
Write-Host "Tests        : $(if ($SkipTests) { 'Skipped' } else { 'Passed' })"
Write-Host "Auto-commit  : $(if ($commitCreated) { 'Yes' } else { 'No' })"
Write-Host ""
Write-Host "Next step    : Review and merge the PR on GitHub."
