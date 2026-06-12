#!/usr/bin/env bash
# modules/90-nvidia/module.sh — NVIDIA driver setup (opt-in only)
#
# NOT part of the default install. Activate with:
#   archinit config NVIDIA_SETUP true
#   archinit install nvidia
# Or select interactively via: archinit tui
#
# Auto-detects GPU branch:
#   Kepler (GTX 600-700)          → nvidia-470xx-dkms (AUR)
#   Maxwell / Pascal / Turing / Ampere / Ada → nvidia-dkms (official)
#
# NOTE: nvidia-470xx is incompatible with Hyprland v0.47+ (Aquamarine backend).

# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_CORE:-} ]] || source "${ARCHINIT_HOME}/lib/core.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_LOG:-} ]] || source "${ARCHINIT_HOME}/lib/log.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_PKG:-} ]] || source "${ARCHINIT_HOME}/lib/pkg.sh"
# shellcheck source=/dev/null
[[ -n ${_ARCHINIT_CONFIG:-} ]] || source "${ARCHINIT_HOME}/lib/config.sh"

module_name()     { echo "nvidia"; }
module_class()    { echo "gpu"; }
module_describe() { echo "NVIDIA drivers for Hyprland/Wayland — opt-in via NVIDIA_SETUP=true"; }
module_requires() { echo "base"; }

_MODERN_PKGS=(nvidia-dkms nvidia-utils nvidia-settings egl-wayland libva libva-nvidia-driver)
_LEGACY_PKGS=(nvidia-470xx-dkms nvidia-470xx-utils nvidia-470xx-settings)

# Kepler GK104/GK106/GK107/GK110 PCI IDs — require nvidia-470xx (AUR)
_LEGACY_PCI_IDS=(
  10de:1004 10de:1005 10de:100a 10de:100c 10de:103a 10de:103c
  10de:1021 10de:1022 10de:1023 10de:1024 10de:1026 10de:1028 10de:102d
  10de:1180 10de:1183 10de:1184 10de:1185 10de:1187 10de:1188 10de:1189
  10de:1194 10de:1198 10de:1199 10de:119a 10de:119d 10de:119f
  10de:11a0 10de:11a1 10de:11a7
  10de:0fc0 10de:0fc1 10de:0fc2 10de:0fc6 10de:0fc8 10de:0fc9
  10de:0fd1 10de:0fd2 10de:0fd3 10de:0fd4 10de:0fd5 10de:0fd8 10de:0fd9
  10de:0fdf 10de:0fe0 10de:0fe1 10de:0fe2 10de:0fe3 10de:0fe4 10de:0fe9
  10de:0fea 10de:0fec 10de:0fed 10de:0fee 10de:0fef
  10de:1040 10de:1042 10de:1048 10de:1049 10de:104a 10de:104b 10de:104c
  10de:1050 10de:1051 10de:1052 10de:1054 10de:1055 10de:1056 10de:1057
  10de:1058 10de:1059 10de:105a 10de:105b
  10de:107c 10de:107d
)

# ---------------------------------------------------------------------------

module_check() {
  local nvidia_setup
  nvidia_setup="$(config_get NVIDIA_SETUP)"
  if [[ ${nvidia_setup:-false} != "true" ]]; then
    log_debug "nvidia: NVIDIA_SETUP != true — skipping (opt-in only)"
    return 0
  fi
  # Satisfied when a driver package is installed
  pkg_is_installed nvidia-dkms || pkg_is_installed nvidia-470xx-dkms
}

module_install() {
  assert_arch
  require_cmd lspci "pciutils is required for GPU detection"

  # --- Detect NVIDIA GPUs ---
  local -a detected_ids=()
  local line id
  while IFS= read -r line; do
    id="$(echo "$line" | grep -o '10de:[0-9a-fA-F]\{4\}' | tr '[:upper:]' '[:lower:]')"
    [[ -n $id ]] && detected_ids+=("$id")
  done < <(lspci -nn 2>/dev/null | grep -i nvidia)

  if [[ ${#detected_ids[@]} -eq 0 ]]; then
    log_warn "nvidia: no NVIDIA GPU detected — skipping"
    return 0
  fi

  log_info "nvidia: detected PCI IDs: ${detected_ids[*]}"

  # --- Choose driver branch ---
  local branch="modern"
  local -a driver_pkgs=("${_MODERN_PKGS[@]}")
  local did lid
  for did in "${detected_ids[@]}"; do
    for lid in "${_LEGACY_PCI_IDS[@]}"; do
      if [[ $did == "$lid" ]]; then
        branch="legacy470"
        driver_pkgs=("${_LEGACY_PKGS[@]}")
        break 2
      fi
    done
  done

  if [[ $branch == "legacy470" ]]; then
    log_warn "nvidia: Kepler GPU detected → nvidia-470xx-dkms (AUR)"
    log_warn "nvidia: NOTE: nvidia-470xx is incompatible with Hyprland v0.47+ (Aquamarine backend)"
    require_cmd yay "yay required for legacy470 AUR packages (run: archinit install aur-helper)"
  fi

  log_info "nvidia: branch=${branch}, packages: ${driver_pkgs[*]}"

  # --- Install kernel headers + dkms ---
  local -a headers=()
  local kernel
  while IFS= read -r kernel; do
    local hdr="${kernel}-headers"
    pkg_is_installed "$hdr" || headers+=("$hdr")
  done < <(pacman -Qq 2>/dev/null | grep '^linux' | grep -v -E '\-(headers|docs|api)$' || true)
  if [[ ${#headers[@]} -gt 0 ]]; then
    pkg_install_official "${headers[@]}" dkms base-devel
  else
    pkg_install_official dkms base-devel
  fi

  # --- Install driver packages ---
  if [[ $branch == "legacy470" ]]; then
    run yay -S --needed --noconfirm "${driver_pkgs[@]}"
  else
    pkg_install_official "${driver_pkgs[@]}"
  fi

  # --- modprobe: options + blacklist nouveau ---
  as_root tee /etc/modprobe.d/nvidia.conf > /dev/null << 'MODCONF'
options nvidia NVreg_PreserveVideoMemoryAllocations=1
MODCONF
  as_root tee /etc/modprobe.d/blacklist-nouveau.conf > /dev/null << 'MODCONF'
blacklist nouveau
options nouveau modeset=0
MODCONF
  log_ok "nvidia: modprobe configured"

  # --- mkinitcpio: add NVIDIA modules ---
  local conf=/etc/mkinitcpio.conf
  if ! grep -q 'nvidia_drm' "$conf" 2>/dev/null; then
    as_root sed -i 's/^MODULES=(\(.*\))/MODULES=(\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' "$conf"
    as_root mkinitcpio -P
    log_ok "nvidia: initramfs rebuilt"
  else
    log_info "nvidia: NVIDIA modules already in mkinitcpio.conf"
  fi

  # --- systemd-boot: kernel parameters ---
  local loader_entries=/boot/loader/entries
  if [[ -d $loader_entries ]]; then
    local entry
    for entry in "${loader_entries}"/*.conf; do
      [[ -f $entry ]] || continue
      if ! grep -q 'nvidia-drm.modeset' "$entry"; then
        as_root sed -i 's/^\(options .*\)/\1 nvidia-drm.modeset=1/' "$entry"
        log_ok "nvidia: added nvidia-drm.modeset=1 to $(basename "$entry")"
      fi
    done
  fi

  # --- Pacman hook: auto-rebuild initramfs on driver/kernel update ---
  local hook_dir=/etc/pacman.d/hooks
  local hook_file="${hook_dir}/nvidia.hook"
  if [[ ! -f $hook_file ]]; then
    as_root mkdir -p "$hook_dir"
    local hook_target="nvidia-dkms"
    [[ $branch == "legacy470" ]] && hook_target="nvidia-470xx-dkms"
    as_root tee "$hook_file" > /dev/null << HOOKEOF
[Trigger]
Operation=Install
Operation=Upgrade
Operation=Remove
Type=Package
Target=${hook_target}
Target=linux

[Action]
Description=Rebuilding initramfs after NVIDIA driver update...
Depends=mkinitcpio
When=PostTransaction
Exec=/usr/bin/mkinitcpio -P
HOOKEOF
    log_ok "nvidia: pacman hook installed at ${hook_file}"
  fi

  log_ok "nvidia: setup complete — reboot required"
  log_warn "nvidia: after reboot verify with: nvidia-smi && dkms status"
}
