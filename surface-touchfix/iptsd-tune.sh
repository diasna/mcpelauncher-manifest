#!/bin/bash
# Lets iptsd follow fast swipes (kids). Run with sudo. Keeps a backup in /etc/iptsd.conf.bak
# Default PositionThresholdMax = 2 cm per scan (~160 cm/s at 80 Hz): faster movement is dropped,
# so the view freezes and then jumps. Fast fingertips also smear, so SizeThresholdMax is raised too.
set -e
[ "$(id -u)" = 0 ] || { echo "Run with sudo"; exit 1; }
CONF=/etc/iptsd.conf
[ -f $CONF.bak ] || cp $CONF $CONF.bak
sed -i -E 's/^#? ?PositionThresholdMax = .*/PositionThresholdMax = 10/; s/^#? ?SizeThresholdMax = .*/SizeThresholdMax = 1.0/' $CONF
grep -E "^(PositionThresholdMax|SizeThresholdMax)" $CONF
systemctl restart 'iptsd@*.service'
echo "iptsd restarted. Undo: sudo mv $CONF.bak $CONF && sudo systemctl restart 'iptsd@*.service'"
