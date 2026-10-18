#!/bin/bash
# Logs game memory, temperatures, clocks and throttling every 30s while mcpelauncher-client runs.
OUT=${1:-$PWD/perf-log.csv}
until P=$(pgrep -f "bin/mcpelauncher-client " | head -1) && [ -n "$P" ]; do sleep 5; done
echo "minutes,rss_mb,cpu_pct,threads,pkg_temp_c,cpu_avg_mhz,gpu_mhz,throttle_ms" > "$OUT"
T0=$(date +%s)
while kill -0 "$P" 2>/dev/null; do
  read RSS CPU NLWP < <(ps -o rss=,%cpu=,nlwp= -p "$P")
  TEMP=$(for z in /sys/class/thermal/thermal_zone*; do [ "$(cat $z/type)" = x86_pkg_temp ] || [ "$(cat $z/type)" = B0D4 ] && cat $z/temp; done | sort -n | tail -1)
  MHZ=$(awk '/MHz/ {s+=$4;n++} END {printf "%.0f", s/n}' /proc/cpuinfo)
  GPU=$(cat /sys/class/drm/card1/gt_act_freq_mhz 2>/dev/null)
  THR=$(cat /sys/devices/system/cpu/cpu*/thermal_throttle/package_throttle_total_time_ms 2>/dev/null | sort -n | tail -1)
  NOW=$(date +%s)
  echo "$(( (NOW - T0) / 60 )),$(( RSS / 1024 )),$CPU,$NLWP,$(( ${TEMP:-0} / 1000 )),$MHZ,$GPU,$THR" >> "$OUT"
  sleep 30
done
