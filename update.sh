#!/bin/bash
# Update a project that was installed from AIDevTeamForge.
#
# Usage:
#   ./update.sh /path/to/target-project
#   ./update.sh --dry-run /path/to/target-project
#   ./update.sh --force /path/to/target-project

set -euo pipefail

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ── Helpers ─────────────────────────────────────────────────────────────────
info()    { printf "${CYAN}ℹ${NC}  %b\n" "$*"; }
added()   { printf "${GREEN}+${NC}  %b\n" "$*"; }
merged()  { printf "${YELLOW}~${NC}  %b\n" "$*"; }
skipped() { printf "${BLUE}⊘${NC}  %b\n" "$*"; }
overwrt() { printf "${RED}↻${NC}  %b\n" "$*"; }
warn()    { printf "${YELLOW}⚠${NC}  %b\n" "$*"; }
err()     { printf "${RED}✖${NC}  %b\n" "$*" >&2; }
header()  { printf "\n${BOLD}%b${NC}\n" "$*"; }

# ── Parse arguments ─────────────────────────────────────────────────────────
DRY_RUN=false
FORCE=false
TARGET_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --force)   FORCE=true; shift ;;
    -*)        err "Unknown flag: $1"; exit 1 ;;
    *)         TARGET_DIR="$1"; shift ;;
  esac
done

TEMPLATE_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$TARGET_DIR" ]; then
  echo "Usage: update.sh [--dry-run] [--force] <target-project-directory>"
  echo ""
  echo "Flags:"
  echo "  --dry-run   Show what would change without making modifications"
  echo "  --force     Skip confirmation prompt"
  exit 1
fi

# Resolve to absolute path
TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd)" || {
  err "Directory '$TARGET_DIR' does not exist."
  exit 1
}

# ── Validate target ────────────────────────────────────────────────────────
if [ ! -d "$TARGET_DIR/.claude" ]; then
  err "Target does not look like a project installed from this template."
  err "Missing .claude/ directory in: $TARGET_DIR"
  exit 1
fi

# ── Check for jq (required for JSON merging) ───────────────────────────────
if ! command -v jq >/dev/null 2>&1; then
  err "jq is required for JSON merging but was not found."
  err "Install it with:  brew install jq  (macOS)  or  apt install jq  (Linux)"
  exit 1
fi

# ── Load manifest ──────────────────────────────────────────────────────────
MANIFEST="$TEMPLATE_DIR/.claude/template-manifest.json"
if [ ! -f "$MANIFEST" ]; then
  err "Template manifest not found at: $MANIFEST"
  exit 1
fi

TEMPLATE_VERSION="$(jq -r '.version' "$MANIFEST")"
TARGET_VERSION_FILE="$TARGET_DIR/.claude/template-version"

if [ -f "$TARGET_VERSION_FILE" ]; then
  TARGET_VERSION="$(tr -d '[:space:]' < "$TARGET_VERSION_FILE")"
else
  TARGET_VERSION="(unknown)"
fi

# ── Version info ───────────────────────────────────────────────────────────
header "AIDevTeamForge — Update"
info "Template version: ${BOLD}$TEMPLATE_VERSION${NC}"
info "Target version:   ${BOLD}$TARGET_VERSION${NC}"
info "Target path:      $TARGET_DIR"

if [ "$TEMPLATE_VERSION" = "$TARGET_VERSION" ]; then
  warn "Target is already on version $TEMPLATE_VERSION."
  if [ "$FORCE" != true ]; then
    echo ""
    printf "Continue anyway? [y/N] "
    read -r confirm
    case "$confirm" in [Yy]*) ;; *) info "Aborted."; exit 0 ;; esac
  fi
fi

# Show changelog excerpt if available
CHANGELOG="$TEMPLATE_DIR/CHANGELOG.md"
if [ -f "$CHANGELOG" ] && [ "$TARGET_VERSION" != "(unknown)" ] && [ "$TARGET_VERSION" != "$TEMPLATE_VERSION" ]; then
  header "Changelog (since $TARGET_VERSION)"
  awk -v from="$TARGET_VERSION" -v to="$TEMPLATE_VERSION" '
    /^## \[/ {
      v = $0; gsub(/^## \[|\] .*/, "", v)
      if (v == to) { printing = 1 }
      if (v == from) { printing = 0 }
    }
    printing { print }
  ' "$CHANGELOG"
  echo ""
fi

# ── Expand glob patterns to file lists ─────────────────────────────────────
# Given a base dir and a newline-separated list of glob patterns on stdin,
# print matching files (one per line). Uses find for ** patterns, direct
# listing otherwise. Compatible with bash 3.x / macOS.
expand_patterns() {
  local base_dir="$1"
  while IFS= read -r pattern; do
    [ -z "$pattern" ] && continue
    case "$pattern" in
      *"**"*)
        # Convert glob ** pattern to find arguments
        # e.g. ".claude/templates/**" → find .claude/templates -type f
        local dir_part="${pattern%%/\*\*}"
        if [ -d "$base_dir/$dir_part" ]; then
          find "$base_dir/$dir_part" -type f 2>/dev/null | while IFS= read -r fp; do
            # Strip base_dir prefix to get relative path
            echo "${fp#$base_dir/}"
          done
        fi
        ;;
      *)
        # Direct file path (no wildcards)
        if [ -f "$base_dir/$pattern" ]; then
          echo "$pattern"
        fi
        ;;
    esac
  done | sort -u
}

# ── Read pattern lists from manifest ───────────────────────────────────────
TEMPLATE_OWNED_PATTERNS="$(jq -r '.templateOwned.patterns[]' "$MANIFEST")"
PROJECT_OWNED_PATTERNS="$(jq -r '.projectOwned.patterns[]' "$MANIFEST")"
COPY_IF_MISSING_PATTERNS="$(jq -r '.copyIfMissing.patterns[]' "$MANIFEST")"
MERGE_FILES="$(jq -r '.mergeFiles.files | keys[]' "$MANIFEST")"
DERIVED_COUNT="$(jq -r '.templateDerived.mappings | length' "$MANIFEST")"

# ── Build file lists ───────────────────────────────────────────────────────
TEMPLATE_OWNED_FILES="$(echo "$TEMPLATE_OWNED_PATTERNS" | expand_patterns "$TEMPLATE_DIR")"
COPY_IF_MISSING_FILES="$(echo "$COPY_IF_MISSING_PATTERNS" | expand_patterns "$TEMPLATE_DIR")"

# Build templateDerived file list: source → target pairs (tab-separated)
# Only includes files where the target already exists in the project.
DERIVED_UPDATE=""
DERIVED_ADD=""
i=0
while [ "$i" -lt "$DERIVED_COUNT" ]; do
  src_dir="$(jq -r ".templateDerived.mappings[$i].source" "$MANIFEST")"
  tgt_dir="$(jq -r ".templateDerived.mappings[$i].target" "$MANIFEST")"
  strip="$(jq -r ".templateDerived.mappings[$i].strip_suffix" "$MANIFEST")"

  if [ -d "$TEMPLATE_DIR/$src_dir" ]; then
    find "$TEMPLATE_DIR/$src_dir" -type f 2>/dev/null | while IFS= read -r src_file; do
      # Get filename, strip suffix to get target filename
      basename="$(basename "$src_file")"
      target_name="$(echo "$basename" | sed "s/$strip//")"
      src_rel="${src_file#$TEMPLATE_DIR/}"
      tgt_rel="$tgt_dir/$target_name"

      if [ -f "$TARGET_DIR/$tgt_rel" ]; then
        printf "%s\t%s\n" "$src_rel" "$tgt_rel"
      else
        printf "MISSING\t%s\t%s\n" "$src_rel" "$tgt_rel"
      fi
    done
  fi
  i=$((i + 1))
done > /tmp/update_derived_$$

DERIVED_UPDATE="$(grep -v '^MISSING' /tmp/update_derived_$$ 2>/dev/null || true)"
DERIVED_ADD="$(grep '^MISSING' /tmp/update_derived_$$ 2>/dev/null | cut -f2,3 || true)"
rm -f /tmp/update_derived_$$

# Filter copyIfMissing to only files that are actually missing in target
COPY_IF_MISSING_ACTUAL=""
echo "$COPY_IF_MISSING_FILES" | while IFS= read -r f; do true; done  # no-op to check
COPY_IF_MISSING_ACTUAL="$(echo "$COPY_IF_MISSING_FILES" | while IFS= read -r f; do
  [ -z "$f" ] && continue
  if [ ! -e "$TARGET_DIR/$f" ]; then
    echo "$f"
  fi
done)"

# Filter merge files to only those that exist in both template and target
MERGE_ACTUAL=""
MERGE_ADD=""
echo "$MERGE_FILES" | while IFS= read -r f; do true; done  # no-op to check
MERGE_ACTUAL="$(echo "$MERGE_FILES" | while IFS= read -r f; do
  [ -z "$f" ] && continue
  if [ -f "$TEMPLATE_DIR/$f" ] && [ -f "$TARGET_DIR/$f" ]; then
    echo "$f"
  fi
done)"
MERGE_ADD="$(echo "$MERGE_FILES" | while IFS= read -r f; do
  [ -z "$f" ] && continue
  if [ -f "$TEMPLATE_DIR/$f" ] && [ ! -f "$TARGET_DIR/$f" ]; then
    echo "$f"
  fi
done)"

# ── Dry-run report ─────────────────────────────────────────────────────────
header "Plan"

# Overwrite (templateOwned)
OVERWRITE_COUNT=0
echo "$TEMPLATE_OWNED_FILES" | while IFS= read -r f; do
  [ -z "$f" ] && continue
  overwrt "OVERWRITE  $f"
done
OVERWRITE_COUNT="$(echo "$TEMPLATE_OWNED_FILES" | grep -c . || true)"

# Merge
echo "$MERGE_ACTUAL" | while IFS= read -r f; do
  [ -z "$f" ] && continue
  strategy="$(jq -r --arg f "$f" '.mergeFiles.files[$f].strategy' "$MANIFEST")"
  merged "MERGE ($strategy)  $f"
done

# Merge files that don't exist in target yet — just copy
echo "$MERGE_ADD" | while IFS= read -r f; do
  [ -z "$f" ] && continue
  added "ADD (new)  $f"
done

# Copy if missing
echo "$COPY_IF_MISSING_ACTUAL" | while IFS= read -r f; do
  [ -z "$f" ] && continue
  added "ADD (missing)  $f"
done

# Template-derived (update generated files from templates)
echo "$DERIVED_UPDATE" | while IFS= read -r line; do
  [ -z "$line" ] && continue
  src="$(echo "$line" | cut -f1)"
  tgt="$(echo "$line" | cut -f2)"
  overwrt "DERIVED  $src → $tgt"
done

# Skipped (projectOwned) — just list a summary
PROJECT_OWNED_FILES="$(echo "$PROJECT_OWNED_PATTERNS" | expand_patterns "$TARGET_DIR" 2>/dev/null || true)"
SKIP_COUNT="$(echo "$PROJECT_OWNED_FILES" | grep -c . || true)"
skipped "SKIP  $SKIP_COUNT project-owned file(s)"

# Meta files
added "WRITE  .claude/template-version → $TEMPLATE_VERSION"

echo ""

if [ "$DRY_RUN" = true ]; then
  info "Dry run complete — no files were modified."
  exit 0
fi

# ── Confirmation ───────────────────────────────────────────────────────────
if [ "$FORCE" != true ]; then
  printf "Apply these changes? [y/N] "
  read -r confirm
  case "$confirm" in [Yy]*) ;; *) info "Aborted."; exit 0 ;; esac
fi

# ── Execute: templateOwned (overwrite) ─────────────────────────────────────
header "Applying updates..."

echo "$TEMPLATE_OWNED_FILES" | while IFS= read -r f; do
  [ -z "$f" ] && continue
  mkdir -p "$TARGET_DIR/$(dirname "$f")"
  cp "$TEMPLATE_DIR/$f" "$TARGET_DIR/$f"
  overwrt "Overwritten: $f"
done

# ── Execute: templateDerived (update generated files from templates) ───────
echo "$DERIVED_UPDATE" | while IFS= read -r line; do
  [ -z "$line" ] && continue
  src="$(echo "$line" | cut -f1)"
  tgt="$(echo "$line" | cut -f2)"
  mkdir -p "$TARGET_DIR/$(dirname "$tgt")"
  cp "$TEMPLATE_DIR/$src" "$TARGET_DIR/$tgt"
  overwrt "Derived update: $tgt (from $src)"
done

# ── Execute: mergeFiles ────────────────────────────────────────────────────

# Merge JSON files using union_keys strategy:
# For each top-level key specified by mergeKey, add keys from template that
# are missing in project. Project's existing keys are never touched.
merge_json_union_keys() {
  local template_file="$1"
  local target_file="$2"
  local merge_key="$3"

  # Merge: template * target, with target taking precedence.
  # jq's * (multiply/merge) recursively merges objects. By putting template
  # first and project second, project values win on conflicts.
  local result
  result="$(jq -s --arg key "$merge_key" '
    .[0] as $template | .[1] as $project |
    $project | .[$key] = ($template[$key] * $project[$key])
  ' "$template_file" "$target_file")"

  echo "$result" | jq '.' > "$target_file"
}

# Merge files using union_lines strategy:
# Add lines from template that are not already present in target.
merge_union_lines() {
  local template_file="$1"
  local target_file="$2"

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    if ! grep -qxF "$line" "$target_file" 2>/dev/null; then
      echo "$line" >> "$target_file"
    fi
  done < "$template_file"
}

echo "$MERGE_ACTUAL" | while IFS= read -r f; do
  [ -z "$f" ] && continue
  strategy="$(jq -r --arg f "$f" '.mergeFiles.files[$f].strategy' "$MANIFEST")"

  case "$strategy" in
    union_keys)
      merge_key="$(jq -r --arg f "$f" '.mergeFiles.files[$f].mergeKey' "$MANIFEST")"
      merge_json_union_keys "$TEMPLATE_DIR/$f" "$TARGET_DIR/$f" "$merge_key"
      merged "Merged (union_keys on $merge_key): $f"
      ;;
    union_lines)
      merge_union_lines "$TEMPLATE_DIR/$f" "$TARGET_DIR/$f"
      merged "Merged (union_lines): $f"
      ;;
    *)
      warn "Unknown merge strategy '$strategy' for $f — skipping"
      ;;
  esac
done

# Merge files that don't exist in target — just copy
echo "$MERGE_ADD" | while IFS= read -r f; do
  [ -z "$f" ] && continue
  mkdir -p "$TARGET_DIR/$(dirname "$f")"
  cp "$TEMPLATE_DIR/$f" "$TARGET_DIR/$f"
  added "Added: $f"
done

# ── Execute: copyIfMissing ─────────────────────────────────────────────────
echo "$COPY_IF_MISSING_ACTUAL" | while IFS= read -r f; do
  [ -z "$f" ] && continue
  mkdir -p "$TARGET_DIR/$(dirname "$f")"
  cp "$TEMPLATE_DIR/$f" "$TARGET_DIR/$f"
  added "Added (was missing): $f"
done

# ── Write version marker ──────────────────────────────────────────────────
echo "$TEMPLATE_VERSION" > "$TARGET_VERSION_FILE"
added "Version marker updated: $TEMPLATE_VERSION"

# ── Report ─────────────────────────────────────────────────────────────────
header "Update complete"
info "Updated from ${BOLD}$TARGET_VERSION${NC} → ${BOLD}$TEMPLATE_VERSION${NC}"
info "Run 'git diff' in your project to review all changes."

# Check for major version bump and suggest migration guide
if [ "$TARGET_VERSION" != "(unknown)" ]; then
  OLD_MAJOR="${TARGET_VERSION%%.*}"
  NEW_MAJOR="${TEMPLATE_VERSION%%.*}"
  if [ "$NEW_MAJOR" -gt "$OLD_MAJOR" ] 2>/dev/null; then
    warn "This is a major version upgrade. Check CHANGELOG.md for breaking changes."
  fi
fi