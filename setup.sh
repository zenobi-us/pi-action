#!/usr/bin/env sh
set -eu

# Gitclaw setup script
# Usage: curl -fsSL https://raw.githubusercontent.com/zenobi-us/pi-action/main/setup.sh | sh
#
# Merges the Gitclaw template into the current directory.
# Existing files are NOT overwritten — only missing files are added.

REPO="zenobi-us/pi-action"
BRANCH="main"
TEMPLATE_DIR="template"

main() {
  # --- Preflight checks ---
  if ! command -v git >/dev/null 2>&1; then
    echo "Error: git is required" >&2
    exit 1
  fi

  if [ ! -d ".git" ]; then
    echo "Error: not a git repository. Run this from your repo root." >&2
    exit 1
  fi

  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' EXIT

  echo "Downloading Gitclaw template..."

  # --- Download and extract template ---
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz" -o "$tmpdir/archive.tar.gz"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$tmpdir/archive.tar.gz" "https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz"
  else
    echo "Error: curl or wget is required" >&2
    exit 1
  fi

  tar -xzf "$tmpdir/archive.tar.gz" -C "$tmpdir"

  # The archive extracts to pi-action-<branch>/
  src="$tmpdir/pi-action-${BRANCH}/${TEMPLATE_DIR}"

  if [ ! -d "$src" ]; then
    echo "Error: template directory not found in archive" >&2
    exit 1
  fi

  # --- Merge files (skip existing) ---
  copied=0
  skipped=0

  cd_back=$(pwd)
  cd "$src"
  find . -type f | while read -r file; do
    rel="${file#./}"
    dest="${cd_back}/${rel}"

    if [ -f "$dest" ]; then
      echo "  skip: ${rel} (already exists)"
      skipped=$((skipped + 1))
    else
      mkdir -p "$(dirname "$dest")"
      cp "$file" "$dest"
      echo "  add:  ${rel}"
      copied=$((copied + 1))
    fi
  done
  cd "$cd_back"

  echo ""
  echo "Done. Review the new files, then:"
  echo ""
  echo "  git add -A"
  echo "  git commit -m 'chore: add gitclaw agent template'"
  echo ""
  echo "Next steps:"
  echo "  1. Add your API keys to repo secrets (Settings → Secrets → Actions)"
  echo "     - PI_AUTH_JSON: your pi auth.json as a single-line JSON string"
  echo "  2. Open a 🥚 Hatch issue to bootstrap your agent's identity"
}

main
