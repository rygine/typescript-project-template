#!/bin/bash
set -euo pipefail

# Resolve this script and the repo root from the script's own location, before
# any cd, so both stay valid afterwards and the script works from any working
# directory. Every path below is relative to the repo root.
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
script_path="$script_dir/$(basename -- "${BASH_SOURCE[0]}")"
repo_root="$(cd -- "$script_dir/.." &>/dev/null && pwd)"
cd "$repo_root"

# Clean up the intermediates on the way out, whether or not we got there by
# succeeding. Relative to $repo_root, which is now the working directory.
trap 'rm -f README.md.tmp AGENTS.md.tmp LICENSE.bak' EXIT

if [ $# -ne 1 ]; then
  echo "usage: $(basename -- "$script_path") <project-name>" >&2
  exit 1
fi

name="$1"

# npm's naming rules: lowercase, URL-safe, optionally scoped. Validating here
# is also what keeps shell metacharacters out of the rewrites below — a scoped
# name like @acme/thing is ordinary, and an unvalidated one used to break the
# s/// delimiter, leave the repo half-renamed, and still exit 0.
name_re='^(@[a-z0-9~-][a-z0-9._~-]*/)?[a-z0-9~-][a-z0-9._~-]*$'
if ! [[ $name =~ $name_re ]]; then
  echo "invalid package name: $name" >&2
  echo "expected lowercase and URL-safe: my-project or @scope/my-project" >&2
  exit 1
fi

if [ "${#name}" -gt 214 ]; then
  echo "invalid package name: $name is over npm's 214-character limit" >&2
  exit 1
fi

# Everything below rewrites a file in place. Check the whole set up front so a
# missing file fails before the first mutation rather than midway through.
for file in package.json README.md LICENSE AGENTS.md; do
  if [ ! -f "$file" ]; then
    echo "missing $file — run this from a fresh clone of the template" >&2
    exit 1
  fi
done

if ! grep -q '<!-- init:start -->' AGENTS.md; then
  echo "AGENTS.md has no <!-- init:start --> marker; already initialized?" >&2
  exit 1
fi

npm pkg set name="$name"

# Renaming the workspace invalidates yarn.lock, which still records the old
# identity under "<old>@workspace:.". The Dockerfile's build stage runs
# `yarn install --immutable`, which refuses that mismatch outright — so
# without this, the first `./scripts/up.sh` after init fails. --mode=update-
# lockfile skips the link step, so node_modules is never materialized — but it
# still resolves and fetches, so on a fresh clone expect a real download into
# .yarn/cache, not a no-op.
if command -v yarn >/dev/null 2>&1; then
  yarn install --mode=update-lockfile
else
  echo "warning: yarn not on PATH, so yarn.lock still names the old" >&2
  echo "workspace. Run 'yarn install' before building the image." >&2
fi

# awk takes the name through -v, so it is never parsed as part of an
# expression. Line 1 only: rewriting every "# " line would also hit bash
# comments inside fenced code blocks.
awk -v title="$name" 'NR == 1 && /^# / { print "# " title; next } { print }' \
  README.md > README.md.tmp
mv README.md.tmp README.md

# -i.bak is the one form of in-place edit both GNU and BSD sed accept.
# Anchored to the copyright line so any other 4-digit number in the license
# text survives.
sed -i.bak "s/^\(Copyright (c) \)[0-9]\{4\}/\1$(date +%Y)/" LICENSE
rm -f LICENSE.bak

# Drop the one-time setup section, plus the blank line it leaves behind.
awk '
  /<!-- init:start -->/ { skip = 1; next }
  /<!-- init:end -->/   { skip = 0; ended = 1; next }
  skip                  { next }
  ended && /^$/         { ended = 0; next }
                        { ended = 0; print }
' AGENTS.md > AGENTS.md.tmp
mv AGENTS.md.tmp AGENTS.md

# Last, and only on success. Every step above is idempotent, so a run that
# failed partway leaves the script in place and safe to re-run once fixed.
rm -f "$script_path"
