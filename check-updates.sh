#!/usr/bin/env bash
# Emit tab-separated update records for Update Center.
# Fields: source, package-or-plugin, detail. This script never installs anything.
set -u

emit() {
  printf '%s\t%s\t%s\n' "$1" "$2" "$3"
}

if command -v checkupdates >/dev/null 2>&1; then
  while IFS=' ' read -r package old_version arrow new_version; do
    [[ -n ${package:-} ]] && emit system "$package" "${old_version:-?} → ${new_version:-?}"
  done < <(checkupdates --nocolor 2>/dev/null || true)
fi

if command -v yay >/dev/null 2>&1; then
  while IFS=' ' read -r package old_version arrow new_version; do
    [[ -n ${package:-} ]] && emit aur "$package" "${old_version:-?} → ${new_version:-?}"
  done < <(timeout 45 yay -Qua 2>/dev/null || true)
fi

if command -v flatpak >/dev/null 2>&1; then
  while IFS=$'\t' read -r app version size; do
    [[ -n ${app:-} ]] && emit flatpak "$app" "${version:-Update available}${size:+ · $size}"
  done < <(flatpak remote-ls --updates --columns=application,version,download-size 2>/dev/null || true)
fi

plugin_root="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins"
if [[ -d $plugin_root ]]; then
  while IFS= read -r -d '' plugin; do
    git -C "$plugin" remote get-url origin >/dev/null 2>&1 || continue
    GIT_TERMINAL_PROMPT=0 timeout 15 git -C "$plugin" fetch --quiet 2>/dev/null || continue
    ahead=$(git -C "$plugin" rev-list --count 'HEAD..@{upstream}' 2>/dev/null || echo 0)
    [[ $ahead =~ ^[1-9][0-9]*$ ]] || continue
    emit plugin "$(basename "$plugin")" "$ahead new commit$([[ $ahead == 1 ]] || printf 's')"
  done < <(find "$plugin_root" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
fi
