#!/bin/bash
# ---------------------------------------------------------------------------
# laptop_check.sh
# Quick hardware/health check for a second-hand laptop, meant to be run
# from a Linux live-USB session (Ubuntu/Fedora/SystemRescue live desktop).
#
# Usage:
#   chmod +x laptop_check.sh
#   sudo ./laptop_check.sh
#
# It writes a plain-text report to ./laptop_report_<timestamp>.txt in the
# same folder the script is run from (put the script on the USB stick's
# writable partition, or run it from /root or /home so the report is saved
# somewhere you can read it back).
# ---------------------------------------------------------------------------

set -u
REPORT="laptop_report_$(date +%Y%m%d_%H%M%S).txt"

section() {
    echo ""
    echo "=================================================================="
    echo "  $1"
    echo "=================================================================="
}

run() {
    # run "description" "command"
    echo ""
    echo "--- $1 ---"
    eval "$2" 2>&1 || echo "(command failed or not available: $2)"
}

{
echo "Laptop Health/Spec Report"
echo "Generated: $(date)"
echo "Run as: $(whoami)"

section "1. BASIC SYSTEM INFO"
run "Hostname / kernel" "uname -a"
run "DMI / model info (may need root)" "sudo dmidecode -t system 2>/dev/null || dmidecode -t system 2>/dev/null || echo 'dmidecode not available'"
run "BIOS/UEFI version" "sudo dmidecode -t bios 2>/dev/null || echo 'dmidecode not available'"

section "2. CPU"
run "lscpu" "lscpu"

section "3. MEMORY (RAM)"
run "free -h" "free -h"
run "Installed RAM modules (dmidecode)" "sudo dmidecode -t memory 2>/dev/null | grep -E 'Size|Speed|Manufacturer|Locator' || echo 'dmidecode not available'"

section "4. STORAGE"
run "Block devices" "lsblk -o NAME,SIZE,TYPE,MODEL,ROTA"
echo ""
echo "--- SMART health per disk (needs smartmontools) ---"
if command -v smartctl >/dev/null 2>&1; then
    for disk in $(lsblk -dno NAME | grep -E '^(sd|nvme|hd)'); do
        echo ""
        echo ">> /dev/$disk"
        sudo smartctl -a /dev/$disk 2>&1 | grep -E \
          "Model|Serial|Rotation Rate|SMART overall-health|Power_On_Hours|Reallocated_Sector|Power_Cycle_Count|Wear_Leveling|Media_Wearout|Percentage Used|Temperature_Celsius|Reported_Uncorrect|Current_Pending_Sector" \
          || echo "  (no matching SMART fields returned)"
    done
else
    echo "smartctl not found. Install with: sudo apt install smartmontools  (or) sudo dnf install smartmontools"
fi

section "5. BATTERY"
if command -v upower >/dev/null 2>&1; then
    BATT=$(upower -e | grep -i battery | head -n1)
    if [ -n "$BATT" ]; then
        run "Battery details" "upower -i $BATT"
    else
        echo "No battery device found via upower (desktop, or battery not detected)."
    fi
else
    echo "upower not found. Try: cat /sys/class/power_supply/BAT0/uevent"
    run "Fallback battery info" "cat /sys/class/power_supply/BAT*/uevent 2>/dev/null"
fi

section "6. DISPLAY"
run "Connected displays / resolution" "xrandr 2>/dev/null || echo 'xrandr not available (not in a graphical session?)'"
echo ""
echo "NOTE: Dead pixels / backlight bleed / discoloration must be checked"
echo "visually. Open a full-screen solid color (white/black/red/green/blue)"
echo "in an image viewer or browser and inspect the panel closely in a dim room."

section "7. NETWORK (WiFi / Bluetooth / Ethernet)"
run "Network interfaces" "ip link show"
run "WiFi scan (nmcli)" "nmcli device wifi list 2>/dev/null || echo 'nmcli not available'"
run "Bluetooth adapters" "bluetoothctl list 2>/dev/null || echo 'bluetoothctl not available'"

section "8. USB / PORTS"
run "USB devices detected" "lsusb"
echo "NOTE: physically test each USB port with a drive, and test the"
echo "headphone jack with a wired headset if possible."

section "9. TEMPERATURE / THERMAL"
if command -v sensors >/dev/null 2>&1; then
    run "Sensor readings (idle)" "sensors"
else
    echo "lm-sensors not found. Install with: sudo apt install lm-sensors  (or) sudo dnf install lm_sensors"
    echo "Then run: sudo sensors-detect --auto && sensors"
fi

section "10. QUICK STRESS TEST (30s CPU load, watch temps)"
if command -v stress-ng >/dev/null 2>&1; then
    echo "Running 30s CPU stress test..."
    stress-ng --cpu 0 --timeout 30s --metrics-brief 2>&1
    if command -v sensors >/dev/null 2>&1; then
        run "Temps immediately after stress" "sensors"
    fi
else
    echo "stress-ng not found. Install with: sudo apt install stress-ng  (or) sudo dnf install stress-ng"
    echo "Then re-run this script, or manually run: stress-ng --cpu 0 --timeout 60s"
fi

section "11. KEYBOARD / TRACKPAD"
echo "No automated test — open a text editor (e.g. gedit / nano in a terminal)"
echo "and press every key once, including function keys, to confirm none"
echo "are stuck, unresponsive, or produce the wrong character."
echo "For the trackpad: test single click, double click, right-click (two"
echo "finger tap), and a two-finger scroll gesture."

section "12. WEBCAM / MIC (if present)"
run "Video devices" "ls /dev/video* 2>/dev/null || echo 'No /dev/video* devices found'"
run "Audio devices" "ls /dev/snd/* 2>/dev/null || echo 'No /dev/snd devices found'"
echo "Open 'cheese' (if installed) or any camera app to visually confirm the webcam works."

section "SUMMARY CHECKLIST — fill in after reviewing the output above"
cat <<'EOF'
[ ] CPU model/cores match what the seller claimed
[ ] RAM size matches, and no errors in dmidecode
[ ] SMART overall-health = PASSED, low reallocated sectors, reasonable power-on hours
[ ] Battery: current full-charge capacity is >70-80% of design capacity
[ ] Display: no dead pixels, no significant backlight bleed
[ ] WiFi + Bluetooth connect successfully
[ ] All USB ports work, headphone jack works
[ ] Temps stay reasonable under 30s stress test (no instant 90C+/throttling)
[ ] Every keyboard key registers correctly; trackpad clicks/scrolls work
[ ] Webcam/mic work if needed
[ ] Hinge is tight, chassis has no cracks, charger wattage matches spec (visual/manual check)
EOF

} | tee "$REPORT"

echo ""
echo "=================================================================="
echo "Report saved to: $(pwd)/$REPORT"
echo "Copy this file off the USB stick (or to another drive) before you"
echo "return the laptop / shut down the live session, since changes on"
echo "most live USB sessions don't persist by default."
echo "=================================================================="
