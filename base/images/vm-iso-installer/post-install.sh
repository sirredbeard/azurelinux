#!/bin/bash
# post-install.sh — Target system configuration (%post --nochroot, runs in chroot)
# Azure Linux 4.0 Desktop with Bluecurve/XFCE4 — ThinkPad T470s optimised
set -x

# --- Fedora 44 GPG key (needed for runtime dnf updates from fedora44.repo) ---
rpm --import https://src.fedoraproject.org/rpms/fedora-repos/raw/rawhide/f/RPM-GPG-KEY-fedora-44-primary
rpm --import https://packages.microsoft.com/keys/microsoft.asc

# --- GRUB defaults (laptop: graphical, no serial console) ---
cat > /etc/default/grub << 'GRUBDEF'
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="Azure Linux Desktop"
GRUB_DEFAULT=0
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="gfxterm"
GRUB_GFXMODE=auto
GRUB_CMDLINE_LINUX="quiet splash"
GRUB_DISABLE_RECOVERY=false
GRUBDEF

# --- NetworkManager: manage all interfaces (replaces systemd-networkd) ---
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/00-managed.conf << 'NMCONF'
[main]
dns=systemd-resolved
NMCONF

# --- Enable desktop services ---
systemctl enable lightdm.service
systemctl enable NetworkManager.service
systemctl enable bluetooth.service
systemctl enable tlp.service
systemctl enable thermald.service
systemctl enable fprintd.service
systemctl enable acpid.service
systemctl enable cups.service
systemctl disable systemd-networkd.service || true
systemctl disable systemd-resolved.service || true

# --- LightDM: default to XFCE session ---
install -Dm644 /dev/stdin /etc/lightdm/lightdm.conf << 'LIGHTDMCONF'
[LightDM]
logind-check-graphical=true

[Seat:*]
user-session=xfce
greeter-session=lightdm-gtk-greeter
autologin-guest=false
xserver-allow-tcp=false
LIGHTDMCONF

install -Dm644 /dev/stdin /etc/lightdm/lightdm-gtk-greeter.conf << 'GREETERCONF'
[greeter]
theme-name = Bluecurve
icon-theme-name = Bluecurve
background = /usr/share/backgrounds/bluecurve/lightrays.png
font-name = Luxi Sans 10
xft-antialias = true
xft-hintstyle = hintmedium
show-clock = true
clock-format = %a, %b %-d  %-I:%M %p
GREETERCONF

# --- TLP: ThinkPad T470s power management ---
cat > /etc/tlp.conf << 'TLPCONF'
TLP_ENABLE=1
TLP_DEFAULT_MODE=AC
CPU_SCALING_GOVERNOR_ON_AC=powersave
CPU_SCALING_GOVERNOR_ON_BAT=powersave
CPU_ENERGY_PERF_POLICY_ON_AC=balance_performance
CPU_ENERGY_PERF_POLICY_ON_BAT=power
PLATFORM_PROFILE_ON_AC=balanced
PLATFORM_PROFILE_ON_BAT=low-power
NMI_WATCHDOG=0
WIFI_PWR_ON_AC=off
WIFI_PWR_ON_BAT=on
SOUND_POWER_SAVE_ON_AC=0
SOUND_POWER_SAVE_ON_BAT=1
RUNTIME_PM_ON_AC=auto
RUNTIME_PM_ON_BAT=auto
USB_AUTOSUSPEND=1
TLPCONF

# --- Bluecurve theme: extract from the tarball bundled in the ISO ---
# The tarball is placed at /usr/share/azl-installer/bluecurve.tar.gz by KIWI.
if [ -f /usr/share/azl-installer/bluecurve.tar.gz ]; then
    tar -xzf /usr/share/azl-installer/bluecurve.tar.gz -C /usr/share/
fi

# Set icon theme inheritance so Bluecurve falls back to elementary-xfce + Adwaita
for theme in /usr/share/icons/Bluecurve*/index.theme; do
    sed -i 's/^Inherits=.*/Inherits=elementary-xfce,Adwaita,gnome,hicolor/' "$theme" 2>/dev/null || true
done

# --- System-wide XFCE4 defaults ---
mkdir -p /etc/xdg/xfce4/xfconf/xfce-perchannel-xml
cp /usr/share/azl-installer/xfce-defaults/*.xml \
   /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/ 2>/dev/null || true

# --- PowerShell: install from official tarball (no aarch64 RPM) ---
case "$(uname -m)" in
    aarch64) ps_arch=arm64 ;;
    x86_64)  ps_arch=x64 ;;
    *) echo "Skipping PowerShell install: unsupported arch $(uname -m)" ;;
esac
if [ -n "${ps_arch:-}" ]; then
    curl -fsSL -o /tmp/powershell.tar.gz \
        "https://github.com/PowerShell/PowerShell/releases/download/v7.6.2/powershell-7.6.2-linux-${ps_arch}.tar.gz"
    mkdir -p /opt/microsoft/powershell/7
    tar -xzf /tmp/powershell.tar.gz -C /opt/microsoft/powershell/7
    chmod 755 /opt/microsoft/powershell/7/pwsh
    ln -sf /opt/microsoft/powershell/7/pwsh /usr/bin/pwsh
    rm -f /tmp/powershell.tar.gz
fi

# --- PowerShell terminal desktop entry (panel launcher) ---
cp /usr/share/azl-installer/powershell-icon.png /usr/share/pixmaps/powershell.png 2>/dev/null || true
printf '[Desktop Entry]\nVersion=1.0\nType=Application\nName=PowerShell\nComment=PowerShell in xfce4-terminal\nExec=xfce4-terminal\nIcon=/usr/share/pixmaps/powershell.png\nCategories=System;TerminalEmulator;\n' \
    > /usr/share/applications/powershell-terminal.desktop

# --- XFCE4 terminal: default to PowerShell ---
mkdir -p /etc/xdg/xfce4/terminal
printf '[Configuration]\nRunCustomCommand=TRUE\nCustomCommand=/usr/bin/pwsh\nColorForeground=#000000\nColorBackground=#ffffff\nColorCursor=#000000\n' \
    > /etc/xdg/xfce4/terminal/terminalrc

# --- Browser helpers: Microsoft Edge as default ---
printf '[Desktop Entry]\nVersion=1.0\nType=X-XFCE-Helper\nIcon=microsoft-edge\nName=Microsoft Edge\nX-XFCE-Binaries=microsoft-edge-stable\nX-XFCE-Category=WebBrowser\nX-XFCE-CommandsWithParameter=microsoft-edge-stable "%%s"\nX-XFCE-Commands=microsoft-edge-stable\n' \
    > /usr/share/xfce4/helpers/microsoft-edge.desktop
mkdir -p /etc/xdg/xfce4
printf 'WebBrowser=microsoft-edge\nTerminalEmulator=xfce4-terminal\nFileManager=Thunar\n' \
    > /etc/xdg/xfce4/helpers.rc

# Remove noisy mail reader desktop entry
rm -f /usr/share/applications/xfce4-mail-reader.desktop || true


# --- Timezone default ---
ln -sfn /usr/share/zoneinfo/America/New_York /etc/localtime

# --- Network: configure systemd-resolved stub as DNS ---
mkdir -p /etc/systemd/resolved.conf.d
cat > /etc/systemd/resolved.conf.d/dns.conf << 'DNSCONF'
[Resolve]
DNS=1.1.1.1 8.8.8.8
FallbackDNS=1.0.0.1 8.8.4.4
DNSCONF
ln -sfn /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf || true

# --- SSH hardening ---
rm -f /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub
: > /etc/machine-id
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config 2>/dev/null || true

# --- SELinux relabel on first boot ---
touch /.autorelabel

# --- Encrypted disk: regenerate initramfs with LUKS support ---
if [ -f /etc/crypttab ] && [ -s /etc/crypttab ]; then
    dracut --regenerate-all --force --add crypt
fi