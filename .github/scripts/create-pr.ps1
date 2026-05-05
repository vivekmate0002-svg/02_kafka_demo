param(
  [string]$BaseBranch = "main",
  [string]$Title = "",
  [string]$Body = "",
  [string]$CommitMessage = "",
  [switch]$AutoCommit,
  [switch]$Draft,
  [switch]$SkipTests,
  [switch]$VerboseLogs
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
  Write-Info "Files currently changed:"
  $changedWorkingTreeFiles | ForEach-Object { Write-Info $_ }

  if (-not $AutoCommit) {
    Fail "Uncommitted changes found." @(
      "Commit the files manually, or rerun with:",
      ".\.github\scripts\create-pr.ps1 -AutoCommit -CommitMessage `"your message`" -Title `"your PR title`""
    )
  }

  if ([string]::IsNullOrWhiteSpace($CommitMessage)) {
    Fail "-CommitMessage is required when using -AutoCommit."
  }

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
