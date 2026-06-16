#!/bin/bash
# KIWI config.sh - post-bootstrap configuration for Anaconda TUI Desktop ISO
# Azure Linux 4.0 + Fedora 44 XFCE desktop + ThinkPad T470s laptop packages
set -euo pipefail
trap 'echo "### config.sh FAILED at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

#----------------------------------------------------------------------
# Architecture detection
#----------------------------------------------------------------------
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)
        GRUB_EFI_PKG="grub2-efi-x64"
        GRUB_EFI_MOD_PKG="grub2-efi-x64-modules"
        ;;
    aarch64)
        GRUB_EFI_PKG="grub2-efi-aa64"
        GRUB_EFI_MOD_PKG="grub2-efi-aa64-modules"
        ;;
    *)
        echo "ERROR: Unsupported architecture: $ARCH" >&2
        exit 1
        ;;
esac
echo "=== Architecture: $ARCH ==="

#----------------------------------------------------------------------
# Variant detection
#----------------------------------------------------------------------
case ",${kiwi_profiles:-}," in
    *,vm-iso-installer-dev,*)
        AZL_REPOS_PKG="azurelinux-repos-dev"
        ;;
    *,vm-iso-installer,*)
        AZL_REPOS_PKG="azurelinux-repos"
        ;;
    *)
        echo "ERROR: cannot determine variant from kiwi_profiles='${kiwi_profiles:-}'" >&2
        exit 1
        ;;
esac

#----------------------------------------------------------------------
# Anaconda launcher symlink
#----------------------------------------------------------------------
ln -sf /usr/local/bin/anaconda-launcher.sh /usr/local/bin/install-azl

#----------------------------------------------------------------------
# Welcome banner
#----------------------------------------------------------------------
cat > /root/.bash_profile << 'PROFILEEOF'
if grep -q 'azl\.autoinstall' /proc/cmdline 2>/dev/null; then
    MY_TTY=$(tty 2>/dev/null)
    VIRT=$(systemd-detect-virt 2>/dev/null)
    LAUNCH=false
    if [ "$VIRT" = "microsoft" ]; then
        [ "$MY_TTY" = "/dev/tty1" ] && LAUNCH=true
    else
        case "$MY_TTY" in
            /dev/ttyS0)
                LAUNCH=true
                ;;
            /dev/tty1|/dev/hvc0)
                if ! grep -q 'console=ttyS' /proc/cmdline 2>/dev/null; then
                    LAUNCH=true
                fi
                ;;
        esac
    fi
    if [ "$LAUNCH" = true ]; then
        exec /usr/local/bin/anaconda-launcher.sh
    fi
fi
echo ""
echo "Azure Linux 4.0 Desktop -- Installer"
echo "To start: install-azl"
echo ""
PROFILEEOF

cat > /root/.bashrc << 'RCEOF'
if [[ $- == *i* ]] && [ ! -f /tmp/.azl-banner-shown ]; then
    touch /tmp/.azl-banner-shown
    source /root/.bash_profile
fi
RCEOF

#----------------------------------------------------------------------
# Autologin on serial and VGA consoles
#----------------------------------------------------------------------
mkdir -p /etc/systemd/system/serial-getty@ttyS0.service.d
cat > /etc/systemd/system/serial-getty@ttyS0.service.d/autologin.conf << 'AUTOEOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I 115200 linux
AUTOEOF

mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << 'AUTOEOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I linux
AUTOEOF

#----------------------------------------------------------------------
# Generate kickstart files from templates
#----------------------------------------------------------------------
generate_packages_section() {
    echo "%packages --nocore"
    echo "bash"
    echo "coreutils"
    echo "systemd"
    echo "dnf5"
    echo "grub2"
    echo "shim"
    echo "efibootmgr"
    echo "kernel"
    echo "kernel-modules"
    echo "openssh-server"
    echo "openssh-clients"
    echo "sudo"
    echo "vim-minimal"
    echo "ca-certificates"
    echo "azurelinux-release"
    echo "$AZL_REPOS_PKG"
    echo "setup"
    echo "shadow-utils"
    echo "util-linux"
    echo "selinux-policy-targeted"
    echo "audit"
    echo "chrony"
    echo "cracklib-dicts"
    echo "glibc"
    echo "glibc-langpack-en"
    echo "cryptsetup"
    echo "firewalld"
    echo "iproute"
    echo "tar"
    echo "gzip"
    echo "curl"
    echo "NetworkManager"
    echo "NetworkManager-wifi"
    echo "NetworkManager-bluetooth"
    echo "wpa_supplicant"
    echo "bluez"
    echo "blueman"
    echo "xorg-x11-server-Xorg"
    echo "xorg-x11-drv-libinput"
    echo "mesa-dri-drivers"
    echo "mesa-libGL"
    echo "lightdm"
    echo "lightdm-gtk"
    echo "xfce4-session"
    echo "xfwm4"
    echo "xfce4-panel"
    echo "xfce4-settings"
    echo "xfce4-terminal"
    echo "xfdesktop"
    echo "xfce4-appfinder"
    echo "xfce4-power-manager"
    echo "xfce4-notifyd"
    echo "xfce4-screensaver"
    echo "xfce4-pulseaudio-plugin"
    echo "Thunar"
    echo "tumbler"
    echo "file-roller"
    echo "pipewire"
    echo "pipewire-alsa"
    echo "pipewire-pulseaudio"
    echo "wireplumber"
    echo "pavucontrol"
    echo "network-manager-applet"
    echo "xdg-desktop-portal"
    echo "xdg-desktop-portal-gtk"
    echo "gvfs"
    echo "gvfs-fuse"
    echo "microsoft-edge-stable"
    echo "code"
    echo "linux-firmware"
    echo "tlp"
    echo "tlp-rdw"
    echo "thermald"
    echo "fprintd"
    echo "libfprint"
    echo "brightnessctl"
    echo "acpid"
    echo "powertop"
    echo "cups"
    echo "%end"
}

for ks_in in /root/azl-install.ks.in /root/azl-install-encrypted.ks.in; do
    ks_out="${ks_in%.in}"
    {
        sed '/@@PACKAGES@@/,$d' "$ks_in"
        generate_packages_section
        sed '1,/@@PACKAGES@@/d' "$ks_in"
    } > "$ks_out"
    rm -f "$ks_in"
done
