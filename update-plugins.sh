#!/usr/bin/env bash
# Update only the supplied Omarchy plugins, following each checkout's actual
# upstream branch instead of the remote's potentially unrelated HEAD.
set -euo pipefail

plugins_root="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins"
updated=0
targets=("$@")

fail() {
  printf 'Update Center: %s\n' "$*" >&2
  return 1
}

confirm_update() {
  local answer
  # The floating terminal owns stdin. Reading it directly is more reliable
  # than reopening /dev/tty under uwsm/xdg-terminal-exec.
  read -r -p "Mettre à jour $1 ? [y/N] " answer || return 1
  [[ $answer =~ ^[Yy]([Ee][Ss])?$ ]]
}

# With no explicit ids, discover only checkouts genuinely behind their own
# configured upstream. This avoids both the remote-HEAD bug and noisy
# "is up to date" lines for unrelated plugins.
if (( ${#targets[@]} == 0 )); then
  while IFS= read -r -d '' dir; do
    [[ -d $dir/.git ]] || continue
    upstream=$(git -C "$dir" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || true)
    [[ $upstream == */* ]] || continue
    remote=${upstream%%/*}
    branch=${upstream#*/}
    GIT_TERMINAL_PROMPT=0 git -C "$dir" fetch --quiet "$remote" "$branch" 2>/dev/null || continue
    [[ $(git -C "$dir" rev-parse HEAD) == $(git -C "$dir" rev-parse FETCH_HEAD) ]] && continue
    targets+=("$(basename "$dir")")
  done < <(find "$plugins_root" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
fi

if (( ${#targets[@]} == 0 )); then
  printf 'Aucune mise à jour de plugin disponible.\n'
  exit 0
fi

for id in "${targets[@]}"; do
  [[ $id =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { fail "invalid plugin id: $id"; continue; }
  dir="$plugins_root/$id"
  [[ -d $dir/.git ]] || { fail "$id is not a Git-managed plugin"; continue; }

  upstream=$(git -C "$dir" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || true)
  [[ $upstream == */* ]] || { fail "$id has no upstream branch"; continue; }
  remote=${upstream%%/*}
  branch=${upstream#*/}

  if ! GIT_TERMINAL_PROMPT=0 git -C "$dir" fetch --quiet "$remote" "$branch"; then
    fail "could not fetch $id from $upstream"
    continue
  fi

  if [[ $(git -C "$dir" rev-parse HEAD) == $(git -C "$dir" rev-parse FETCH_HEAD) ]]; then
    printf '%s is up to date.\n' "$id"
    continue
  fi

  commit_count=$(git -C "$dir" rev-list --count HEAD..FETCH_HEAD)
  shortstat=$(git -C "$dir" diff --shortstat HEAD FETCH_HEAD)
  printf 'Résumé pour %s (%s) :\n' "$id" "$upstream"
  printf '  • %s nouveaux commits\n' "$commit_count"
  printf '  • %s\n' "${shortstat:-Aucun changement de fichier détecté}"
  printf '  • Principaux fichiers :\n'
  git -C "$dir" diff --name-only HEAD FETCH_HEAD | sed -n '1,5{s/^/    – /;p;}'
  printf '\n'

  if ! confirm_update "$id"; then
    printf 'Skipped %s.\n' "$id"
    continue
  fi

  if ! git -C "$dir" merge --ff-only FETCH_HEAD; then
    fail "cannot fast-forward $id; check for local changes"
    continue
  fi
  if ! omarchy plugin validate "$dir"; then
    git -C "$dir" reset --hard ORIG_HEAD >/dev/null
    fail "$id failed validation and was rolled back"
    continue
  fi

  printf 'Updated %s.\n' "$id"
  updated=1
done

if (( updated )); then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
fi
