#!/bin/bash
# Runs the touch-patched mcpelauncher-client on the game/worlds installed by the Flatpak launcher.
D=$HOME/.var/app/io.mrarm.mcpelauncher/data/mcpelauncher
VER=$(ls -1 "$D/versions" | grep -v '\.ini$' | sort -V | tail -1)
# Same mods as the Flatpak "Default" profile (mcpelauncher-updates is needed for newer game versions)
MODS=$(grep -E '^mods\\[0-9]+\\path=' "$D/profiles/profiles.ini" | cut -d= -f2- | paste -sd,)
# bin/ holds the mcpelauncher-webview wrapper used for Xbox Live login
export PATH="$HOME/.local/opt/mcpelauncher-touchfix/bin:$PATH"
# Keep the output of dock launches for debugging
[ -t 1 ] || exec >"$HOME/.local/opt/mcpelauncher-touchfix/last-run.log" 2>&1
# Screen-sized window (2736x1824 @ 150% = 1824x1216 logical); GNOME auto-maximizes it
exec "$HOME/.local/opt/mcpelauncher-touchfix/bin/mcpelauncher-client" -ww 1824 -wh 1216 -dg "$D/versions/$VER" -dd "$D" ${MODS:+-m "$MODS"} "$@"
