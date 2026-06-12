#!/usr/bin/env bash
set -euo pipefail

echo "::group::Force MT76 / MT7612U / MT76x2U built-in"

echo "GITHUB_WORKSPACE=$GITHUB_WORKSPACE"
pwd
ls -la "$GITHUB_WORKSPACE" || true

# Find the real kernel root by locating mt76x2 Kconfig.
mapfile -t MT76_KCONFIGS < <(
  find "$GITHUB_WORKSPACE" \
    -type f \
    -path '*/drivers/net/wireless/mediatek/mt76/mt76x2/Kconfig' \
    2>/dev/null | sort
)

if [ "${#MT76_KCONFIGS[@]}" -eq 0 ]; then
  echo "::error::mt76x2 Kconfig not found. This kernel source tree does not contain mt76x2U source."
  echo "Dumping nearby wireless dirs because apparently we enjoy pain:"
  find "$GITHUB_WORKSPACE" -type d -path '*/drivers/net/wireless*' 2>/dev/null | head -80 || true
  exit 1
fi

MT76_KCONFIG="${MT76_KCONFIGS[0]}"
KROOT="${MT76_KCONFIG%/drivers/net/wireless/mediatek/mt76/mt76x2/Kconfig}"

echo "MT76_KCONFIG=$MT76_KCONFIG"
echo "KROOT=$KROOT"

grep -q 'config MT76x2U' "$MT76_KCONFIG" || {
  echo "::error::CONFIG_MT76x2U not present in $MT76_KCONFIG"
  exit 1
}

# Find defconfig-ish files. Patch broad enough to catch Android/OnePlus build nonsense.
mapfile -t CONFIG_FILES < <(
  {
    find "$KROOT/arch/arm64/configs" -type f 2>/dev/null || true
    find "$GITHUB_WORKSPACE" -type f \( \
      -name '*defconfig' -o \
      -name 'gki_defconfig' -o \
      -name 'vendor_dlkm.modules.blocklist' \
    \) 2>/dev/null || true
  } | sort -u
)

if [ "${#CONFIG_FILES[@]}" -eq 0 ]; then
  echo "::error::No defconfig files found to patch."
  exit 1
fi

set_config_y() {
  local file="$1"
  local sym="$2"

  # Remove existing setting in any form.
  sed -i -E "/^CONFIG_${sym}=|^# CONFIG_${sym} is not set$/d" "$file"

  # Append built-in.
  printf 'CONFIG_%s=y\n' "$sym" >> "$file"
}

# Keep this list boring. Boring boots. Fancy bootloops.
SYMS_Y=(
  WIRELESS
  CFG80211
  MAC80211
  RFKILL
  USB
  WLAN
  WLAN_VENDOR_MEDIATEK
  MT76_CORE
  MT76_USB
  MT76x02_LIB
  MT76x02_USB
  MT76x2_COMMON
  MT76x2U
)

echo "Patching config files:"
for f in "${CONFIG_FILES[@]}"; do
  # Skip binary/random garbage if find got creative.
  if ! file "$f" | grep -qiE 'text|empty'; then
    continue
  fi

  echo "  $f"

  for sym in "${SYMS_Y[@]}"; do
    set_config_y "$f" "$sym"
  done
done

echo
echo "Relevant config result:"
grep -RniE \
  'CONFIG_(WIRELESS|CFG80211|MAC80211|RFKILL|USB|WLAN|WLAN_VENDOR_MEDIATEK|MT76_CORE|MT76_USB|MT76x02_LIB|MT76x02_USB|MT76x2_COMMON|MT76x2U)=y' \
  "${CONFIG_FILES[@]}" | head -300 || true

echo "::endgroup::"
