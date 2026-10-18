# Surface Pro 7 touch fix (fork notes)

This branch (`surface-touchfix` of `diasna/mcpelauncher-manifest`) is a personal fork that makes touch input work properly on a **Surface Pro 7 running Fedora (linux-surface kernel, iptsd, GNOME Wayland)**. The upstream README follows below this section.

Everything here was worked out on 2026-10-18. Starting point: Flatpak launcher `io.mrarm.mcpelauncher` v1.8.4, Minecraft 1.26.52.3, Fedora 43, iptsd 3.1.0.

## Reinstall after a clean Fedora install

1. Install the linux-surface kernel and iptsd: https://github.com/linux-surface/linux-surface/wiki/Installation-and-Setup. Check that touch works on the desktop.
2. Install the normal launcher: `flatpak install flathub io.mrarm.mcpelauncher`. Open it once, sign in, and download/start the game. This creates the game files, worlds and profile that the patched build reuses (`~/.var/app/io.mrarm.mcpelauncher/data/mcpelauncher`). Back up that folder before reinstalling if you want to keep worlds.
3. Install podman and git if missing: `sudo dnf install podman git`. No compiler is needed on the host.
4. Get this fork and build it:
   ```
   git clone --recursive -b surface-touchfix https://github.com/diasna/mcpelauncher-manifest
   cd mcpelauncher-manifest
   surface-touchfix/build.sh        # builds in a fedora:43 container, ~15-30 min the first time
   surface-touchfix/install.sh      # run script, Xbox login wrapper, dock shortcut
   sudo surface-touchfix/iptsd-tune.sh
   sudo surface-touchfix/thermal-tune.sh   # prevents the overheating slowdown, see below
   ```
5. Launch **Minecraft (touch fix)** from the dock. Output of the last launch goes to `~/.local/opt/mcpelauncher-touchfix/last-run.log`.

If the clone fails on a submodule, all submodule URLs in `.gitmodules` are absolute. Only `mcpelauncher-client` and `game-window` point at the `diasna` forks; everything else is upstream.

## What was wrong and what was changed

All four client commits are on branch `surface-touchfix` of https://github.com/diasna/mcpelauncher-client, and the window commit is on branch `surface-touchfix` of https://github.com/diasna/game-window. An upstream PR (minecraft-linux/mcpelauncher-client#156, first fix only) was opened and then closed; these changes are kept in the fork only.

| Symptom | Cause | Fix |
|---|---|---|
| Touch barely works: dragging does nothing, buttons stay pressed | With ImGui, the first finger's MOVE/UP were always swallowed, even when ImGui did not take the touch (since upstream commit 1764dc5) | client `957da53`: only swallow when ImGui captured the DOWN (`imGuiTouchCaptured`) |
| Look-around swipe jerky, swipes sometimes act as a click | `sendTouchEvent` sent one pointer per event, ACTION_DOWN/UP for every finger and `eventTime`/`downTime` = 0 | client `a76fd03`: Android-style events with all active fingers, POINTER_DOWN/UP and real timestamps |
| Scrolling lists (recipes) stutters | Events are polled once per frame (`fake_looper.cpp`), so stamping them on dispatch gave every move in a frame nearly the same time | game-window `3d54ec9` adds `GameWindow::getEventTime()` (SDL's event timestamp); client `6f73105` uses it |
| Kids: swipes freeze then jump | iptsd drops movement over `PositionThresholdMax` (2 cm per scan, ~160 cm/s at ~80 Hz). Kids swiped ~875 cm/s, an adult ~460 cm/s | `iptsd-tune.sh`: `PositionThresholdMax = 10`, `SizeThresholdMax = 1.0` in `/etc/iptsd.conf` |
| Kids: blocks placed by accident | Light touches drop out for 1-2 scans (10-20 ms) mid-swipe; the game sees each piece as a ~30 ms tap. One minute of a kid playing: 121 short taps, only 6 with a second finger down, normal finger size | client `378b6df`: releases are held 100 ms; a finger landing within 5% of the window diagonal continues the lost pointer. Replaying the recording: 121 → 8 short taps |

Other things the patched build needs, all handled by the scripts:

- **Build without Qt.** `build.sh` uses `BUILD_UI=OFF BUILD_WEBVIEW=OFF`. The Flatpak launcher is still used to download versions and sign in.
- **Xbox login error `0x80070057`.** The client runs `mcpelauncher-webview` from `PATH` for sign-in. `surface-touchfix/mcpelauncher-webview` is a wrapper that runs the Flatpak's copy, and `run.sh` puts it on `PATH`.
- **Crash on start with `cannot locate symbol "pthread_sigmask"`.** This happens when the `mcpelauncher-updates` mod is missing. `run.sh` loads the mods listed in the Flatpak's Default profile.
- **Window size.** `run.sh` passes `-ww 1824 -wh 1216` (2736x1824 at 150% scale), so GNOME maximizes the window. Change it if the scale or screen changes.
- **Dock grouping.** The SDL3 window's app id is the executable name, so the desktop file sets `StartupWMClass=mcpelauncher-client`.

## Files in `surface-touchfix/`

| File | Purpose |
|---|---|
| `build.sh` | Builds the client in a `fedora:43` podman container into `~/.local/opt/mcpelauncher-touchfix` (build dir `~/.cache/mcpelauncher-touchfix-build`) |
| `install.sh` | Installs `run.sh` and the webview wrapper, creates the desktop entry and pins it to the dock |
| `run.sh` | Starts the game using the Flatpak's newest installed version, its data and its profile mods |
| `mcpelauncher-webview` | Xbox Live login window, taken from the Flatpak |
| `iptsd-tune.sh` | Raises iptsd's movement and size limits (backup in `/etc/iptsd.conf.bak`) |
| `thermal-tune.sh` | Switches tuned to `balanced` and caps CPU power at 15 W (25 W boost) via a udev rule (`/etc/udev/rules.d/90-surface-power-limits.rules`) |
| `perf-log.sh` | While the game runs, logs memory, temperature, CPU/GPU clocks and throttling every 30 s to `perf-log.csv` |
| `touch-probe.py` | Records touches from the iptsd virtual touchscreen and reports taps, broken swipes, speed and jumps; saves raw data next to itself as `touch-probe-last.json` |

## Game slows down over time (overheating)

Measured 2026-10-18 with `perf-log.sh` over 17 minutes of play:
- **Memory was not the problem.** The game used about 1.45-1.6 GB after loading the world, growing slowly as new map areas loaded.
- **The chip overheated and stalled.** With tuned's `throughput-performance` profile (EPP `performance`, 25 W sustained power limit, the i5-1035G4's cTDP-up maximum; the chip is rated 15 W), the CPU reached 82-89 C within about 8 minutes. Then the CPU was clamped to **200 MHz** and the GPU to **100 MHz** for 2-3 minutes until it cooled to ~55 C, and this repeated. No thermald config (`/etc/thermald/thermal-conf.xml`) is installed.
- **Fix:** `sudo surface-touchfix/thermal-tune.sh` switches tuned to `balanced` and limits power to 15 W sustained / 25 W boost. The aim is steady, slightly lower speed instead of full speed followed by stalls. *Status: added 2026-10-18; confirm with another `perf-log.sh` run after applying.*
- **Check it:** start the game, run `surface-touchfix/perf-log.sh` in a terminal, play until it would normally slow down, then close the game and look at `perf-log.csv`. Rows with `cpu_avg_mhz` around 200 mean it is still stalling; then try `sudo PL1=12000000 PL2=20000000 surface-touchfix/thermal-tune.sh`.
- Lowering Minecraft's render distance or the window size in `run.sh` also reduces heat.

## Diagnosing touch again

Run the probe in a normal terminal (sudo needs a password prompt), then play for a minute:

```
sudo python3 -I surface-touchfix/touch-probe.py 60 | tee probe.txt
```

How to read it:
- **Swipes that broke apart** high, or many **short taps** with median duration ~30 ms: light-touch dropouts. Tune the 100 ms window (`touchDropoutNs`) or the 5% distance in `sendFingerEvent` (`mcpelauncher-client/src/window_callbacks.cpp`). Lowering iptsd's `ActivationThreshold` (default 24) is the driver-side alternative, but it may add ghost touches.
- **Biggest jump per scan** near or above `PositionThresholdMax`: fast swipes are being dropped. Raise it in `/etc/iptsd.conf`.
- Many short taps **while another finger was down** or near the edge: palm or hand contact. iptsd's `DisableOnPalm` or Minecraft's touch control scheme (crosshair or buttons instead of tap-to-place) can help.

## Updating to a newer upstream launcher

```
git -C mcpelauncher-client fetch https://github.com/minecraft-linux/mcpelauncher-client master
git -C mcpelauncher-client rebase FETCH_HEAD          # the 4 touch commits move on top
git -C game-window fetch https://github.com/minecraft-linux/game-window master
git -C game-window rebase FETCH_HEAD
# push both rebased branches to the forks, commit the new submodule pointers here, then build.sh again
```

If the game needs a newer launcher than this fork, the Flatpak launcher will still run it, but without these touch fixes.

---

# mcpelauncher

An unstable unofficial launcher for the Android version of Minecraft: Bedrock Edition on linux and macOS.

# UI

The User Interface to login, download and manage Versions can be found [here](https://github.com/minecraft-linux/mcpelauncher-ui-manifest)

# System Requirements

> [!WARNING]
> Once the new OpenGL ES 3.1 system requirement for "Vibrant Visuals" aka "Deferred Technical Preview" of 31. March 2025 no longer allow the game to start using classic "Fancy" Graphics on OpenGL ES 3.0 the **macOS port Minecraft updates are going to be on hold**

Operating System|Architecture|Requirements|Minecraft Versions
---|---|---|---
linux glibc|x86|Intel or Amd CPU with SSSE3 Instruction Set and OpenGL ES 2.0 or newer.|1.13.0 - 1.20.20
linux glibc|x86|Intel or Amd CPU with SSSE3 Instruction Set and OpenGL ES 3.0 or newer.|1.13.0 - 1.21.73
macOS 10.10 - 10.14|x86|Intel or Amd CPU with SSSE3 Instruction Set.|1.13.0 - 1.16.1X
linux glibc|x86_64|Intel or Amd CPU with SSSE3, SSE4.1, SSE4.2,  POPCNT Instruction Sets and OpenGL ES 2.0 or newer.|1.13.0 - 1.20.20
linux glibc|x86_64|Intel or Amd CPU with SSSE3, SSE4.1, SSE4.2, POPCNT Instruction Sets and OpenGL ES 3.0 or newer.|1.13.0 - 1.21.73
macOS 10.10 - latest|x86_64|Intel or Amd CPU with SSSE3, SSE4.1, SSE4.2 and POPCNT Instruction Sets. Rosetta 2 worked in macOS 11 and 12, but no longer in macOS 13|1.13.0 - 1.21.73
linux glibc|arm32|armv7 CPU, pulseaudio and OpenGL ES 2.0 or newer|1.13.0 - 1.18.10
linux glibc|arm64|armv7 CPU, pulseaudio and OpenGL ES 3.0 or newer|1.13.0 - 1.21.73
linux glibc|arm64|armv8 CPU, pulseaudio and OpenGL ES 2.0 or newer|1.13.0 - 1.20.20
linux glibc|arm64|armv8 CPU, pulseaudio and OpenGL ES 3.0 or newer|1.13.0 - 1.21.73
macOS 11.0 - latest|arm64|apple m series CPU (Experimental, modding limitations)|1.19.70 - 1.21.73

## Versions 1.20.30+ will not have hardware rendering on older hardware (GLES 3.0 is now required)

Read Issue https://github.com/minecraft-linux/mcpelauncher-manifest/issues/933 to force software rendering to be able to run them anyway

For mesa3d this would be defining `LIBGL_ALWAYS_SOFTWARE` to `1` of the launcher process. Alternatively you can replace your libEGl drivers with <https://github.com/google/angle/> and tell it to use the swiftshader backend.

# Important Minecraft Version specific Bugs

Minecraft Version|Bug Description
---|---
1.13.0 - 1.16.1X|Xbox login doesn't work. It is working in previous Versions of this Launcher.
1.16.20 - latest|No sound for macOS x86 launcher without compiling yourself with pulseaudio
1.16.210 - 1.17.4X|Crafting is broken on x86 and x86_64 based devices
1.16.210 - 1.17.4X|Textures are off by one on x86 and x86_64 based devices, enable texture patch in profile settings to mitigate this Bug
1.16.210 - 1.17.4X|World Corruption while next to water
1.18.30 - latest|The armv7 port might not work correctly
1.19.50 - latest|You cannot sprint while diagonal strafing on Intel cpu (see [MCPE-170810](https://bugs.mojang.com/browse/MCPE-170810))
all|You are unable to receive Xbox live game invites
all|You may be unable to join worlds hosted by this launcher using Xbox live friends joining

# Wiki

Please check our wiki https://minecraft-linux.github.io for information about compiling or installing this launcher.
The old wiki of readthedocs is obsolete.

# Nightly Prebuilds

[AppImage (Deprecated) and DMG Files](https://github.com/minecraft-linux/mcpelauncher-manifest/releases/tag/nightly)
[Debian, Ubuntu and Fedora Packages (ca. 1-24h delay)](https://github.com/minecraft-linux/pkg?tab=readme-ov-file#nightly)
[flatpak install flathub-beta io.mrarm.mcpelauncher (ca. 1-24h delay)](https://discourse.flathub.org/t/how-to-use-flathub-beta/2111)
