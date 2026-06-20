#!/usr/bin/env bash
# Symlink every skill in this repo into ~/.claude/skills/ for local testing.
# Run: bash scripts/link-skills.sh
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"

case "$DEST" in
  "$REPO"*) echo "refusing: destination $DEST is inside the repo" >&2; exit 1 ;;
esac

mkdir -p "$DEST"

cd "$REPO"
while IFS= read -r skill_md; do
  skill_dir="$(dirname "$skill_md")"
  name="$(basename "$skill_dir")"
  target="$DEST/$name"

  if [ -e "$target" ] && [ ! -L "$target" ]; then
    echo "skipped $name -> $target already exists and is not a symlink" >&2
    continue
  fi
  ln -sfn "$REPO/$skill_dir" "$target"
  echo "linked $name -> $REPO/$skill_dir"
done < <(find skills -name SKILL.md -not -path '*/node_modules/*' | sort)
