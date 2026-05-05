---
name: github-cli-automation
description: Automates GitHub Pull Request creation using GitHub CLI by reviewing git changes
tools: ['execute', 'read']
---

## 🔹 Purpose
Automate Pull Request creation using GitHub CLI (`gh`) with clear step-by-step feedback and change visibility.

---

## 🔹 Workflow

### 1. Validate Git Repository
Print:
"🔍 Checking if current directory is a git repository..."

Run:
git rev-parse --is-inside-work-tree

If fails:
Stop and say:
"❌ Not a git repository.
👉 Fix: Run `git init` or navigate to a valid repository."

If success:
Print:
"✅ Git repository detected"

---

### 2. Check Changes
Print:
"🔍 Checking for staged or committed changes..."

Run:
git status --porcelain

If empty:
Stop and say:
"❌ No changes found.
👉 Fix:
git add .
git commit -m 'your message'"

If success:
Print:
"✅ Changes detected"

---

### 3. Review Changes

Print:
"📊 Analyzing current branch and changes..."

Run:
git branch --show-current

Run:
git diff --name-only

Run:
git diff --stat

---

### Output Review Summary

Print:

"🌿 Branch:"
(output of git branch --show-current)

"📂 Files changed:"
(output of git diff --name-only)

"📈 Change stats:"
(output of git diff --stat)

---

### 4. Push Branch

Print:
"🚀 Pushing branch to remote repository..."

Run:
git push -u origin $(git branch --show-current)

If fails:
Stop and say:
"❌ Push failed.
👉 Fix: Check remote origin or authentication."

If success:
Print:
"✅ Branch pushed successfully"

---

### 5. Create Pull Request

Print:
"🔧 Creating Pull Request using GitHub CLI..."

Run:
gh pr create

If fails:
Stop and say:
"❌ PR creation failed.
👉 Fix: Run `gh auth login` and try again."

---

### ✅ Success

Print:
"🎉 Pull Request created successfully!"