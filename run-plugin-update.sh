#!/usr/bin/env bash
# Deliberately argument-free: Omarchy's floating-terminal wrapper receives a
# plain `bash path/to/this-file` command, so no nested quoting is involved.
set -u

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
bash "$script_dir/update-plugins.sh"
status=$?

if (( status == 0 )); then
  runtime_dir=${XDG_RUNTIME_DIR:-/tmp}
  date +%s%N > "$runtime_dir/omarchy-update-center-complete"
  printf '\n\033[1;32m✓ Mise à jour OK.\033[0m\n'
fi

exit "$status"
