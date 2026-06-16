#!/bin/sh
# One-time setup: installs git hooks that auto-run `xcodegen generate` after
# every `git pull` / branch checkout, so you never run it by hand again.
#
# Usage (from anywhere in the repo):  sh scripts/install-dev-hooks.sh

set -e
repo="$(git rev-parse --show-toplevel)"
hooks_dir="$repo/.git/hooks"
mkdir -p "$hooks_dir"

# The hook body: regenerate the Xcode project if xcodegen is installed.
hook_body='#!/bin/sh
root="$(git rev-parse --show-toplevel)"
if command -v xcodegen >/dev/null 2>&1; then
  ( cd "$root/Muse" && xcodegen generate >/dev/null 2>&1 ) \
    && echo "[muse] Xcode project regenerated."
fi
'

for hook in post-merge post-checkout post-rewrite; do
  printf '%s' "$hook_body" > "$hooks_dir/$hook"
  chmod +x "$hooks_dir/$hook"
done

echo "Installed. 'xcodegen generate' will now run automatically after"
echo "git pull / checkout. Just pull and press Run in Xcode."
