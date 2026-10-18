#!/bin/bash
# Keeps the Surface Pro 7 (i5-1035G4) from overheating into 200 MHz stalls. Run with sudo.
# With tuned's throughput-performance profile the CPU ran at its 25 W cTDP-up limit, reached ~89 C
# within minutes and was then clamped to 200 MHz (GPU 100 MHz) until it cooled to ~55 C.
# This switches tuned to balanced and caps package power at the chip's rated 15 W (25 W short boost).
# Undo: sudo rm /etc/udev/rules.d/90-surface-power-limits.rules && sudo tuned-adm profile throughput-performance, then reboot
set -e
[ "$(id -u)" = 0 ] || { echo "Run with sudo"; exit 1; }
PL1=${PL1:-15000000}
PL2=${PL2:-25000000}
tuned-adm profile balanced
# udev applies the limits whenever the power capping devices appear, including at every boot
RULE=/etc/udev/rules.d/90-surface-power-limits.rules
cat > $RULE <<RULES
ACTION=="add|change", SUBSYSTEM=="powercap", KERNEL=="intel-rapl:0|intel-rapl-mmio:0", ATTR{constraint_0_power_limit_uw}="$PL1", ATTR{constraint_1_power_limit_uw}="$PL2"
RULES
udevadm control --reload
udevadm trigger --action=change --subsystem-match=powercap
udevadm settle
tuned-adm active
grep -H . /sys/class/powercap/intel-rapl:0/constraint_[01]_power_limit_uw /sys/class/powercap/intel-rapl-mmio:0/constraint_[01]_power_limit_uw
