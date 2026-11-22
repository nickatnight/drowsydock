#!/usr/bin/env bash
#   scripts/readme/banner.sh          write docs/readme/banner.svg and docs/readme/cat.png
#   scripts/readme/banner.sh --check  exit 1 if either is out of date
#
# banner.svg uses CSS animation only and embeds the PNGs, so GitHub can show it through <img>.
set -euo pipefail
cd "$(dirname "$0")/../.."
export LC_ALL=C

references="${README_REFERENCES:-Tests/DrowsyDockTests/Snapshots}"
sources="${README_SOURCES:-.}"
assets="${README_ASSETS:-docs/readme}"
mode="${1:-write}"
case "$mode" in
  write | --check) ;;
  *)
    echo "usage: scripts/readme/banner.sh [--check]" >&2
    exit 2
    ;;
esac

png_signature=89504e470d0a1a0a
for pose in awake drowsy yawning noddingOff asleep; do
  reference="$references/pose-$pose-left.png"
  if [[ -L $reference || ! -f $reference || ! -r $reference ]] ||
    [[ "$(head -c 8 -- "$reference" | od -An -tx1 | tr -d ' \n')" != "$png_signature" ]]; then
    echo "banner.sh: $reference must be a regular PNG file" >&2
    exit 1
  fi
done

loop=16

calc_expression='^[0-9. +*/()-]+$'
calc() {
  if [[ ! $1 =~ $calc_expression ]]; then
    echo "banner.sh: calc got \"$1\", which isn't arithmetic" >&2
    exit 1
  fi
  awk "BEGIN { printf \"%.6g\", $1 }"
}

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
  duration="$(swift_value "$1" "$2 = Duration\.([a-z]+\([0-9]+\))")" || exit 1
  case "$duration" in
    seconds*) calc "${duration//[^0-9]/}" ;;
    milliseconds*) calc "${duration//[^0-9]/} / 1000" ;;
    *)
      echo "banner.sh: $2 in $1 is neither seconds nor milliseconds" >&2
      exit 1
      ;;
  esac
}

thresholds_swift="$sources/Sources/DrowsyDockCore/Thresholds.swift"
asleep_below="$(swift_value "$thresholds_swift" 'asleepBelow: ([0-9]+)')"
nodding_off_below="$(swift_value "$thresholds_swift" 'noddingOffBelow: ([0-9]+)')"
yawning_below="$(swift_value "$thresholds_swift" 'yawningBelow: ([0-9]+)')"
drowsy_below="$(swift_value "$thresholds_swift" 'validatedDrowsyBelow: ([0-9]+)')"
mascot_pose_swift="$sources/Sources/DrowsyDockCore/MascotPose.swift"
veil_opacity="$(swift_value "$mascot_pose_swift" 'veilOpacity: ([0-9.]+)')"
overlay_window_swift="$sources/Sources/DockOverlayKit/OverlayWindow.swift"
veil_fade_seconds="$(swift_value "$overlay_window_swift" 'fadeDuration: TimeInterval = ([0-9.]+)')"

crowd_wave_swift="$sources/Sources/DrowsyDockCore/CrowdWave.swift"
icon_seconds="$(swift_seconds "$crowd_wave_swift" iconEffectDuration)"
dim_seconds="$(swift_seconds "$crowd_wave_swift" dimDuration)"
stagger_seconds="$(swift_seconds "$crowd_wave_swift" preferredStagger)"

crowd_node_swift="$sources/Sources/DrowsyDock/CrowdEffectNode.swift"
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

units_per_point=1.6

awake_level=80
drowsy_level=40
yawning_level=25
nodding_level=15
asleep_level=5

require_band() {
  if (($2 < $3 || $2 >= $4)); then
    echo "banner.sh: the banner shows $1 at $2%, but Thresholds.swift makes that band $3 to" \
      "$(($4 - 1))%. Change the levels in banner.sh, then check the README's table, tagline and" \
      "alt text." >&2
    exit 1
  fi
}
require_band awake "$awake_level" "$drowsy_below" 101
require_band drowsy "$drowsy_level" "$yawning_below" "$drowsy_below"
require_band yawning "$yawning_level" "$nodding_off_below" "$yawning_below"
require_band "nodding off" "$nodding_level" "$asleep_below" "$nodding_off_below"
require_band asleep "$asleep_level" 0 "$asleep_below"

unplugged_at=0.5
drowsy_at=3
yawning_at=5.5
nodding_at=8
asleep_at=10.5
plugged_at=13.25
awake_at=13.5
waking_status_end=15.25
refill_start=15
refill_end=15.75
charged_status_at=15.5
drain_seconds=0.5
pose_fade_seconds=0.25
plug_slide_seconds=0.5
step_seconds=0.01

keyframes() {
  local name="$1" property="$2"
  shift 2
  printf '%s\n' "$@" | awk -v name="$name" -v property="$property" -v loop="$loop" '
    BEGIN { printf "@keyframes %s {", name }
    {
      split_at = index($0, ":")
      printf " %.6g%% { %s: %s }", substr($0, 1, split_at - 1) * 100 / loop, property,
        substr($0, split_at + 1)
    }
    END { printf " }\n" }'
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

pose_shown() {
  keyframes "$1" opacity 0:0 "$(calc "$2 - $pose_fade_seconds"):0" "$2:1" "$3:1" \
    "$(calc "$3 + $step_seconds"):0" "$loop:0"
}

# add_drain AT FROM TO: appends to the caller's level_frames the two keyframes of a drain from
# FROM% to TO% that ends at AT seconds.
add_drain() {
  level_frames+=(
    "$(calc "$1 - $drain_seconds"):$(fill_dashoffset "$2")"
    "$1:$(fill_dashoffset "$3")"
  )
}

banner_css() {
  local level_frames=("0:$(fill_dashoffset "$awake_level")")
  add_drain "$drowsy_at" "$awake_level" "$drowsy_level"
  add_drain "$yawning_at" "$drowsy_level" "$yawning_level"
  add_drain "$nodding_at" "$yawning_level" "$nodding_level"
  add_drain "$asleep_at" "$nodding_level" "$asleep_level"
  level_frames+=(
    "$refill_start:$(fill_dashoffset "$asleep_level")"
    "$refill_end:$(fill_dashoffset "$awake_level")"
    "$loop:$(fill_dashoffset "$awake_level")"
  )
  keyframes level stroke-dashoffset "${level_frames[@]}"
  keyframes charge stroke 0:#34c759 "$unplugged_at:#34c759" \
    "$(calc "$unplugged_at + $step_seconds"):#6b7383" "$plugged_at:#6b7383" \
    "$(calc "$plugged_at + $step_seconds"):#34c759" "$loop:#34c759"
  keyframes plug transform 0:none "$unplugged_at:translateX(60px)" \
    "$(calc "$plugged_at - $plug_slide_seconds"):translateX(60px)" "$plugged_at:none" "$loop:none"
  shown_across_loop_end bolt "$plugged_at" "$unplugged_at"
  keyframes base opacity 0:1 "$drowsy_at:1" "$(calc "$drowsy_at + $step_seconds"):0" "$loop:0"
  pose_shown drowsy "$drowsy_at" "$yawning_at"
  pose_shown yawning "$yawning_at" "$nodding_at"
  pose_shown nodding "$nodding_at" "$asleep_at"
  pose_shown asleep "$asleep_at" "$awake_at"
  keyframes waking opacity 0:0 "$(calc "$awake_at - $pose_fade_seconds"):0" "$awake_at:1" "$loop:1"
  keyframes stretch transform 0:none "$awake_at:none" \
    "$(calc "$awake_at + 0.25"):scale(0.97, 1.06)" "$(calc "$awake_at + 0.6"):none" "$loop:none"
  keyframes sparkle transform "0:scale(0)" "$(calc "$awake_at + 0.1"):scale(0)" \
    "$(calc "$awake_at + 0.4"):scale(1.3)" "$(calc "$awake_at + 1"):scale(1)" \
    "$(calc "$awake_at + 1.4"):scale(0)" "$loop:scale(0)"
  keyframes veil opacity 0:0 "$(calc "$asleep_at - $veil_fade_seconds"):0" \
    "$asleep_at:$veil_opacity" "$plugged_at:$veil_opacity" \
    "$(calc "$plugged_at + $veil_fade_seconds"):0" "$loop:0"
  keyframes dim opacity 0:0 "$asleep_at:0" \
    "$(calc "$asleep_at + $dim_seconds * $dim_fade_in"):$dim_opacity" \
    "$(calc "$asleep_at + $dim_seconds * ($dim_fade_in + $dim_hold)"):$dim_opacity" \
    "$(calc "$asleep_at + $dim_seconds * ($dim_fade_in + $dim_hold + $dim_fade_out)"):0" "$loop:0"
  keyframes puff opacity 0:0 "$asleep_at:0" \
    "$(calc "$asleep_at + $icon_seconds * $puff_fade_in"):1" \
    "$(calc "$asleep_at + $icon_seconds * ($puff_fade_in + $puff_hold)"):1" \
    "$(calc "$asleep_at + $icon_seconds * ($puff_fade_in + $puff_hold + $puff_fade_out)"):0" \
    "$loop:0"
  local drift_x drift_y drifted
  drift_x="$(calc "$drift_dx * $units_per_point")"
  drift_y="$(calc "$drift_dy * $units_per_point")"
  drifted="translate(${drift_x}px, -${drift_y}px) scale($z_end_scale)"
  keyframes drift transform "0:scale($z_start_scale)" "$asleep_at:scale($z_start_scale)" \
    "$(calc "$asleep_at + $icon_seconds"):$drifted" "$loop:$drifted"
  shown s80d "$unplugged_at" "$drowsy_at"
  shown s40 "$drowsy_at" "$yawning_at"
  shown s25 "$yawning_at" "$nodding_at"
  shown s15 "$nodding_at" "$asleep_at"
  shown s5 "$asleep_at" "$plugged_at"
  shown s5w "$plugged_at" "$waking_status_end"
  shown_across_loop_end s80c "$charged_status_at" "$unplugged_at"
}

# Runs a command with set -e, which bash turns off inside $(...).
with_errexit() {
  set -e
  "$@"
}

stagger_rules() {
  local i
  for i in 1 2 3 4; do
    printf '.i%s { animation-delay: %ss }\n' "$i" "$(calc "$i * $stagger_seconds")"
  done
}

puffs() {
  local i x delay
  for i in 0 1 2 3 4; do
    x="$(calc "97.5 + 101 * $i")"
    delay=""
    if ((i > 0)); then delay=" i$i"; fi
    printf '<g class="a puff%s" transform="translate(%s 189.4)"><g class="a drift%s">' "$delay" "$x" "$delay"
    printf '<use href="#z" stroke="#2b3b66" stroke-width="6.05"/><use href="#z" stroke="#d6e6ff" stroke-width="3.17"/></g></g>\n'
  done
}

# Everything the template needs is computed first, so a failure stops the script under set -e.
banner_svg() {
  local asleep_fill stagger css awake_png drowsy_png yawning_png nodding_png asleep_png
  local puff_groups labels fill_end ticks
  asleep_fill="$(fill_dashoffset "$asleep_level")"
  stagger="$(with_errexit stagger_rules)"
  css="$(with_errexit banner_css)"
  awake_png="$(png pose-awake-left.png)"
  drowsy_png="$(png pose-drowsy-left.png)"
  yawning_png="$(png pose-yawning-left.png)"
  nodding_png="$(png pose-noddingOff-left.png)"
  asleep_png="$(png pose-asleep-left.png)"
  puff_groups="$(with_errexit puffs)"
  labels="$(with_errexit threshold_labels)"
  fill_end="$(fill_x 100)"
  ticks="$(with_errexit threshold_ticks)"
  cat <<EOF
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 900 300" width="900" height="300" role="img">
<title>DrowsyDock: the cat on the Dock gets drowsier as the battery drains, and wakes when a charger plugs in</title>
<!-- Generated by scripts/readme/banner.sh from the snapshot references and the app's Swift sources. Do not edit; rerun the script. -->
<style>
.a { animation-duration: ${loop}s; animation-timing-function: linear; animation-iteration-count: infinite }
.pose { opacity: 0 }
#asleep, #s5 { opacity: 1 }
#fill { stroke: #6b7383; stroke-dashoffset: $asleep_fill; animation-name: level, charge }
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
$stagger
.s1 { animation-delay: 0.2s }
.s2 { animation-delay: 0.4s }
$css
@media (prefers-reduced-motion: reduce) { * { animation: none !important } }
</style>
<defs>
<image id="p-awake" x="449.6" y="22" width="102.4" height="128" href="$awake_png"/>
<image id="p-drowsy" x="449.6" y="22" width="102.4" height="128" href="$drowsy_png"/>
<image id="p-yawning" x="449.6" y="22" width="102.4" height="128" href="$yawning_png"/>
<image id="p-noddingOff" x="449.6" y="22" width="102.4" height="128" href="$nodding_png"/>
<image id="p-asleep" x="449.6" y="22" width="102.4" height="128" href="$asleep_png"/>
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
$puff_groups
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
<text id="s80d" class="a status" x="736" y="96">$awake_level% &#183; Discharging &#183; Awake</text>
<text id="s40" class="a status" x="736" y="96">$drowsy_level% &#183; Discharging &#183; Drowsy</text>
<text id="s25" class="a status" x="736" y="96">$yawning_level% &#183; Discharging &#183; Yawning</text>
<text id="s15" class="a status" x="736" y="96">$nodding_level% &#183; Discharging &#183; Nodding off</text>
<text id="s5" class="a status" x="736" y="96">$asleep_level% &#183; Discharging &#183; Asleep</text>
<text id="s5w" class="a status" x="736" y="96">$asleep_level% &#183; Charging &#183; Waking</text>
<text id="s80c" class="a status" x="736" y="96">$awake_level% &#183; Charging &#183; Awake</text>
</g>
<g font-size="12" fill="#5b6472">
$labels
</g>
</g>
<rect x="620" y="125" width="230" height="64" rx="14" fill="#f7f8fa" stroke="#5b6472" stroke-width="4"/>
<rect x="852" y="144" width="9" height="26" rx="4" fill="#5b6472"/>
<line id="fill" class="a" x1="$fill_start" y1="157" x2="$fill_end" y2="157" stroke-width="48" stroke-dasharray="$fill_length 400"/>
<g stroke="#5b6472" stroke-opacity="0.45" stroke-dasharray="3 3">
$ticks
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
  echo "Regenerate them with scripts/readme/banner.sh. If Thresholds.swift changed, also check" \
    "the README's table, tagline and alt text." >&2
fi
exit "$stale"
