#!/bin/bash

# Farben für hübsche Ausgabe
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Arch Linux + Hyprland + NVIDIA DPMS Diagnose ===${NC}\n"

# 1. Check Kernel Parameters
echo -e "${YELLOW}[1/4] Prüfe Kernel-Parameter (NVIDIA DRM)...${NC}"
CMDLINE=$(cat /proc/cmdline)
if [[ $CMDLINE == *"nvidia_drm.modeset=1"* ]]; then
    echo -e "${GREEN}✔ nvidia_drm.modeset=1 ist gesetzt.${NC}"
else
    echo -e "${RED}✖ nvidia_drm.modeset=1 FEHLT in den Kernel-Parametern!${NC} (Wichtig für Wayland)"
fi

if [[ $CMDLINE == *"nvidia_drm.fbdev=1"* ]]; then
    echo -e "${GREEN}✔ nvidia_drm.fbdev=1 ist gesetzt.${NC}"
else
    echo -e "${RED}✖ nvidia_drm.fbdev=1 FEHLT in den Kernel-Parametern!${NC} (Wichtig ab NVIDIA 545+)"
fi
echo ""

# 2. Check Modprobe Options (Preserve Video Memory)
echo -e "${YELLOW}[2/4] Prüfe NVIDIA Video Memory Preservation...${NC}"
MODPROBE_CHECK=$(grep -r "NVreg_PreserveVideoMemoryAllocations=1" /etc/modprobe.d/ /usr/lib/modprobe.d/ 2>/dev/null)
if [ -n "$MODPROBE_CHECK" ]; then
    echo -e "${GREEN}✔ NVreg_PreserveVideoMemoryAllocations=1 ist konfiguriert.${NC}"
else
    echo -e "${RED}✖ NVreg_PreserveVideoMemoryAllocations=1 FEHLT in /etc/modprobe.d/nvidia.conf!${NC}"
    echo -e "  Ohne dies wacht der Monitor nach dem Standby oft nicht auf, weil der VRAM geleert wurde."
fi
echo ""

# 3. Check Systemd Services
echo -e "${YELLOW}[3/4] Prüfe NVIDIA Systemd-Services für Suspend/Resume...${NC}"
SERVICES=("nvidia-suspend.service" "nvidia-hibernate.service" "nvidia-resume.service")
for service in "${SERVICES[@]}"; do
    if systemctl is-enabled --quiet $service 2>/dev/null; then
        echo -e "${GREEN}✔ $service ist aktiviert.${NC}"
    else
        echo -e "${RED}✖ $service ist DEAKTIVIERT!${NC} (Führe aus: sudo systemctl enable $service)"
    fi
done
echo ""

# 4. Check Hypridle / Swayidle config
echo -e "${YELLOW}[4/4] Prüfe Idle-Daemon Konfigurationen...${NC}"
if [ -f "$HOME/.config/hypr/hypridle.conf" ]; then
    echo -e "${GREEN}✔ hypridle.conf gefunden.${NC} Stelle sicher, dass 'hyprctl dispatch dpms on' im on-resume block steht."
elif pgrep -x "swayidle" > /dev/null; then
    echo -e "${YELLOW}! swayidle läuft.${NC} Ersetze es besser durch hypridle, das funktioniert mit NVIDIA stabiler."
else
    echo -e "${YELLOW}? Weder hypridle konfiguriert noch swayidle am Laufen.${NC} Wie legst du den Monitor schlafen?"
fi
echo ""

echo -e "${YELLOW}=== Diagnose abgeschlossen ===${NC}"
echo -e "Bitte korrigiere alle rot markierten (✖) Punkte."
