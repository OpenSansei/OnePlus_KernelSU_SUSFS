#!/usr/bin/env bash
set -euo pipefail

echo "::group::Force MT76x2U built-in, minimal"

mapfile -t MT76_KCONFIGS < <(
  find "$GITHUB_WORKSPACE" \
    -type f \
    -path '*/drivers/net/wireless/mediatek/mt76/mt76x2/Kconfig' \
    2>/dev/null | sort
)

if [ "${#MT76_KCONFIGS[@]}" -eq 0 ]; then
  echo "::error::mt76x2 Kconfig not found"
  exit 1
fi

MT76_KCONFIG="${MT76_KCONFIGS[0]}"
KROOT="${MT76_KCONFIG%/drivers/net/wireless/mediatek/mt76/mt76x2/Kconfig}"

echo "KROOT=$KROOT"

# Prefer OP13r / vendor defconfig-ish files. Do NOT patch every random config.
mapfile -t CONFIG_FILES < <(
  find "$KROOT/arch/arm64/configs" -type f 2>/dev/null | \
    grep -Ei 'gki|vendor|pineapple|waffle|oneplus|op13|oplus|sm8650|kalama|defconfig' | sort -u
)

if [ "${#CONFIG_FILES[@]}" -eq 0 ]; then
  echo "::error::No candidate defconfigs found"
  find "$KROOT/arch/arm64/configs" -type f 2>/dev/null | sort | head -100
  exit 1
fi

set_y() {
  local file="$1"
  local sym="$2"
  sed -i -E "/^CONFIG_${sym}=|^# CONFIG_${sym} is not set$/d" "$file"
  printf 'CONFIG_%s=y\n' "$sym" >> "$file"
}

# Do NOT touch Qualcomm/CNSS/QCA symbols.
# Only upstream Wi-Fi core + MT76 USB path.
SYMS_Y=(
  CFG80211
  MAC80211
  WLAN
  WLAN_VENDOR_MEDIATEK
  MT76_CORE
  MT76_USB
  MT76x02_LIB
  MT76x02_USB
  MT76x2_COMMON
  MT76x2U
)

echo "Patching:"
printf '  %s\n' "${CONFIG_FILES[@]}"

for f in "${CONFIG_FILES[@]}"; do
  for sym in "${SYMS_Y[@]}"; do
    set_y "$f" "$sym"
  done
done

echo "--- patched symbols ---"
grep -RniE \
  'CONFIG_(CFG80211|MAC80211|WLAN|WLAN_VENDOR_MEDIATEK|MT76_CORE|MT76_USB|MT76x02_LIB|MT76x02_USB|MT76x2_COMMON|MT76x2U|CNSS|QCA|QCACLD|WCNSS|WLAN_VENDOR_QUALCOMM)' \
  "${CONFIG_FILES[@]}" | head -400 || true

echo "::endgroup::"
