#!/bin/bash
# Installs the launch script, the Xbox login wrapper and a dock shortcut for the build from build.sh
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$HOME/.local/opt/mcpelauncher-touchfix
[ -x "$OUT/bin/mcpelauncher-client" ] || { echo "Run build.sh first"; exit 1; }
install -m 755 "$HERE/run.sh" "$OUT/run.sh"
install -m 755 "$HERE/mcpelauncher-webview" "$OUT/bin/mcpelauncher-webview"
mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/mcpelauncher-touchfix.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Minecraft (touch fix)
Exec=$OUT/run.sh
Icon=io.mrarm.mcpelauncher
Categories=Game;
StartupWMClass=mcpelauncher-client
DESKTOP
# Pin to the GNOME dock
FAV=$(gsettings get org.gnome.shell favorite-apps)
case "$FAV" in
  *mcpelauncher-touchfix.desktop*) ;;
  "@as []") gsettings set org.gnome.shell favorite-apps "['mcpelauncher-touchfix.desktop']" ;;
  *) gsettings set org.gnome.shell favorite-apps "${FAV%]}, 'mcpelauncher-touchfix.desktop']" ;;
esac
echo "Installed. Launch 'Minecraft (touch fix)' from the dock."
