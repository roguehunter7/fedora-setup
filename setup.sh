#!/usr/bin/env bash
# ==============================================================================
# Fedora Workstation (GNOME) - Post-Install Setup
# ==============================================================================
# Target   : Fresh Fedora Workstation install (GNOME Wayland)
# Hardware : AMD Ryzen/Picasso laptop (amdgpu, Vega 8, VCN)
# Shell    : Zsh + Starship + FZF
# Browser  : Brave Origin (native RPM with PWAs + Widevine DRM, no AI/Crypto)
# Node     : Fast Node Manager (fnm) -> Latest Node.js and npm (clean, use npx)
# ==============================================================================

{
set -euo pipefail
FAILURES=0

# Ensure script is run with sudo
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run with root privileges (sudo)." >&2
    exit 1
fi

exec < /dev/null

# ==============================================================================
# USER DISCOVERY
# ==============================================================================
TARGET_USER="${SUDO_USER:-$(whoami)}"
if [ "$TARGET_USER" = "root" ]; then
    echo "Warning: Running as root directly. Settings will be applied to /root."
    TARGET_HOME="/root"
    TARGET_GROUP="root"
else
    TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
    TARGET_GROUP=$(id -gn "$TARGET_USER")
fi
echo "--> Target User: $TARGET_USER  |  Home: $TARGET_HOME"

# ==============================================================================
# 1. DNF 5 SPEEDUPS (KISS Drop-in)
# ==============================================================================
echo "--> Configuring DNF parallel downloads via clean drop-in..."
mkdir -p /etc/dnf/libdnf5.conf.d
cat <<EOF > /etc/dnf/libdnf5.conf.d/80-parallel-downloads.conf
[main]
max_parallel_downloads = 10
EOF
chmod 0644 /etc/dnf/libdnf5.conf.d/80-parallel-downloads.conf

# ==============================================================================
# 2. BASE SYSTEM UPGRADE
# ==============================================================================
echo "--> Refreshing and upgrading system packages..."
dnf upgrade -y --refresh || { FAILURES=$((FAILURES+1)); echo "  !! Upgrade encountered an issue"; }

# ==============================================================================
# 3. REPOSITORIES
# ==============================================================================
FEDORA_VERSION=$(rpm -E %fedora)

echo "--> Installing RPM Fusion Free and Nonfree repositories..."
dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm" || { FAILURES=$((FAILURES+1)); echo "  !! RPM Fusion install failed"; }

# Disable duplicate Workstation repos (Steam and NVIDIA are provided by full RPM Fusion)
WORKSTATION_REPOS="/etc/yum.repos.d/fedora-workstation-repositories.repo"
if [ -f "$WORKSTATION_REPOS" ]; then
    echo "--> Disabling duplicate Workstation repositories..."
    for section in rpmfusion-nonfree-nvidia-driver rpmfusion-steam; do
        sed -i "/^\[$section\]/,/^\[/{s/^enabled=.*/enabled=0/}" "$WORKSTATION_REPOS"
    done
fi

mkdir -p /etc/yum.repos.d

echo "--> Adding Brave Browser repository..."
cat <<EOF > /etc/yum.repos.d/brave-browser.repo
[brave-browser]
name=Brave Browser
baseurl=https://brave-browser-rpm-release.s3.brave.com/x86_64/
enabled=1
gpgcheck=1
gpgkey=https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
EOF

echo "--> Adding VS Code repository..."
cat <<EOF > /etc/yum.repos.d/vscode.repo
[vscode]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
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

# ==============================================================================
# 4. MULTIMEDIA and HARDWARE ACCELERATION (AMD Picasso / Vega 8)
# ==============================================================================
echo "--> Swapping ffmpeg-free with full ffmpeg..."
dnf install -y ffmpeg --allowerasing || { FAILURES=$((FAILURES+1)); echo "  !! ffmpeg swap failed"; }

echo "--> Installing RPM Fusion multimedia group..."
dnf group install -y "multimedia" --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin || { FAILURES=$((FAILURES+1)); echo "  !! multimedia group install failed"; }

echo "--> Installing sound-and-video group..."
dnf group install -y "sound-and-video" || { FAILURES=$((FAILURES+1)); echo "  !! sound-and-video group install failed"; }

echo "--> Swapping in freeworld Mesa Vulkan drivers (Vulkan Video H.264/H.265)..."
if rpm -q mesa-vulkan-drivers >/dev/null 2>&1 && ! rpm -q mesa-vulkan-drivers-freeworld >/dev/null 2>&1; then
    dnf swap -y mesa-vulkan-drivers mesa-vulkan-drivers-freeworld || { FAILURES=$((FAILURES+1)); echo "  !! mesa-vulkan-drivers freeworld swap failed"; }
else
    echo "    (already on mesa-vulkan-drivers-freeworld, or stock driver not present)"
fi

# ==============================================================================
# 5. CORE PACKAGES and TOOLS
# ==============================================================================
echo "--> Removing stock Firefox..."
dnf remove -y firefox || true

echo "--> Installing Brave Origin, AMD hardware acceleration, and developer tools..."
PKGS=(
    # Hardware acceleration for AMD VCN 1.0 / Vega 8
    mesa-dri-drivers mesa-va-drivers-freeworld libva libva-utils ffmpeg-libs
    # Primary browser and desktop apps
    brave-origin mpv gnome-boxes code google-cloud-cli libreoffice
    # Build tools, AppImage runtime (fuse-libs) and shell utilities
    @development-tools python3 python3-pip distrobox git curl unzip zsh fzf fuse-libs
    # Archives and fonts (cabextract required by Microsoft Core Fonts)
    flatpak cabextract mkfontscale fontconfig 7zip 7zip-standalone
    google-carlito-fonts google-crosextra-caladea-fonts
)

dnf install -y "${PKGS[@]}" || { FAILURES=$((FAILURES+1)); echo "  !! Package installation failed"; }

# Firmware updates
if command -v fwupdmgr >/dev/null 2>&1; then
    echo "--> Checking for firmware updates..."
    fwupdmgr refresh --force || true
    fwupdmgr update -y || true
fi

# ==============================================================================
# 6. SYSTEM TUNING (KISS)
# ==============================================================================
echo "--> Enabling weekly SSD TRIM timer..."
systemctl enable fstrim.timer || true

echo "--> Disabling NetworkManager-wait-online.service..."
systemctl disable NetworkManager-wait-online.service || true

echo "--> Capping systemd journal size to 500MB..."
mkdir -p /etc/systemd/journald.conf.d
cat <<EOF > /etc/systemd/journald.conf.d/99-size.conf
[Journal]
SystemMaxUse=500M
EOF
systemctl restart systemd-journald || true

echo "--> Setting GRUB timeout to 2 seconds..."
if [ -f /etc/default/grub ]; then
    sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=2/' /etc/default/grub || echo 'GRUB_TIMEOUT=2' >> /etc/default/grub
    if [ -f /boot/grub2/grub.cfg ]; then
        grub2-mkconfig -o /boot/grub2/grub.cfg >/dev/null 2>&1 || true
    fi
fi

echo "--> Disabling unneeded background services..."
for svc in ModemManager cups abrtd; do
    if systemctl list-unit-files "$svc.service" >/dev/null 2>&1; then
        systemctl disable --now "$svc.service" >/dev/null 2>&1 || true
    fi
done

# ==============================================================================
# 7. FLATPAK (Flathub Only)
# ==============================================================================
echo "--> Configuring Flatpak..."
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
if flatpak remote-list | grep -q '^fedora'; then
    flatpak remote-delete fedora || true
fi
flatpak update -y || true

# ==============================================================================
# 8. ZSH SHELL, STARSHIP and FZF
# ==============================================================================
echo "--> Installing Starship prompt..."
curl -sS https://starship.rs/install.sh | sh -s -- -y -b /usr/local/bin || { FAILURES=$((FAILURES+1)); echo "  !! Starship install failed"; }

if [ "$TARGET_USER" != "root" ]; then
    ZSH_BIN="$(command -v zsh || true)"
    if [ -n "$ZSH_BIN" ]; then
        echo "--> Setting zsh as the default shell for $TARGET_USER..."
        grep -qx "$ZSH_BIN" /etc/shells || echo "$ZSH_BIN" >> /etc/shells
        if [ "$(getent passwd "$TARGET_USER" | cut -d: -f7)" != "$ZSH_BIN" ]; then
            chsh -s "$ZSH_BIN" "$TARGET_USER" || { FAILURES=$((FAILURES+1)); echo "  !! chsh to zsh failed"; }
        fi
    else
        FAILURES=$((FAILURES+1)); echo "  !! zsh not found; skipping shell switch"
    fi

    echo "--> Writing ~/.zshrc..."
    ZSHRC_FILE="$TARGET_HOME/.zshrc"
    if ! grep -q 'BEGIN SETUP BLOCKS' "$ZSHRC_FILE" 2>/dev/null; then
        cat <<'ZSHBLOCK' >> "$ZSHRC_FILE"

# BEGIN SETUP BLOCKS
# 1. History
HISTFILE="$HOME/.zsh_history"
HISTSIZE=10000
SAVEHIST=20000
setopt hist_ignore_all_dups hist_ignore_space share_history extended_history inc_append_history

# 2. Navigation and globbing
setopt autocd correct extendedglob

# 3. Completion (case-insensitive, menu select)
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
setopt always_to_end complete_in_word

# 4. Prefix-matching history search (type "git " then Up to filter history)
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search

# 5. PATH
export PATH="$HOME/.local/bin:$PATH"

# 6. Fast Node Manager (fnm)
export PATH="$HOME/.local/share/fnm:$PATH"
if command -v fnm >/dev/null 2>&1; then
    eval "$(fnm env --use-on-cd --resolve-engines --shell zsh)"
fi

# 7. FZF Integration (Ctrl+R history search, Ctrl+T file finding)
if command -v fzf >/dev/null 2>&1; then
    if fzf --zsh >/dev/null 2>&1; then
        source <(fzf --zsh)
    elif [ -f /usr/share/fzf/shell/key-bindings.zsh ]; then
        source /usr/share/fzf/shell/key-bindings.zsh
    fi
fi

# 8. Starship Prompt
if command -v starship >/dev/null 2>&1; then
    eval "$(starship init zsh)"
fi
# END SETUP BLOCKS
ZSHBLOCK
    fi
    chown "$TARGET_USER":"$TARGET_GROUP" "$ZSHRC_FILE"
fi

# ==============================================================================
# 9. NODE.JS VIA FNM (Latest Version - Clean, Zero Global NPM Packages)
# ==============================================================================
if [ "$TARGET_USER" != "root" ]; then
    echo "--> Installing fnm (Fast Node Manager) for $TARGET_USER..."
    sudo -u "$TARGET_USER" bash -c 'curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell' || { FAILURES=$((FAILURES+1)); echo "  !! fnm install failed"; }

    echo "--> Installing latest Node.js release and setting as default..."
    sudo -u "$TARGET_USER" bash -c '
        export PATH="$HOME/.local/share/fnm:$PATH"
        eval "$("$HOME/.local/share/fnm/fnm" env --shell zsh)"
        fnm install --latest
        fnm default latest
    ' || { FAILURES=$((FAILURES+1)); echo "  !! Node.js installation via fnm failed"; }
fi

# ==============================================================================
# 10. GNOME PREFERENCES and DESKTOP POLISH
# ==============================================================================
if [ "$TARGET_USER" != "root" ]; then
    echo "--> Setting GNOME interface to prefer dark theme..."
    sudo -u "$TARGET_USER" dbus-run-session gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || true

    echo "--> Disabling GNOME Software background autostart & search provider (saving ~500MB RAM)..."
    mkdir -p "$TARGET_HOME/.config/autostart"
    if [ -f /usr/share/applications/org.gnome.Software.desktop ]; then
        cp -f /usr/share/applications/org.gnome.Software.desktop "$TARGET_HOME/.config/autostart/"
        echo "X-GNOME-Autostart-enabled=false" >> "$TARGET_HOME/.config/autostart/org.gnome.Software.desktop"
    fi
    chown -R "$TARGET_USER":"$TARGET_GROUP" "$TARGET_HOME/.config/autostart"
    sudo -u "$TARGET_USER" dbus-run-session gsettings set org.gnome.desktop.search-providers disabled "['org.gnome.Software.desktop']" 2>/dev/null || true
fi

# ==============================================================================
# 11. FONTS (Fira Code Nerd Font and Microsoft Core Fonts)
# ==============================================================================
if [ "$TARGET_USER" != "root" ]; then
    echo "--> Installing Fira Code Nerd Font..."
    FONT_DIR="$TARGET_HOME/.local/share/fonts"
    mkdir -p "$FONT_DIR"
    chown "$TARGET_USER":"$TARGET_GROUP" "$FONT_DIR"
    chmod 0755 "$FONT_DIR"

    if ! compgen -G "$FONT_DIR/FiraCode*.ttf" >/dev/null 2>&1; then
        sudo -u "$TARGET_USER" curl -fsSL -o "$TARGET_HOME/FiraCode.tar.xz" https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.tar.xz || true
        if [ -f "$TARGET_HOME/FiraCode.tar.xz" ]; then
            sudo -u "$TARGET_USER" tar -xf "$TARGET_HOME/FiraCode.tar.xz" -C "$FONT_DIR"
            rm -f "$TARGET_HOME/FiraCode.tar.xz"
        fi
    fi
fi

echo "--> Installing Microsoft Core Fonts..."
MSRPM="/tmp/msttcore-fonts-installer-2.6-1.noarch.rpm"
curl -fsSL -o "$MSRPM" https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm || true
if [ -f "$MSRPM" ]; then
    rpm -i "$MSRPM" 2>/dev/null || true
    rm -f "$MSRPM"
fi

echo "--> Refreshing font cache..."
fc-cache -f || true

# ==============================================================================
# 12. USABILITY POLISH
# ==============================================================================
echo "--> Enabling sudo password feedback asterisks..."
echo "Defaults pwfeedback" > /etc/sudoers.d/pwfeedback
chmod 0440 /etc/sudoers.d/pwfeedback

# ==============================================================================
# 13. DNS RESOLVER (Strict DNS-over-TLS via Cloudflare and Google)
# ==============================================================================
echo "--> Configuring systemd-resolved with strict DNS-over-TLS..."
mkdir -p /etc/systemd/resolved.conf.d
cat <<EOF > /etc/systemd/resolved.conf.d/99-dns.conf
[Resolve]
DNS=1.1.1.1#cloudflare-dns.com 1.0.0.1#cloudflare-dns.com
FallbackDNS=8.8.8.8#dns.google 8.8.4.4#dns.google
DNSOverTLS=yes
Domains=~.
EOF

systemctl enable --now systemd-resolved || true
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf || true

mkdir -p /etc/NetworkManager/conf.d
printf '[main]\ndns=systemd-resolved\n' > /etc/NetworkManager/conf.d/99-systemd-resolved.conf
systemctl restart NetworkManager || true

# ==============================================================================
# SUMMARY
# ==============================================================================
echo ""
echo "=============================================================================="
if [ "$FAILURES" -gt 0 ]; then
    echo "Setup finished with $FAILURES non-fatal warning(s) or failure(s)."
else
    echo "Setup complete! All steps finished successfully."
fi
echo "=============================================================================="
echo "Quick verification:"
echo "  node -v                       # Verify active Node version"
echo "  npm -v                        # Verify npm"
echo "  brave-origin                  # Launch Brave Origin"
echo "  vainfo                        # Verify AMD VCN video hardware acceleration"
echo "  powerprofilesctl              # Verify GNOME power profiles daemon"
echo "  echo \$SHELL                  # Should print /usr/bin/zsh after re-login"
echo ""
echo "Please reboot to ensure all graphics, power, and session changes are cleanly loaded."
echo "=============================================================================="
}
