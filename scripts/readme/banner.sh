#!/usr/bin/env bash
#   scripts/readme/banner.sh          write docs/readme/banner.svg and docs/readme/cat.png
#   scripts/readme/banner.sh --check  exit 1 if either is out of date
#
# banner.svg uses CSS animation only and embeds the PNGs, so GitHub can show it through <img>.
set -euo pipefail
cd "$(dirname "$0")/../.."
export LC_ALL=C

references="${README_REFERENCES:-Tests/DrowsyDockTests/Snapshots}"
assets="${README_ASSETS:-docs/readme}"
mode="${1:-write}"
case "$mode" in
  write | --check) ;;
  *)
    echo "usage: scripts/readme/banner.sh [--check]" >&2
    exit 2
    ;;
esac

loop=16

calc() {
  awk "BEGIN { printf \"%.6g\", $1 }"
}

# The number PATTERN's group captures on its one matching line of FILE, from the first line that
# matches AFTER if given. The banner reads the app's values this way, so it can't drift from them.
swift_value() {
  local file="$1" pattern="$2" after="${3:-}" address="" values
  if [[ -n $after ]]; then address="/$after/,/$pattern/ "; fi
  values="$(sed -nE "${address}s/.*$pattern.*/\\1/p" "$file")"
  if [[ -z $values || $values == *$'\n'* ]]; then
    echo "banner.sh: /$pattern/ must match one line of $file" >&2
    exit 1
  fi
  printf '%s' "$values"
}

swift_seconds() {
  local duration
  duration="$(swift_value "$1" "$2 = Duration\.([a-z]+\([0-9]+\))")"
  case "$duration" in
    seconds*) calc "${duration//[^0-9]/}" ;;
    milliseconds*) calc "${duration//[^0-9]/} / 1000" ;;
    *)
      echo "banner.sh: $2 in $1 is neither seconds nor milliseconds" >&2
      exit 1
      ;;
  esac
}

thresholds_swift=Sources/DrowsyDockCore/Thresholds.swift
asleep_below="$(swift_value "$thresholds_swift" 'asleepBelow: ([0-9]+)')"
nodding_off_below="$(swift_value "$thresholds_swift" 'noddingOffBelow: ([0-9]+)')"
yawning_below="$(swift_value "$thresholds_swift" 'yawningBelow: ([0-9]+)')"
drowsy_below="$(swift_value "$thresholds_swift" 'validatedDrowsyBelow: ([0-9]+)')"
veil_opacity="$(swift_value Sources/DrowsyDockCore/MascotPose.swift 'veilOpacity: ([0-9.]+)')"

crowd_wave_swift=Sources/DrowsyDockCore/CrowdWave.swift
icon_seconds="$(swift_seconds "$crowd_wave_swift" iconEffectDuration)"
dim_seconds="$(swift_seconds "$crowd_wave_swift" dimDuration)"
stagger_seconds="$(swift_seconds "$crowd_wave_swift" preferredStagger)"

crowd_node_swift=Sources/DrowsyDock/CrowdEffectNode.swift
dim_opacity="$(swift_value "$crowd_node_swift" 'dimOpacity: CGFloat = ([0-9.]+)')"
dim_fade_in="$(swift_value "$crowd_node_swift" 'dimPhases = \(fadeIn: ([0-9.]+)')"
dim_hold="$(swift_value "$crowd_node_swift" 'dimPhases = \(.*hold: ([0-9.]+)')"
dim_fade_out="$(swift_value "$crowd_node_swift" 'dimPhases = \(.*fadeOut: ([0-9.]+)')"
puff_fade_in="$(swift_value "$crowd_node_swift" 'fadeIn\(withDuration: life \* ([0-9.]+)\)')"
puff_hold="$(swift_value "$crowd_node_swift" 'wait\(forDuration: life \* ([0-9.]+)\)')"
puff_fade_out="$(swift_value "$crowd_node_swift" 'fadeOut\(withDuration: life \* ([0-9.]+)\)')"
z_start_scale="$(swift_value "$crowd_node_swift" 'z\.setScale\(([0-9.]+)\)')"
z_end_scale="$(swift_value "$crowd_node_swift" 'scale\(to: ([0-9.]+), duration: life\)')"
drift_dx="$(swift_value "$crowd_node_swift" 'drift = CGVector\(dx: ([0-9.]+),' 'case \.bottom:')"
drift_dy="$(swift_value "$crowd_node_swift" 'drift = CGVector\(.*dy: ([0-9.]+)\)' 'case \.bottom:')"

# The references are 2 pixels a point, and the banner draws them at 0.8 of their size.
units_per_point=1.6
wave_start=10.5

percent() {
  awk -v t="$1" -v loop="$loop" 'BEGIN { printf "%.6g%%", t * 100 / loop }'
}

keyframes() {
  local name="$1" property="$2" pair
  shift 2
  printf '@keyframes %s {' "$name"
  for pair in "$@"; do
    printf ' %s { %s: %s }' "$(percent "${pair%%:*}")" "$property" "${pair#*:}"
  done
  printf ' }\n'
}

fade=0.15

shown() {
  local name="$1" from="$2" to="$3"
  keyframes "$name" opacity 0:0 "$from:0" "$(calc "$from + $fade"):1" "$(calc "$to - $fade"):1" \
    "$to:0" "$loop:0"
}

shown_across_loop_end() {
  local name="$1" from="$2" to="$3"
  keyframes "$name" opacity 0:1 "$(calc "$to - $fade"):1" "$to:0" "$from:0" \
    "$(calc "$from + $fade"):1" "$loop:1"
}

fill_start=630
fill_length=210
thresholds=("$asleep_below" "$nodding_off_below" "$yawning_below" "$drowsy_below")

fill_dashoffset() {
  awk -v p="$1" -v span="$fill_length" 'BEGIN { printf "%.6gpx", span * (100 - p) / 100 }'
}

fill_x() {
  awk -v p="$1" -v start="$fill_start" -v span="$fill_length" \
    'BEGIN { printf "%.6g", start + span * p / 100 }'
}

threshold_labels() {
  local threshold
  for threshold in "${thresholds[@]}"; do
    printf '<text x="%s" y="214">%s</text>' "$(fill_x "$threshold")" "$threshold"
  done
}

threshold_ticks() {
  local threshold x
  for threshold in "${thresholds[@]}"; do
    x="$(fill_x "$threshold")"
    printf '<line x1="%s" y1="133" x2="%s" y2="198"/>' "$x" "$x"
  done
}

png() {
  printf 'data:image/png;base64,'
  base64 <"$references/$1" | tr -d '\n'
}

banner_css() {
  keyframes level stroke-dashoffset "0:$(fill_dashoffset 80)" "2.5:$(fill_dashoffset 80)" \
    "3:$(fill_dashoffset 40)" "5:$(fill_dashoffset 40)" "5.5:$(fill_dashoffset 25)" \
    "7.5:$(fill_dashoffset 25)" "8:$(fill_dashoffset 15)" "10:$(fill_dashoffset 15)" \
    "10.5:$(fill_dashoffset 5)" "15:$(fill_dashoffset 5)" "15.75:$(fill_dashoffset 80)" \
    "16:$(fill_dashoffset 80)"
  keyframes charge stroke 0:#34c759 0.5:#34c759 0.51:#6b7383 13.25:#6b7383 13.26:#34c759 \
    16:#34c759
  keyframes plug transform 0:none 0.5:translateX\(60px\) 12.75:translateX\(60px\) 13.25:none \
    16:none
  shown_across_loop_end bolt 13.25 0.5
  keyframes base opacity 0:1 3:1 3.01:0 16:0
  keyframes drowsy opacity 0:0 2.75:0 3:1 5.5:1 5.51:0 16:0
  keyframes yawning opacity 0:0 5.25:0 5.5:1 8:1 8.01:0 16:0
  keyframes nodding opacity 0:0 7.75:0 8:1 10.5:1 10.51:0 16:0
  keyframes asleep opacity 0:0 10.25:0 10.5:1 13.5:1 13.51:0 16:0
  keyframes waking opacity 0:0 13.25:0 13.5:1 16:1
  keyframes stretch transform 0:none 13.5:none "13.75:scale(0.97, 1.06)" 14.1:none 16:none
  keyframes sparkle transform 0:scale\(0\) 13.6:scale\(0\) 13.9:scale\(1.3\) 14.5:scale\(1\) \
    14.9:scale\(0\) 16:scale\(0\)
  keyframes veil opacity 0:0 10.3:0 "$wave_start:$veil_opacity" "13.25:$veil_opacity" 13.45:0 \
    16:0
  keyframes dim opacity 0:0 "$wave_start:0" \
    "$(calc "$wave_start + $dim_seconds * $dim_fade_in"):$dim_opacity" \
    "$(calc "$wave_start + $dim_seconds * ($dim_fade_in + $dim_hold)"):$dim_opacity" \
    "$(calc "$wave_start + $dim_seconds * ($dim_fade_in + $dim_hold + $dim_fade_out)"):0" 16:0
  keyframes puff opacity 0:0 "$wave_start:0" \
    "$(calc "$wave_start + $icon_seconds * $puff_fade_in"):1" \
    "$(calc "$wave_start + $icon_seconds * ($puff_fade_in + $puff_hold)"):1" \
    "$(calc "$wave_start + $icon_seconds * ($puff_fade_in + $puff_hold + $puff_fade_out)"):0" \
    16:0
  local drift_x drift_y drifted
  drift_x="$(calc "$drift_dx * $units_per_point")"
  drift_y="$(calc "$drift_dy * $units_per_point")"
  drifted="translate(${drift_x}px, -${drift_y}px) scale($z_end_scale)"
  keyframes drift transform "0:scale($z_start_scale)" "$wave_start:scale($z_start_scale)" \
    "$(calc "$wave_start + $icon_seconds"):$drifted" "16:$drifted"
  shown s80d 0.5 3
  shown s40 3 5.5
  shown s25 5.5 8
  shown s15 8 10.5
  shown s5 10.5 13.25
  shown s5w 13.25 15.25
  shown_across_loop_end s80c 15.5 0.5
}

banner_svg() {
  cat <<EOF
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 900 300" width="900" height="300" role="img">
<title>DrowsyDock: the cat on the Dock gets drowsier as the battery drains, and wakes when a charger plugs in</title>
<style>
.a { animation-duration: ${loop}s; animation-timing-function: linear; animation-iteration-count: infinite }
.pose { opacity: 0 }
#asleep, #s5 { opacity: 1 }
#fill { stroke: #6b7383; stroke-dashoffset: $(fill_dashoffset 5); animation-name: level, charge }
#plug { transform: translateX(60px); animation-name: plug }
#bolt { opacity: 0; animation-name: bolt }
#base { animation-name: base }
#drowsy { animation-name: drowsy }
#yawning { animation-name: yawning }
#nodding { animation-name: nodding }
#asleep { animation-name: asleep }
#waking { animation-name: waking, stretch; transform-origin: 500.8px 150px }
.sparkle { transform: scale(0); animation-name: sparkle }
#veil { opacity: $veil_opacity; animation-name: veil }
.dim { opacity: 0; animation-name: dim }
.puff { opacity: 0; animation-name: puff }
.drift { transform: scale($z_start_scale); animation-name: drift }
.status { opacity: 0 }
#s80d { animation-name: s80d }
#s40 { animation-name: s40 }
#s25 { animation-name: s25 }
#s15 { animation-name: s15 }
#s5 { animation-name: s5 }
#s5w { animation-name: s5w }
#s80c { animation-name: s80c }
$(for i in 1 2 3 4; do printf '.i%s { animation-delay: %ss }\n' "$i" "$(calc "$i * $stagger_seconds")"; done)
.s1 { animation-delay: 0.2s }
.s2 { animation-delay: 0.4s }
$(banner_css)
@media (prefers-reduced-motion: reduce) { * { animation: none !important } }
</style>
<defs>
<image id="p-awake" x="449.6" y="22" width="102.4" height="128" href="$(png pose-awake-left.png)"/>
<image id="p-drowsy" x="449.6" y="22" width="102.4" height="128" href="$(png pose-drowsy-left.png)"/>
<image id="p-yawning" x="449.6" y="22" width="102.4" height="128" href="$(png pose-yawning-left.png)"/>
<image id="p-noddingOff" x="449.6" y="22" width="102.4" height="128" href="$(png pose-noddingOff-left.png)"/>
<image id="p-asleep" x="449.6" y="22" width="102.4" height="128" href="$(png pose-asleep-left.png)"/>
<path id="z" d="M-7.2 -7.2H7.2L-7.2 7.2H7.2" fill="none"/>
<path id="star" d="M0 6.7L-1.49 1.49L-6.7 0L-1.49 -1.49L0 -6.7L1.49 -1.49L6.7 0L1.49 1.49Z" fill="#ffe073" stroke="#c78c26" stroke-width="1.3"/>
<rect id="tile" width="77" height="77" rx="16"/>
</defs>
<rect width="900" height="300" rx="18" fill="#d6dce6"/>
<rect x="40" y="150" width="519" height="126" rx="36" fill="#ebeef3" stroke="#c2c8d2" stroke-width="1.5"/>
<g fill="#f9f9ff" stroke="#999fb0" stroke-width="1.5">
<use href="#tile" x="59" y="175"/><use href="#tile" x="160" y="175"/><use href="#tile" x="261" y="175"/><use href="#tile" x="362" y="175"/><use href="#tile" x="463" y="175"/>
</g>
<rect id="veil" class="a" x="40" y="150" width="519" height="126" rx="36"/>
<g fill="#000">
<use class="a dim" href="#tile" x="59" y="175"/><use class="a dim i1" href="#tile" x="160" y="175"/><use class="a dim i2" href="#tile" x="261" y="175"/><use class="a dim i3" href="#tile" x="362" y="175"/><use class="a dim i4" href="#tile" x="463" y="175"/>
</g>
<g stroke-linejoin="miter">
$(for i in 0 1 2 3 4; do
    x="$(calc "97.5 + 101 * $i")"
    delay=""
    if ((i > 0)); then delay=" i$i"; fi
    printf '<g class="a puff%s" transform="translate(%s 189.4)"><g class="a drift%s">' "$delay" "$x" "$delay"
    printf '<use href="#z" stroke="#2b3b66" stroke-width="6.05"/><use href="#z" stroke="#d6e6ff" stroke-width="3.17"/></g></g>\n'
  done)
</g>
<use id="base" class="a" href="#p-awake"/>
<use id="drowsy" class="a pose" href="#p-drowsy"/>
<use id="yawning" class="a pose" href="#p-yawning"/>
<use id="nodding" class="a pose" href="#p-noddingOff"/>
<use id="asleep" class="a pose" href="#p-asleep"/>
<use id="waking" class="a pose" href="#p-awake"/>
<g transform="translate(456 62)"><use class="a sparkle" href="#star"/></g>
<g transform="translate(541 36)"><use class="a sparkle s1" href="#star"/></g>
<g transform="translate(548 88)"><use class="a sparkle s2" href="#star"/></g>
<g font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif" text-anchor="middle">
<rect x="612" y="74" width="248" height="34" rx="17" fill="#f7f8fa" fill-opacity="0.7"/>
<g font-size="14" fill="#2b3340">
<text id="s80d" class="a status" x="736" y="96">80% &#183; Discharging &#183; Awake</text>
<text id="s40" class="a status" x="736" y="96">40% &#183; Discharging &#183; Drowsy</text>
<text id="s25" class="a status" x="736" y="96">25% &#183; Discharging &#183; Yawning</text>
<text id="s15" class="a status" x="736" y="96">15% &#183; Discharging &#183; Nodding off</text>
<text id="s5" class="a status" x="736" y="96">5% &#183; Discharging &#183; Asleep</text>
<text id="s5w" class="a status" x="736" y="96">5% &#183; Charging &#183; Waking</text>
<text id="s80c" class="a status" x="736" y="96">80% &#183; Charging &#183; Awake</text>
</g>
<g font-size="12" fill="#5b6472">
$(threshold_labels)
</g>
</g>
<rect x="620" y="125" width="230" height="64" rx="14" fill="#f7f8fa" stroke="#5b6472" stroke-width="4"/>
<rect x="852" y="144" width="9" height="26" rx="4" fill="#5b6472"/>
<line id="fill" class="a" x1="$fill_start" y1="157" x2="$(fill_x 100)" y2="157" stroke-width="48" stroke-dasharray="$fill_length 400"/>
<g stroke="#5b6472" stroke-opacity="0.45" stroke-dasharray="3 3">
$(threshold_ticks)
</g>
<path id="bolt" class="a" d="M741 135L722 161H734L729 180L749 152H737Z" fill="#fff" stroke="#2b3340" stroke-width="2.5" stroke-linejoin="round"/>
<g id="plug" class="a" fill="#3a4150">
<rect x="863" y="147" width="24" height="20" rx="4"/>
<rect x="885" y="153" width="80" height="8"/>
</g>
</svg>
EOF
}

generate() {
  banner_svg >"$1/banner.svg"
  cp "$references/pose-awake-left.png" "$1/cat.png"
}

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
generate "$scratch"

if [[ $mode == write ]]; then
  mkdir -p "$assets"
  mv "$scratch"/* "$assets"/
  exit 0
fi

stale=0
for generated in "$scratch"/*; do
  file="$assets/${generated##*/}"
  if ! cmp -s "$generated" "$file"; then
    echo "README images: $file differs from what $references and the app's values give" >&2
    stale=1
  fi
done
if ((stale)); then
  echo "Regenerate them with scripts/readme/banner.sh" >&2
fi
exit "$stale"
