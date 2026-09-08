# Update Center for Omarchy

A Quickshell bar widget that groups pending updates from four local sources:

- official Arch packages (`checkupdates`);
- AUR packages (`yay -Qua`);
- Flatpaks (`flatpak remote-ls --updates`);
- Git-managed third-party Omarchy plugins.

It checks when the shell starts and then every six hours. A middle-click on
the bar icon refreshes manually. No check installs anything; update controls
open an Omarchy floating terminal so the normal confirmation prompts and logs
remain visible.

## Requirements

Omarchy / Quickshell, `git`, and Bash are required. The widget uses the
following optional tools when they are installed:

- `checkupdates` (from `pacman-contrib`) for official Arch package updates;
- `yay` for AUR update checks;
- `flatpak` for Flatpak updates.

## Install

From the published repository:

```bash
omarchy plugin add https://github.com/Saiiiiiph/update-center.git --enable
```

For local development:

```bash
omarchy plugin validate ./omarchy-update-center
mkdir -p ~/.config/omarchy/plugins
ln -s "$(pwd)/omarchy-update-center" ~/.config/omarchy/plugins/io.github.saiiiiiph.update-center
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.saiiiiiph.update-center
```

Use `omarchy bar move io.github.saiiiiiph.update-center --section right` if desired.

## Remove

```bash
omarchy plugin remove io.github.saiiiiiph.update-center
```

## Notes

Plugin update checks fetch only each installed plugin's `origin` remote, with
credential prompts disabled and a 15-second timeout. This makes the result
fresh without changing a working tree. A plugin without an upstream branch is
silently skipped.
