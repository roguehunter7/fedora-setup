#!/usr/bin/env bash
# ==============================================================================
# Fedora Sway Spin - Post-Install Setup (F44+)
# ==============================================================================
# Target   : Fresh Fedora 44+ Sway spin install (NOT Fedora Workstation)
# Hardware : AMD Ryzen/Picasso laptop (amdgpu, Vega 8, VCN), any WiFi
# Audience : tiling-WM beginner coming from GNOME
#
# Optional flags (set env vars before running, e.g. `SCX=1 sudo ./setup.sh`):
#   SCX=1          Install sched-ext (scx_bpfland) from the CachyOS COPR.
#                  Default off: gains on 4C/8T Zen+ are modest; COPR is
#                  third-party. Enable only if you know you want it.
#   MS_CORE_FONTS=1 Install MS core fonts via the SourceForge third-party RPM
#                  (no signature verification possible). Default off; the
#                  metric-compatible Carlito/Caladea fonts are installed by
#                  default and cover LibreOffice compatibility fine.
#   DNS_OVER_TLS=1 Enable DNS-over-TLS for systemd-resolved. Default off:
#                  port 853 is blocked on some networks and breaks captive
#                  portals / split-horizon DNS.
#
# Run:   git clone <this repo> && read this file && sudo ./setup.sh
# Never: curl | sudo bash.  You verified this script yourself.
# ==============================================================================

{
set -euo pipefail
FAILURES=0

SCX="${SCX:-0}"
MS_CORE_FONTS="${MS_CORE_FONTS:-0}"
DNS_OVER_TLS="${DNS_OVER_TLS:-0}"

# Ensure script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run with root privileges (sudo)." >&2
    exit 1
fi

# Prevent commands from swallowing the script when executed from a pipe
exec < /dev/null

# ==============================================================================
# USER DISCOVERY
# ==============================================================================
TARGET_USER="${SUDO_USER:-$(whoami)}"
if [ "$TARGET_USER" = "root" ]; then
    echo "Warning: Running as root directly. Settings and dotfiles will be applied to /root."
    TARGET_HOME="/root"
    TARGET_GROUP="root"
else
    TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
    TARGET_GROUP=$(id -gn "$TARGET_USER")
fi
echo "--> Target User: $TARGET_USER  |  Home: $TARGET_HOME"

# ==============================================================================
# 1. DNF SPEEDUPS (works for both dnf5 and legacy dnf configs)
# ==============================================================================
configure_dnf_speedups() {
    local conf_file="$1"
    [ -f "$conf_file" ] || return 0
    echo "--> Configuring DNF speedups in $conf_file..."
    for opt in max_parallel_downloads=20 defaultyes=True; do
        local key="${opt%%=*}" val="${opt#*=}"
        sed -i "/^${key}[[:space:]]*=/d" "$conf_file"
        sed -i "/^\[main\]/a $key = $val" "$conf_file"
    done
    chmod 0644 "$conf_file"
}
configure_dnf_speedups "/etc/dnf/dnf.conf"
configure_dnf_speedups "/etc/dnf5/dnf.conf"

# ==============================================================================
# 2. BASE SYSTEM UPGRADE
#    Done BEFORE third-party repos so only official Fedora packages are
#    involved in the base upgrade.
# ==============================================================================
echo "--> Upgrading all system packages (official repos only)..."
dnf upgrade -y --refresh || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }
echo "--> Upgrading the core package group..."
dnf group upgrade core -y || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }

# ==============================================================================
# 3. THIRD-PARTY REPOSITORIES
# ==============================================================================
FEDORA_VERSION=$(rpm -E %fedora)

echo "--> Installing RPM Fusion Free and Nonfree repositories..."
dnf install -y "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm" || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }
dnf install -y "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm" || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }

if [ "$SCX" = "1" ]; then
    echo "--> Enabling CachyOS COPR for sched-ext (optional, flag SCX=1)..."
    dnf copr enable -y bieszczaders/kernel-cachyos-addons || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }
fi

# First-party vendor repos (each is a deliberate trust decision - review them)
mkdir -p /etc/yum.repos.d
echo "--> Adding VS Code repository..."
cat <<EOF > /etc/yum.repos.d/vscode.repo
[vscode]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
enabled=1
EOF

echo "--> Adding Google Chrome repository..."
cat <<EOF > /etc/yum.repos.d/google-chrome.repo
[google-chrome]
name=Google Chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/\$basearch
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
enabled=1
EOF

echo "--> Adding Google Cloud CLI repository..."
cat <<EOF > /etc/yum.repos.d/google-cloud-cli.repo
[google-cloud-cli]
name=Google Cloud CLI
baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el9-\$basearch
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
enabled=1
EOF

# Disable unused limited third-party repos (NVIDIA & Steam) on AMD hardware
WORKSTATION_REPOS="/etc/yum.repos.d/fedora-workstation-repositories.repo"
if [ -f "$WORKSTATION_REPOS" ]; then
    echo "--> Disabling unused Workstation repositories (NVIDIA & Steam)..."
    for section in rpmfusion-nonfree-nvidia-driver rpmfusion-steam; do
        sed -i "/^\[$section\]/,/^\[/{s/^enabled=.*/enabled=0/}" "$WORKSTATION_REPOS"
    done
fi

# ==============================================================================
# 4. MULTIMEDIA SWAP (needs RPM Fusion, does not affect base system)
# ==============================================================================
echo "--> Swapping ffmpeg-free with full ffmpeg..."
dnf install -y ffmpeg --allowerasing || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }

echo "--> Installing RPM Fusion multimedia group..."
dnf group install -y "multimedia" --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }

# ==============================================================================
# 5. CONSOLIDATED PACKAGE INSTALLATION (single transaction)
#    Sway-first list: compositor, ecosystem, portals, AMD HW accel, laptop power
# ==============================================================================
echo "--> Installing Sway stack, applications, runtimes and dev tools..."
PKGS=(
    # Sway stack (idempotent on the spin; ensures Fedora config + companions)
    sway sway-config-fedora
    xdg-desktop-portal-wlr xdg-desktop-portal-gtk   # screen share + GTK file pickers
    cliphist wl-clipboard                            # clipboard history
    swappy                                         # screenshot annotation
    pavucontrol                                    # audio GUI (floats by default in Fedora config)
    kanshi dunst                                    # display hotplug + notifications (spin ships both)
    # AMD / VCN 1.0 video acceleration (Fedora 44 = Mesa 26: base VA-API lives in
    # mesa-dri-drivers; freeworld adds H.264/HEVC codecs; libva-utils provides vainfo)
    mesa-dri-drivers mesa-va-drivers-freeworld libva-utils
    # Laptop power management (Zen+ has no amd-pstate/PPD support; TLP is the right tool)
    tlp tlp-rdw
    # Applications  (no vlc/gstreamer1-plugin-libav in RPM Fusion for F44 yet; mpv
    # + ffmpeg + the multimedia group cover media playback - see README)
    firefox mpv gnome-boxes
    code google-chrome-stable google-cloud-cli
    libreoffice
    # Runtimes & build tools (Fedora 44 ships Node.js as versioned packages;
    # nodejs24 is the current LTS line and bundles npm)
    @development-tools
    nodejs24 python3 python3-pip python3-devel distrobox git
    # Shell
    zsh zsh-syntax-highlighting zsh-autosuggestions
    # Desktop plumbing
    flatpak qt5ct qt6ct
    cabextract mkfontscale fontconfig
    7zip 7zip-standalone
    google-carlito-fonts google-crosextra-caladea-fonts
)
if [ "$SCX" = "1" ]; then
    PKGS+=(scx-scheds scx-tools)
fi
dnf install -y "${PKGS[@]}" || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }

# Firmware updates (after base upgrade; needs a quiet moment)
if command -v fwupdmgr >/dev/null 2>&1; then
    echo "--> Refreshing firmware metadata and applying pending updates..."
    fwupdmgr refresh --force || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }
    fwupdmgr update -y || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }
fi

# ==============================================================================
# 6. SYSTEM OPTIMIZATIONS
# ==============================================================================
echo "--> Configuring memory/power sysctls..."
cat > /etc/sysctl.d/99-sway-laptop.conf <<'EOF'
# Laptop-oriented memory policy
vm.swappiness = 10
vm.vfs_cache_pressure = 50
# Reduce writeback frequency (battery; trade-off: slightly more data in flight)
vm.dirty_writeback_centisecs = 1500
# NMI watchdog off: saves power, but removes one deadlock detector.
# Remove this line if you want kernel watchdog reporting.
kernel.nmi_watchdog = 0
EOF
chmod 0644 /etc/sysctl.d/99-sway-laptop.conf
sysctl -p /etc/sysctl.d/99-sway-laptop.conf >/dev/null || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }

echo "--> Enabling noatime for Btrfs volumes in /etc/fstab (backup kept)..."
cp -a /etc/fstab /etc/fstab.bak 2>/dev/null || true
sed -i '/\sbtrfs\s/{/noatime/!s/\(subvol=[^[:space:],]*\)/\1,noatime/; s/,relatime//}' /etc/fstab
systemctl daemon-reload
mount -o remount / || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }
printf '  (verify with: findmnt -no OPTIONS / | tr "," "\\n")\n'

echo "--> Disabling NetworkManager-wait-online.service to speed up boot..."
systemctl disable NetworkManager-wait-online.service || true

echo "--> Enabling weekly SSD TRIM timer..."
systemctl enable fstrim.timer || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }

echo "--> Capping systemd journal size to 500MB..."
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/99-size.conf <<'EOF'
[Journal]
SystemMaxUse=500M
EOF
systemctl restart systemd-journald || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }

echo "--> Setting GRUB timeout to 2 seconds..."
if [ -f /etc/default/grub ]; then
    if grep -q '^GRUB_TIMEOUT=' /etc/default/grub; then
        sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=2/' /etc/default/grub
    else
        echo 'GRUB_TIMEOUT=2' >> /etc/default/grub
    fi
    GRUB_CFG=""
    if [ -e /etc/grub2.cfg ]; then
        GRUB_CFG=$(readlink -f /etc/grub2.cfg) || true
    fi
    if [ -z "$GRUB_CFG" ] && [ -e /etc/grub2-efi.cfg ]; then
        GRUB_CFG=$(readlink -f /etc/grub2-efi.cfg) || true
    fi
    if [ -z "$GRUB_CFG" ] && [ -f /boot/grub2/grub.cfg ]; then
        GRUB_CFG=/boot/grub2/grub.cfg
    fi
    if [ -n "$GRUB_CFG" ]; then
        grub2-mkconfig -o "$GRUB_CFG" >/dev/null 2>&1 || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }
    else
        echo "  !! Warning: could not determine GRUB config path - timeout change may not apply"
    fi
fi

echo "--> Disabling unneeded services (uninstall-friendly; disable, not mask)..."
for svc in ModemManager cups abrtd; do
    if systemctl list-unit-files "$svc.service" >/dev/null 2>&1; then
        systemctl disable --now "$svc.service" >/dev/null 2>&1 || true
    fi
done

echo "--> Enabling TLP (power management; conflicts with power-profiles-daemon - do not install both)..."
systemctl enable --now tlp tlp-rdw || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }

if [ "$SCX" = "1" ]; then
    echo "--> Configuring sched-ext (SCX) to use scx_bpfland..."
    mkdir -p /etc/default
    echo "SCX_SCHEDULER=scx_bpfland" > /etc/default/scx
    systemctl enable --now scx_loader 2>/dev/null || systemctl enable --now scx || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }
    echo "  (verify: systemctl status scx_loader --no-pager | head -5)"
fi

# ==============================================================================
# 7. FLATPAK (Flathub; drop the stock Fedora remote)
# ==============================================================================
echo "--> Setting up Flatpak: Flathub repo..."
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }
if flatpak remote-list | grep -q '^fedora'; then
    flatpak remote-delete fedora || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }
fi
echo "--> Updating installed Flatpaks..."
flatpak update -y || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }

# ==============================================================================
# 8. GTK / QT THEMING (applies to apps under Sway; does not touch the WM)
# ==============================================================================
echo "--> Setting system-wide GTK defaults (dark mode, window buttons)..."
cat > /usr/share/glib-2.0/schemas/99-sway.gschema.override <<'EOF'
[org.gnome.desktop.interface]
color-scheme='prefer-dark'
gtk-theme='Adwaita-dark'

[org.gnome.desktop.wm.preferences]
button-layout='appmenu:minimize,maximize,close'
EOF
glib-compile-schemas /usr/share/glib-2.0/schemas/ || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }

# ==============================================================================
# 9. SWAY USER CONFIGURATION
#    The Fedora spin loads /usr/share/sway/config.d, /etc/sway/config.d and
#    ~/.config/sway/config.d (later dirs win). We only ADD files and never
#    overwrite - so your later manual edits are safe.
# ==============================================================================
if [ "$TARGET_USER" != "root" ]; then
    SWAY_UD="$TARGET_HOME/.config/sway/config.d"
    mkdir -p "$SWAY_UD" "$TARGET_HOME/.config/kanshi" "$TARGET_HOME/.local/bin"
    chown -R "$TARGET_USER":"$TARGET_GROUP" "$TARGET_HOME/.config/sway" "$TARGET_HOME/.config/kanshi" "$TARGET_HOME/.local/bin"

    # -- Touchpad / input (Sway reads libinput directly - gsettings does NOT apply)
    if [ ! -e "$SWAY_UD/10-usr-input.conf" ]; then
        cat > "$SWAY_UD/10-usr-input.conf" <<'SWAYEOF'
# Input tweaks (written by fedora-setup; edit freely, reload with $mod+Shift+c)
#
# Find your device names:  swaymsg -t get_inputs
input "type:touchpad" {
    tap enabled
    natural_scroll enabled
    middle_emulation enabled
    dwt enabled
}
# Optional: swap Caps Lock for Esc (vim-friendly)
# input "type:keyboard" { xkb_options caps:escape }
SWAYEOF
        echo "--> Wrote $SWAY_UD/10-usr-input.conf"
    fi

    # -- Clipboard history, screenshot annotation, kanshi autostart
    if [ ! -e "$SWAY_UD/40-usr-tools.conf" ]; then
        cat > "$SWAY_UD/40-usr-tools.conf" <<'SWAYEOF'
# Clipboard & tools (written by fedora-setup; edit freely, reload with $mod+Shift+c)
#
# Clipboard history via rofi: pick an entry, paste with Ctrl+V / $mod+Shift+v again
bindsym $mod+Shift+v exec --no-startup-id sh -c 'cliphist list | rofi -dmenu | cliphist decode | wl-copy'

# Annotate a selected area with swappy (swap=tmpfile because swappy cannot read stdin)
bindsym $mod+Shift+Print exec --no-startup-id sh -c 'tmp=$(mktemp --suffix=.png) && grim -g "$(slurp)" - > "$tmp" && swappy -f "$tmp"'

# Dynamic display profiles (kanshi). Remove this line if kanshi is already
# started by your session (e.g. via a systemd --user service).
exec kanshi
SWAYEOF
        echo "--> Wrote $SWAY_UD/40-usr-tools.conf"
    fi

    # -- Environment for apps spawned by Sway (was sourced by spin's start-sway)
    if [ ! -e "$TARGET_HOME/.config/sway/environment" ]; then
        cat > "$TARGET_HOME/.config/sway/environment" <<'SWAYEOF'
# App environment written by fedora-setup; edit freely.
# Electron apps (VS Code, Discord, Slack, Obsidian...) -> native Wayland
ELECTRON_OZONE_PLATFORM_HINT=auto
# Qt theming through qt6ct / qt5ct
QT_QPA_PLATFORMTHEME=qt6ct
SWAYEOF
        echo "--> Wrote $TARGET_HOME/.config/sway/environment"
    fi

    # -- kanshi profile template (write-once; adjust output names per your hardware)
    if [ ! -e "$TARGET_HOME/.config/kanshi/config" ]; then
        cat > "$TARGET_HOME/.config/kanshi/config" <<'SWAYEOF'
# Profile template (written by fedora-setup; edit freely).
# Find your output names:  swaymsg -t get_outputs
profile builtin {
    output eDP-1 enable
}

# Example for an external monitor over HDMI - uncomment after checking names:
# profile dock {
#     output eDP-1 enable
#     output HDMI-A-1 enable position 1920,0
# }
SWAYEOF
        echo "--> Wrote $TARGET_HOME/.config/kanshi/config"
    fi

    chown -R "$TARGET_USER":"$TARGET_GROUP" "$TARGET_HOME/.config/sway" "$TARGET_HOME/.config/kanshi" "$TARGET_HOME/.local/bin"
fi

# ==============================================================================
# 10. FONTS
# ==============================================================================
if [ "$TARGET_USER" != "root" ]; then
    echo "--> Creating local fonts directory and installing Fira Code Nerd Font..."
    FONT_DIR="$TARGET_HOME/.local/share/fonts"
    mkdir -p "$FONT_DIR"
    chown "$TARGET_USER":"$TARGET_GROUP" "$FONT_DIR"
    chmod 0755 "$FONT_DIR"
    if ! compgen -G "$FONT_DIR/FiraCode*.ttf" >/dev/null 2>&1; then
        sudo -u "$TARGET_USER" curl -fsSL -o "$TARGET_HOME/FiraCode.tar.xz" https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.tar.xz || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }
        if [ -f "$TARGET_HOME/FiraCode.tar.xz" ]; then
            sudo -u "$TARGET_USER" tar -xf "$TARGET_HOME/FiraCode.tar.xz" -C "$FONT_DIR"
            rm -f "$TARGET_HOME/FiraCode.tar.xz"
        fi
    fi
fi

if [ "$MS_CORE_FONTS" = "1" ]; then
    echo "--> Installing Microsoft Core Fonts (optional, flag MS_CORE_FONTS=1)..."
    MSRPM="/tmp/msttcore-fonts-installer-2.6-1.noarch.rpm"
    curl -fsSL -o "$MSRPM" https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }
    if [ -f "$MSRPM" ]; then
        # Third-party RPM; no trustworthy signature - reviewed & accepted by flag.
        rpm -i "$MSRPM" 2>/dev/null || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }
    fi
else
    echo "--> Skipping MS core fonts (set MS_CORE_FONTS=1 to enable). Carlito/Caladea metric-compatible fonts were installed."
fi

echo "--> Rebuilding font cache..."
fc-cache -f || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }

# ==============================================================================
# 11. NODE TOOLCHAIN (as the user - never as root, so upgrades need no sudo)
# ==============================================================================
if command -v npm >/dev/null 2>&1; then
    echo "--> Installing TypeScript, its language server and Reasonix CLI (user-level)..."
    sudo -u "$TARGET_USER" npm install -g typescript typescript-language-server reasonix || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }
    echo "  (binaries land in ~/.local/bin, already on PATH via the zsh block below)"
fi

# ==============================================================================
# 12. SHELL & USABILITY POLISH
# ==============================================================================
if [ "$TARGET_USER" != "root" ]; then
    echo "--> Changing default shell to Zsh..."
    usermod -s /bin/zsh "$TARGET_USER"

    echo "--> Configuring Zsh options and plugins in .zshrc..."
    ZSHRC_FILE="$TARGET_HOME/.zshrc"
    if ! grep -q 'BEGIN SETUP BLOCKS' "$ZSHRC_FILE" 2>/dev/null; then
        cat >> "$ZSHRC_FILE" <<'ZSHBLOCK'

# BEGIN SETUP BLOCKS
# Initialize Starship Prompt if installed (not packaged in Fedora 41+; if you
# want it: install via cargo, or replace with a plain prompt)
if command -v starship >/dev/null 2>&1; then
    eval "$(starship init zsh)"
fi

# Enable syntax highlighting and autosuggestions from DNF packages
source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh

# Ensure local bin is in PATH (npm user-level packages, scripts)
export PATH="$HOME/.local/bin:$PATH"

# Sane Zsh options
setopt HIST_IGNORE_DUPS
setopt SHARE_HISTORY

# Custom alias to easily reload zsh config
alias reload="source ~/.zshrc"
# END SETUP BLOCKS
ZSHBLOCK
    fi
    chown "$TARGET_USER":"$TARGET_GROUP" "$ZSHRC_FILE"
fi

echo "--> Enabling sudo password feedback..."
echo "Defaults pwfeedback" > /etc/sudoers.d/pwfeedback
chmod 0440 /etc/sudoers.d/pwfeedback

# ==============================================================================
# 13. DNS (SYSTEMD-RESOLVED) - LAST, SO A NETWORK RESTART CANNOT INTERRUPT EARLIER STEPS
# ==============================================================================
echo "--> Configuring systemd-resolved (Cloudflare primary, Google fallback)..."
mkdir -p /etc/systemd/resolved.conf.d
{
    printf '[Resolve]\nDNS=1.1.1.1 1.0.0.1\nFallbackDNS=8.8.8.8\n'
    if [ "$DNS_OVER_TLS" = "1" ]; then
        printf 'DNSOverTLS=yes\n'
    fi
} > /etc/systemd/resolved.conf.d/99-dns.conf
systemctl enable --now systemd-resolved || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }
mkdir -p /etc/NetworkManager/conf.d
printf '[main]\ndns=systemd-resolved\n' > /etc/NetworkManager/conf.d/99-systemd-resolved.conf
systemctl restart NetworkManager || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }

# ==============================================================================
# SUMMARY
# ==============================================================================
if [ "$FAILURES" -gt 0 ]; then
    echo ""
    echo "=============================================================================="
    echo "Setup finished with $FAILURES failed step(s) - look for '!!' markers above."
    echo "=============================================================================="
else
    echo ""
    echo "=============================================================================="
    echo "Setup complete! Reboot, then log in to the Sway session."
    echo ""
    echo "Quick checks inside Sway:"
    echo "  swaymsg -t get_outputs        # display names/resolution"
    echo "  swaymsg -t get_inputs         # devices (tap/natural scroll already set)"
    echo "  systemctl status tlp --no-pager | head -3"
    echo "  vainfo                        # VCN 1.0 decode should enumerate"
    echo "  systemctl status scx_loader --no-pager | head -3   (only with SCX=1)"
    echo ""
    echo "If notifications never appear: systemctl --user enable --now dunst"
    echo "=============================================================================="
fi
}
