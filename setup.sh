#!/usr/bin/env bash
# ==============================================================================
# Arch Linux (KDE Plasma 6) - Post-Install Setup
# ==============================================================================
# Target   : Fresh Arch Linux install (KDE Plasma 6, Wayland, GRUB)
# Hardware : AMD Ryzen 5 3500U / 8GB RAM / NVMe SSD / Btrfs
# Power    : TLP and a 60% battery charge limit
# Shell    : Zsh + Starship + FZF
# Browser  : Firefox
# Node     : Fast Node Manager (fnm) -> latest Node.js (clean, use npx)
# Java     : latest OpenJDK SDK (jdk-openjdk)
# Boot     : GRUB or systemd-boot (auto-detected); AMD microcode via mkinitcpio
# Safety   : snapper + snap-pac + grub-btrfs snapshots, AppArmor
# ==============================================================================
# Lean philosophy: a curated package set instead of plasma-meta / gnome-meta.
# Mirrors the Fedora setup's tuning, shell, fonts, DNS and SSD work.
# Hibernation is intentionally not supported (zram-only swap).
# ==============================================================================
# Usage: sudo ./setup.sh [--dry-run] [--no-reboot]
# ==============================================================================

set -euo pipefail
exec < /dev/null

DRY_RUN=0
DO_REBOOT=1
for arg in "$@"; do
    case "$arg" in
        --dry-run)   DRY_RUN=1 ;;
        --no-reboot) DO_REBOOT=0 ;;
        -h|--help)
            cat <<'USAGE'
Usage: sudo ./setup.sh [options]

  --dry-run     Print what would be done. Nothing is installed or written.
  --no-reboot   Do not reboot when the script finishes.
  -h, --help    Show this help.
USAGE
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n' "$arg" >&2
            exit 2
            ;;
    esac
done

# ------------------------------------------------------------------------------
# Logging
# ------------------------------------------------------------------------------
BOLD="$(tput bold 2>/dev/null || true)"
GREEN="$(tput setaf 2 2>/dev/null || true)"
BLUE="$(tput setaf 4 2>/dev/null || true)"
YELLOW="$(tput setaf 3 2>/dev/null || true)"
RED="$(tput setaf 1 2>/dev/null || true)"
RESET="$(tput sgr0 2>/dev/null || true)"

info() { printf '%s\n' "${BLUE}${BOLD}[INFO]${RESET} $*"; }
ok()   { printf '%s\n' "${GREEN}${BOLD}[ OK ]${RESET} $*"; }
warn() { printf '%s\n' "${YELLOW}${BOLD}[WARN]${RESET} $*" >&2; }
err()  { printf '%s\n' "${RED}${BOLD}[FAIL]${RESET} $*" >&2; }

FAILURES=0
fail() { FAILURES=$((FAILURES + 1)); err "$*"; }

# ------------------------------------------------------------------------------
# Preconditions
# ------------------------------------------------------------------------------
if [ ! -f /etc/arch-release ]; then
    err "This script targets Arch Linux (/etc/arch-release not found)."
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    err "This script must be run with root privileges: sudo ./setup.sh"
    exit 1
fi

LOG_FILE="/var/log/arch-setup-$(date +%Y%m%d-%H%M%S).log"
if [ "$DRY_RUN" = 0 ]; then
    exec > >(tee -a "$LOG_FILE") 2>&1
    info "Logging to $LOG_FILE"
fi

TARGET_USER="${SUDO_USER:-$(id -un)}"
if [ "$TARGET_USER" = "root" ]; then
    warn "Running directly as root. AUR builds and user dotfiles need a normal sudo user."
    TARGET_HOME="/root"
    TARGET_GROUP="root"
else
    TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
    TARGET_GROUP="$(id -gn "$TARGET_USER")"
fi
info "Target user: $TARGET_USER  |  Home: $TARGET_HOME"
if [ "$DRY_RUN" = 1 ]; then
    warn "DRY RUN: nothing will be installed, written, enabled, or rebooted."
fi

# ------------------------------------------------------------------------------
# Action helpers (dry-run aware)
# ------------------------------------------------------------------------------
run() {
    if [ "$DRY_RUN" = 1 ]; then
        printf '  [dry-run] %s\n' "$*"
        return 0
    fi
    "$@"
}

# Like run(), but records a failure instead of aborting the script.
try() { run "$@" || fail "$*"; }

# Replace a file's contents from stdin.
apply() {
    local path="$1"
    if [ "$DRY_RUN" = 1 ]; then
        printf '  [dry-run] write %s\n' "$path"
        cat > /dev/null
        return 0
    fi
    mkdir -p "$(dirname "$path")"
    cat > "$path"
}

# Append stdin to a file.
append_file() {
    local path="$1"
    if [ "$DRY_RUN" = 1 ]; then
        printf '  [dry-run] append %s\n' "$path"
        cat > /dev/null
        return 0
    fi
    cat >> "$path"
}

# ------------------------------------------------------------------------------
# Backups
# ------------------------------------------------------------------------------
BACKUP_DIR="/var/backups/arch-setup-$(date +%Y%m%d-%H%M%S)"
backup_file() {
    local f="$1"
    [ -e "$f" ] || return 0
    if [ "$DRY_RUN" = 1 ]; then
        printf '  [dry-run] backup %s\n' "$f"
        return 0
    fi
    mkdir -p "$BACKUP_DIR"
    cp -a "$f" "$BACKUP_DIR/$(printf '%s' "${f#/}" | tr '/' '_')"
}

info "Backing up files this script may overwrite..."
for f in \
    /etc/pacman.conf /etc/pacman.d/mirrorlist /etc/fstab \
    /etc/default/grub /boot/grub/grub.cfg /etc/mkinitcpio.conf \
    /boot/loader/loader.conf /etc/kernel/cmdline \
    /etc/makepkg.conf /etc/sudoers.d/pwfeedback \
    /etc/systemd/zram-generator.conf /etc/sysctl.d/99-performance.conf \
    /etc/default/earlyoom /etc/xdg/baloofilerc \
    /etc/systemd/journald.conf.d /etc/systemd/resolved.conf.d \
    /etc/NetworkManager/conf.d /etc/sddm.conf.d /etc/firefox/policies \
    /etc/tlp.d /etc/conf.d/snapper /etc/snapper/configs \
    /etc/default/btrfsmaintenance /etc/smartd.conf /etc/nsswitch.conf \
    /etc/xdg/reflector; do
    backup_file "$f"
done
[ "$DRY_RUN" = 1 ] || ok "Backups stored in $BACKUP_DIR"

as_user() { sudo -u "$TARGET_USER" "$@"; }

# Clone an AUR package, build it as the target user, then install as root.
# Avoids yay's internal sudo (which cannot prompt: stdin is /dev/null).
aur_install() {
    local pkg="$1"
    local base="/tmp/aur-build"
    local dir="$base/$pkg"

    if pacman -Q "$pkg" >/dev/null 2>&1; then
        ok "$pkg already installed."
        return 0
    fi
    if [ "$DRY_RUN" = 1 ]; then
        info "[dry-run] would build and install AUR package: $pkg"
        return 0
    fi

    run as_user mkdir -p "$base"
    run rm -rf "$dir"
    run as_user git clone --depth=1 "https://aur.archlinux.org/${pkg}.git" "$dir" \
        || { fail "Could not clone AUR package: $pkg"; return 0; }
    ( cd "$dir" && run as_user makepkg --noconfirm ) \
        || { fail "makepkg failed for AUR package: $pkg"; rm -rf "$dir"; return 0; }
    run pacman -U --noconfirm --needed "$dir"/*.pkg.tar.zst \
        || fail "Could not install AUR package: $pkg"
    run rm -rf "$dir"
}

# ==============================================================================
# 1. PACMAN CONFIGURATION, MIRRORS & MULTILIB
# ==============================================================================
info "Configuring /etc/pacman.conf (Color, ParallelDownloads, multilib)..."

run sed -i 's/^#Color$/Color/' /etc/pacman.conf
grep -q '^Color$' /etc/pacman.conf || run sed -i '/^\[options\]/a Color' /etc/pacman.conf

run sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
grep -q '^ParallelDownloads' /etc/pacman.conf || run sed -i '/^\[options\]/a ParallelDownloads = 10' /etc/pacman.conf

run sed -i 's/^#ILoveCandy$/ILoveCandy/' /etc/pacman.conf

# Enable [multilib] for 32-bit Steam / Wine / Vulkan
if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
    run sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/ s/^#//' /etc/pacman.conf
fi
grep -q '^\[multilib\]' /etc/pacman.conf && ok "[multilib] enabled." || fail "Could not enable [multilib]"

run chmod 0644 /etc/pacman.conf

info "Installing bootstrap tools and reflector..."
run pacman -S --needed --noconfirm base-devel git curl wget cabextract btrfs-progs reflector \
    || fail "Bootstrap package install failed"

info "Ranking HTTPS mirrors (backup kept in $BACKUP_DIR)..."
if command -v reflector >/dev/null 2>&1 && [ "$DRY_RUN" = 0 ]; then
    reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist \
        || warn "reflector failed; keeping the existing mirrorlist"
fi

info "Writing the reflector timer configuration..."
cat <<'EOF' | apply /etc/xdg/reflector/reflector.conf
--save /etc/pacman.d/mirrorlist
--protocol https
--latest 20
--sort rate
#--country India
EOF

info "Synchronizing repositories and upgrading the system..."
run pacman -Syu --noconfirm || fail "System upgrade failed"

# ==============================================================================
# 2. AUR HELPER (yay-bin)
# ==============================================================================
if command -v yay >/dev/null 2>&1 || command -v paru >/dev/null 2>&1; then
    ok "AUR helper already present."
elif [ "$TARGET_USER" = "root" ]; then
    warn "Skipping yay-bin build (no normal sudo user)."
else
    info "Building yay-bin from the AUR..."
    aur_install yay-bin
    command -v yay >/dev/null 2>&1 && ok "yay-bin installed."
fi

# ==============================================================================
# 3. LEAN PLASMA 6 + DEV + GRAPHICS + CODECS + AUDIO
# ==============================================================================
info "Installing the curated package set (this is the long step)..."

PACKAGES=(
    # --- Minimal Plasma 6: plasma-desktop, not plasma-meta ---
    plasma-desktop plasma-workspace plasma-nm plasma-pa
    kscreen kwin bluedevil
    sddm sddm-kcm breeze breeze-gtk kde-gtk-config
    xdg-desktop-portal-kde xdg-desktop-portal-gtk qt6-wayland
    kwallet kwallet-pam kwalletmanager plasma-browser-integration
    dolphin konsole kate gwenview spectacle ark
    kdegraphics-thumbnailers ffmpegthumbs kimageformats
    kio-extras kio-admin dolphin-plugins plasma-systemmonitor
    print-manager

    # --- Build toolchain & languages ---
    cmake ninja clang gdb cpupower
    python python-pip python-virtualenv
    jdk-openjdk
    go rust
    fnm

    # --- AMD Ryzen 3500U (Picasso / Vega 8) + CPU microcode ---
    amd-ucode
    mesa lib32-mesa
    vulkan-radeon lib32-vulkan-radeon vulkan-tools
    libva libva-utils

    # --- Multimedia codec suite ---
    ffmpeg
    gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly
    gst-libav gst-plugin-va
    dav1d libheif libavif libjxl webp-pixbuf-loader
    mpv

    # --- Audio: PipeWire, 32-bit support, laptop firmware ---
    pipewire wireplumber pipewire-audio pipewire-pulse pipewire-alsa
    lib32-pipewire
    sof-firmware alsa-ucm-conf alsa-utils
    bluez-utils

    # --- Daily drivers ---
    firefox qbittorrent libreoffice-fresh
    7zip unzip xdg-user-dirs

    # --- Printing (socket-activated) ---
    cups

    # --- Power management (TLP replaces power-profiles-daemon) ---
    tlp tlp-pd lm_sensors

    # --- Snapshots, rollback and Btrfs maintenance ---
    snapper snap-pac grub-btrfs inotify-tools btrfs-assistant btrfsmaintenance

    # --- Audio effects for the laptop speakers ---
    easyeffects lsp-plugins-lv2 calf

    # --- Security and storage diagnostics ---
    apparmor arch-audit smartmontools nvme-cli informant

    # --- Network discovery and lean system services ---
    ufw earlyoom networkmanager
    cloudflared
    zram-generator pacman-contrib flatpak fwupd
    avahi nss-mdns irqbalance

    # --- Small utilities ---
    openssh rsync dosfstools mtools usbutils unrar

    # --- Optional media helpers ---
    yt-dlp pipewire-jack

    # --- Shell & documentation ---
    zsh zsh-autosuggestions zsh-syntax-highlighting zsh-completions
    zsh-history-substring-search fzf starship
    bash-completion man-db man-pages fastfetch

    # --- Fonts ---
    noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra ttf-dejavu
    ttf-carlito ttf-caladea ttf-croscore ttf-firacode-nerd
)

# TLP conflicts with power-profiles-daemon and tuned.
for p in power-profiles-daemon tuned-ppd tuned; do
    if pacman -Q "$p" >/dev/null 2>&1; then
        info "Removing $p (conflicts with TLP)..."
        run pacman -Rns --noconfirm "$p" || warn "Could not remove $p"
    fi
done

run pacman -S --needed --noconfirm "${PACKAGES[@]}" || fail "Package installation failed"

# ==============================================================================
# 4. AUR: MICROSOFT CORE FONTS
# ==============================================================================
if [ "$TARGET_USER" != "root" ]; then
    info "Installing Microsoft core fonts from the AUR..."
    aur_install ttf-ms-fonts
    run fc-cache -f || true

    info "Installing downgrade from the AUR..."
    aur_install downgrade
fi

# ==============================================================================
# 5. NODE.JS VIA FNM (latest, zero global npm packages)
# ==============================================================================
if [ "$TARGET_USER" != "root" ] && command -v fnm >/dev/null 2>&1; then
    info "Installing the latest Node.js via fnm..."
    run as_user bash -c '
        eval "$(fnm env --shell bash)"
        fnm install --latest
        LATEST="$(fnm ls | grep -oE "v[0-9]+\.[0-9]+\.[0-9]+" | sort -V | tail -1)"
        [ -n "$LATEST" ] && fnm default "$LATEST"
    ' || fail "Node.js installation via fnm failed"
fi

# ==============================================================================
# 6. ZSH, STARSHIP AND FZF
# ==============================================================================
if [ "$TARGET_USER" != "root" ]; then
    ZSH_BIN="$(command -v zsh || true)"
    if [ -n "$ZSH_BIN" ]; then
        info "Setting zsh as the default shell for $TARGET_USER..."
        grep -qx "$ZSH_BIN" /etc/shells || run bash -c "echo '$ZSH_BIN' >> /etc/shells"
        if [ "$(getent passwd "$TARGET_USER" | cut -d: -f7)" != "$ZSH_BIN" ]; then
            run chsh -s "$ZSH_BIN" "$TARGET_USER" || fail "chsh to zsh failed"
        fi
    else
        fail "zsh not found; skipping shell switch"
    fi

    info "Writing the ~/.zshrc setup block..."
    ZSHRC_FILE="$TARGET_HOME/.zshrc"
    if ! grep -q 'BEGIN SETUP BLOCKS' "$ZSHRC_FILE" 2>/dev/null; then
        cat <<'ZSHBLOCK' | append_file "$ZSHRC_FILE"

# BEGIN SETUP BLOCKS
# Node.js (fnm) and local binaries
export PATH="$HOME/.local/bin:$HOME/.local/share/fnm:$PATH"
if command -v fnm >/dev/null 2>&1; then
    eval "$(fnm env --use-on-cd --resolve-engines --shell zsh)"
fi

# Completion
autoload -U compinit
compinit
setopt COMPLETE_IN_WORD

# History
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt appendhistory
setopt SHARE_HISTORY

# Navigation
setopt autocd
unsetopt nomatch

# Prompt and plugins (Arch paths)
eval "$(starship init zsh)"

[ -f /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ] && source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
[ -f /usr/share/fzf/key-bindings.zsh ] && source /usr/share/fzf/key-bindings.zsh

if [ -f /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh ]; then
    source /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh
    bindkey '^[[A' history-substring-search-up
    bindkey '^[[B' history-substring-search-down
fi

# zsh-syntax-highlighting goes last: it wraps the widgets sourced above.
[ -f /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ] && source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# Ctrl + Arrow keybindings
bindkey "^[[1;5D" backward-word
bindkey "^[[1;5C" forward-word

# Ctrl + Backspace/Delete keybindings
bindkey '^H' backward-kill-word
bindkey '^[[3;5~' kill-word

# Alt + Backspace/Delete keybindings
bindkey "^[[3~" delete-char
bindkey -M emacs '^[[3;3~' kill-word

# Home/End keybindings
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line
# END SETUP BLOCKS
ZSHBLOCK
    fi
    run chown "$TARGET_USER":"$TARGET_GROUP" "$ZSHRC_FILE"
fi

# ==============================================================================
# 7. KDE PLASMA 6 DESKTOP POLISH
# ==============================================================================
if [ "$TARGET_USER" != "root" ] && command -v kwriteconfig6 >/dev/null 2>&1; then
    info "Applying KDE Plasma preferences for $TARGET_USER..."
    run mkdir -p "$TARGET_HOME/.config"

    # Dark Breeze theme on next login
    try as_user kwriteconfig6 --file kdeglobals --group General --key ColorScheme BreezeDark
    try as_user kwriteconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage org.kde.breezedark.desktop

    # Fast boot: start with an empty session instead of restoring apps
    try as_user kwriteconfig6 --file ksmserverrc --group General --key loginMode emptySession

    # Double UI animation speed
    try as_user kwriteconfig6 --file kdeglobals --group KDE --key AnimationDurationFactor 0.5

    # Super+Space opens KRunner (defaults preserved)
    try as_user kwriteconfig6 --file kglobalshortcutsrc --group krunner.desktop \
        --key _launch 'Alt+Space\tAlt+F2,Meta+Space\tAlt+Space\tAlt+F2,KRunner'

    info "Disabling the Baloo file indexer (plasma-desktop pulls it in)..."
    cat <<'EOF' | apply "$TARGET_HOME/.config/baloofilerc"
[Basic Settings]
Indexing-Enabled=false
EOF
    cat <<'EOF' | apply /etc/xdg/baloofilerc
[Basic Settings]
Indexing-Enabled=false
EOF

    run chown -R "$TARGET_USER":"$TARGET_GROUP" "$TARGET_HOME/.config"

    # Sync cursor theme into the SDDM greeter
    run mkdir -p /var/lib/sddm/.config
    if [ -f "$TARGET_HOME/.config/kcminputrc" ]; then
        run cp -f "$TARGET_HOME/.config/kcminputrc" /var/lib/sddm/.config/kcminputrc
        run chown -R sddm:sddm /var/lib/sddm/.config
    fi
    ok "KDE desktop preferences applied."
fi

# ==============================================================================
# 8. LIBREOFFICE (MS Office-like look: Colibre icons, tabbed UI, OOXML defaults)
# ==============================================================================
if [ "$TARGET_USER" != "root" ] && command -v libreoffice >/dev/null 2>&1; then
    LO_XCU="$TARGET_HOME/.config/libreoffice/4/user/registrymodifications.xcu"
    if [ ! -f "$LO_XCU" ]; then
        info "Configuring LibreOffice defaults for $TARGET_USER..."
        cat <<'EOF' | apply "$LO_XCU"
<?xml version="1.0" encoding="UTF-8"?>
<oor:items xmlns:oor="http://openoffice.org/2001/registry" xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
 <item oor:path="/org.openoffice.Office.Common/Misc"><prop oor:name="FirstRun" oor:op="fuse"><value>false</value></prop></item>
 <item oor:path="/org.openoffice.Office.Common/Misc"><prop oor:name="ShowTipOfTheDay" oor:op="fuse"><value>false</value></prop></item>
 <item oor:path="/org.openoffice.Office.Common/Misc"><prop oor:name="SymbolStyle" oor:op="fuse"><value>colibre</value></prop></item>
 <item oor:path="/org.openoffice.Office.UI.ToolbarMode"><prop oor:name="ActiveWriter" oor:op="fuse"><value>notebookbar.ui</value></prop></item>
 <item oor:path="/org.openoffice.Office.UI.ToolbarMode"><prop oor:name="ActiveCalc" oor:op="fuse"><value>notebookbar.ui</value></prop></item>
 <item oor:path="/org.openoffice.Office.UI.ToolbarMode"><prop oor:name="ActiveImpress" oor:op="fuse"><value>notebookbar.ui</value></prop></item>
 <item oor:path="/org.openoffice.Office.UI.ToolbarMode/Applications/org.openoffice.Office.UI.ToolbarMode:Application['Writer']"><prop oor:name="Active" oor:op="fuse"><value>notebookbar.ui</value></prop></item>
 <item oor:path="/org.openoffice.Office.UI.ToolbarMode/Applications/org.openoffice.Office.UI.ToolbarMode:Application['Calc']"><prop oor:name="Active" oor:op="fuse"><value>notebookbar.ui</value></prop></item>
 <item oor:path="/org.openoffice.Office.UI.ToolbarMode/Applications/org.openoffice.Office.UI.ToolbarMode:Application['Impress']"><prop oor:name="Active" oor:op="fuse"><value>notebookbar.ui</value></prop></item>
 <item oor:path="/org.openoffice.Setup/Office/Factories/org.openoffice.Setup:Factory[com.sun.star.text.TextDocument]"><prop oor:name="ooSetupFactoryDefaultFilter" oor:op="fuse"><value>MS Word 2007 XML</value></prop></item>
 <item oor:path="/org.openoffice.Setup/Office/Factories/org.openoffice.Setup:Factory[com.sun.star.sheet.SpreadSheetDocument]"><prop oor:name="ooSetupFactoryDefaultFilter" oor:op="fuse"><value>Calc MS Excel 2007 XML</value></prop></item>
 <item oor:path="/org.openoffice.Setup/Office/Factories/org.openoffice.Setup:Factory[com.sun.star.presentation.PresentationDocument]"><prop oor:name="ooSetupFactoryDefaultFilter" oor:op="fuse"><value>Impress MS PowerPoint 2007 XML</value></prop></item>
</oor:items>
EOF
        run chown -R "$TARGET_USER":"$TARGET_GROUP" "$TARGET_HOME/.config/libreoffice"
    fi
fi

# ==============================================================================
# 9. FONTS (Fira Code Nerd Font from the repos, MS fonts above, rendering)
# ==============================================================================
info "Enabling sub-pixel RGB rendering and the LCD filter..."
run ln -sf /usr/share/fontconfig/conf.avail/10-sub-pixel-rgb.conf /etc/fonts/conf.d/10-sub-pixel-rgb.conf
run ln -sf /usr/share/fontconfig/conf.avail/11-lcdfilter-default.conf /etc/fonts/conf.d/11-lcdfilter-default.conf

run fc-cache -f || true

# ==============================================================================
# 10. SYSTEM TUNING
# ==============================================================================
info "Capping the systemd journal (200M; SystemKeepFree may cap it lower)..."
cat <<'EOF' | apply /etc/systemd/journald.conf.d/99-ssd.conf
[Journal]
SystemMaxUse=200M
SystemMaxFiles=5
SyncIntervalSec=5m
EOF
run systemctl restart systemd-journald || true

info "Configuring 1:1 zstd ZRAM..."
if [ -f /etc/systemd/zram-generator.conf ]; then
    info "Replacing the installer's zram configuration with a 1:1 size."
fi
cat <<'EOF' | apply /etc/systemd/zram-generator.conf
[zram0]
zram-size = ram
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
EOF

info "Applying kernel and memory sysctls..."
cat <<'EOF' | apply /etc/sysctl.d/99-performance.conf
# Aggressive swap into fast compressed ZRAM
vm.swappiness = 180
vm.page-cluster = 0
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125

# Proton / Steam / high-memory apps
vm.max_map_count = 1048576

# Keep directory and inode caches in RAM (low value on NVMe, harmless)
vm.vfs_cache_pressure = 50

# Inotify capacity
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 8192
EOF
run sysctl --system || true

info "Configuring earlyoom (systemd-oomd stays disabled)..."
cat <<'EOF' | apply /etc/default/earlyoom
EARLYOOM_ARGS="-m 5 -s 10 -r 60 --avoid '(^|/)(init|systemd|sddm|kwin_wayland|kwin|Xwayland|pipewire|wireplumber)$' --prefer '(^|/)(Web Content|firefox|chrome|electron)$'"
EOF
run systemctl disable --now systemd-oomd.service || true
run systemctl enable earlyoom.service

info "Configuring SMART monitoring..."
cat <<'EOF' | apply /etc/smartd.conf
# Scan every SMART-capable device (Arch Wiki: S.M.A.R.T.)
DEVICESCAN -a
EOF

info "Configuring ufw..."
run ufw default deny incoming || true
run ufw default allow outgoing || true
if ! ufw status 2>/dev/null | grep -q '^Status: active'; then
    run ufw --force enable || fail "Could not enable ufw"
fi

info "Disabling boot-delaying and unused services..."
run systemctl disable NetworkManager-wait-online.service || true
if systemctl list-unit-files ModemManager.service >/dev/null 2>&1; then
    run systemctl disable --now ModemManager.service || true
fi

# ==============================================================================
# 11. SSD LONGEVITY (makepkg builds in RAM, Firefox cache in RAM)
# ==============================================================================
info "Moving makepkg builds to /tmp..."
if grep -q '^#BUILDDIR=/tmp/makepkg' /etc/makepkg.conf 2>/dev/null; then
    run sed -i 's|^#BUILDDIR=/tmp/makepkg|BUILDDIR=/tmp/makepkg|' /etc/makepkg.conf
elif ! grep -q '^BUILDDIR=' /etc/makepkg.conf 2>/dev/null; then
    run bash -c "echo 'BUILDDIR=/tmp/makepkg' >> /etc/makepkg.conf"
fi

info "Moving the Firefox cache to RAM..."
cat <<'EOF' | apply /etc/firefox/policies/policies.json
{
  "policies": {
    "Preferences": {
      "browser.cache.disk.enable": false,
      "browser.cache.memory.enable": true
    }
  }
}
EOF

# ==============================================================================
# 12. NETWORK (systemd-resolved + opportunistic DNS-over-TLS on Cloudflare)
# ==============================================================================
info "Configuring systemd-resolved (Cloudflare, opportunistic DoT)..."
cat <<'EOF' | apply /etc/systemd/resolved.conf.d/99-dns.conf
[Resolve]
DNS=1.1.1.1#cloudflare-dns.com 1.0.0.1#cloudflare-dns.com
FallbackDNS=1.1.1.1 1.0.0.1
DNSOverTLS=opportunistic
Domains=~.
EOF

if run systemctl enable --now systemd-resolved; then
    run rm -f /etc/resolv.conf
    run ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
else
    fail "systemd-resolved did not start; leaving /etc/resolv.conf untouched"
fi

cat <<'EOF' | apply /etc/NetworkManager/conf.d/99-systemd-resolved.conf
[main]
dns=systemd-resolved
EOF
run systemctl restart NetworkManager || true

info "Enabling mDNS hostname resolution (Avahi)..."
if ! grep -q 'mdns_minimal' /etc/nsswitch.conf 2>/dev/null; then
    run sed -i '/^hosts:/ s/\bresolve\b/mdns_minimal [NOTFOUND=return] resolve/' /etc/nsswitch.conf
fi

info "Configuring the SDDM Wayland greeter..."
cat <<'EOF' | apply /etc/sddm.conf.d/10-wayland.conf
[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell

[Wayland]
CompositorCommand=kwin_wayland --drm --no-lockscreen --no-global-shortcuts --locale1
EOF

# ==============================================================================
# 13. BTRFS FSTAB OPTIMIZATION (verified before it is written)
# ==============================================================================
optimize_btrfs_fstab() {
    local FSTAB="/etc/fstab"
    local CANDIDATE="/tmp/fstab.candidate"
    local BACKUP="/etc/fstab.bak.$(date +%s)"

    if [ "$DRY_RUN" = 1 ]; then
        info "[dry-run] would add noatime,compress=zstd:1 to Btrfs mounts in $FSTAB"
        return 0
    fi

    if ! grep -qE '^[^#].*[[:space:]]btrfs[[:space:]]' "$FSTAB"; then
        info "No Btrfs filesystem in $FSTAB. Skipping fstab tuning."
        return 0
    fi

    info "Optimizing Btrfs mount options in fstab..."
    rm -f "$CANDIDATE"

    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" =~ ^[[:space:]]*# ]] || [ -z "${line// }" ]; then
            echo "$line" >> "$CANDIDATE"
            continue
        fi

        read -r fs_spec fs_file fs_vfstype fs_mntops fs_freq fs_passno _ <<< "$line"

        if [ "$fs_vfstype" = "btrfs" ]; then
            IFS=',' read -ra opts <<< "$fs_mntops"
            local opt_list=()
            local o
            for o in "${opts[@]}"; do
                [[ "$o" =~ ^(relatime|atime|strictatime)$ ]] && continue
                [[ "$o" =~ ^compress ]] && continue
                opt_list+=("$o")
            done

            # discard=async is the Btrfs default since kernel 6.2; fstrim.timer covers the rest.
            opt_list=("noatime" "compress=zstd:1" "${opt_list[@]}")

            local unique_opts=()
            declare -A seen=()
            for o in "${opt_list[@]}"; do
                if [ -z "${seen[$o]:-}" ]; then
                    seen["$o"]=1
                    unique_opts+=("$o")
                fi
            done
            unset seen

            local new_mntops
            new_mntops=$(IFS=,; echo "${unique_opts[*]}")

            printf '%-42s %-16s %-8s %-45s 0 0\n' \
                "$fs_spec" "$fs_file" "$fs_vfstype" "$new_mntops" >> "$CANDIDATE"
        else
            echo "$line" >> "$CANDIDATE"
        fi
    done < "$FSTAB"

    if findmnt --verify --tab-file "$CANDIDATE" >/dev/null 2>&1; then
        cp "$FSTAB" "$BACKUP"
        mv "$CANDIDATE" "$FSTAB"
        chmod 0644 "$FSTAB"
        systemctl daemon-reload >/dev/null 2>&1 || true
        mount -o remount,noatime,compress=zstd:1 / 2>/dev/null || true
        ok "fstab verified with findmnt and updated (backup: $BACKUP)."
    else
        warn "findmnt rejected the candidate fstab. Live fstab left untouched."
        rm -f "$CANDIDATE"
    fi
}
optimize_btrfs_fstab

# ==============================================================================
# 14. POWER MANAGEMENT (TLP and the ASUS battery charge limit)
# ==============================================================================
info "Configuring TLP..."
cat <<'EOF' | apply /etc/tlp.d/00-laptop.conf
# ASUS VivoBook X409DA. Stop charging at 60% to slow wear on an aged battery.
STOP_CHARGE_THRESH_BAT0=60
EOF

# TLP owns the radio kill switches.
run systemctl mask systemd-rfkill.service systemd-rfkill.socket

# ==============================================================================
# 15. BTRFS SNAPSHOTS AND ROLLBACK
# ==============================================================================
setup_snapshots() {
    if ! findmnt -no FSTYPE / | grep -q btrfs; then
        warn "Root is not Btrfs; skipping the snapper configuration."
        return 0
    fi
    if [ "$DRY_RUN" = 1 ]; then
        info "[dry-run] would create the snapper root config and snapshot timers"
        return 0
    fi

    if [ -f /etc/snapper/configs/root ]; then
        ok "The snapper root config already exists."
    elif [ -d /.snapshots ] && btrfs subvolume show /.snapshots >/dev/null 2>&1; then
        # archinstall can leave @.snapshots mounted here. Reuse that subvolume,
        # because snapper's create-config would try to make a second one and fail.
        info "Reusing the existing /.snapshots subvolume."
        mkdir -p /etc/snapper/configs
        cp /usr/share/snapper/config-templates/default /etc/snapper/configs/root
        sed -i 's|^SUBVOLUME=.*|SUBVOLUME="/"|' /etc/snapper/configs/root
        if grep -q '^SNAPPER_CONFIGS=' /etc/conf.d/snapper; then
            sed -i 's|^SNAPPER_CONFIGS=.*|SNAPPER_CONFIGS="root"|' /etc/conf.d/snapper
        else
            echo 'SNAPPER_CONFIGS="root"' >> /etc/conf.d/snapper
        fi
    else
        snapper -c root create-config / || { fail "snapper create-config failed"; return 0; }
    fi

    # Tighten whichever configs exist; archinstall may create root and home.
    # The template default is 10 hourly and 10 daily snapshots.
    for cfg in root home; do
        if [ -f "/etc/snapper/configs/$cfg" ]; then
            sed -i 's/^TIMELINE_LIMIT_HOURLY=.*/TIMELINE_LIMIT_HOURLY="5"/' "/etc/snapper/configs/$cfg"
            sed -i 's/^TIMELINE_LIMIT_DAILY=.*/TIMELINE_LIMIT_DAILY="7"/' "/etc/snapper/configs/$cfg"
        fi
    done

    if snapper -c root list >/dev/null 2>&1; then
        ok "Snapper is active: pre/post snapshots on every pacman transaction."
    else
        fail "The snapper root config is not usable."
    fi
}
setup_snapshots

# ==============================================================================
# 16. APPARMOR
# ==============================================================================
add_kernel_param() {
    local param="$1"
    if [ -f /etc/default/grub ] && grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub; then
        if ! grep -q "$param" /etc/default/grub; then
            run sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"|GRUB_CMDLINE_LINUX_DEFAULT=\"\1 $param\"|" /etc/default/grub
        fi
    fi
    if [ -f /etc/kernel/cmdline ] && ! grep -q "$param" /etc/kernel/cmdline; then
        run bash -c "echo ' $param' >> /etc/kernel/cmdline"
    fi
    local entry
    for entry in /boot/loader/entries/*.conf; do
        [ -f "$entry" ] || continue
        if ! grep -q "$param" "$entry"; then
            run sed -i "s|^options \(.*\)|options \1 $param|" "$entry"
        fi
    done
}

info "Enabling AppArmor as the default LSM..."
if [ "$DRY_RUN" = 1 ] || [ -f /etc/default/grub ] || [ -f /etc/kernel/cmdline ] || compgen -G "/boot/loader/entries/*.conf" >/dev/null; then
    add_kernel_param "lsm=landlock,lockdown,yama,integrity,apparmor,bpf"
else
    warn "No kernel command line found; add lsm=landlock,lockdown,yama,integrity,apparmor,bpf manually."
fi

# ==============================================================================
# 17. BOOT (AMD microcode, initramfs, bootloader)
# ==============================================================================
if [ "$DRY_RUN" = 1 ] || pacman -Q amd-ucode >/dev/null 2>&1; then
    info "Ensuring the microcode hook is enabled and rebuilding the initramfs..."
    if [ -f /etc/mkinitcpio.conf ] && ! grep -qE '^HOOKS=.*microcode' /etc/mkinitcpio.conf; then
        run sed -i 's/^HOOKS=(\(.*\))/HOOKS=(microcode \1)/' /etc/mkinitcpio.conf
    fi
    run mkinitcpio -P || fail "mkinitcpio failed"
else
    warn "amd-ucode is not installed; skipping the initramfs rebuild."
fi

info "Setting the bootloader timeout..."
if [ -f /etc/default/grub ] && command -v grub-mkconfig >/dev/null 2>&1; then
    if grep -q '^GRUB_TIMEOUT=' /etc/default/grub; then
        run sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=2/' /etc/default/grub
    else
        run bash -c "echo 'GRUB_TIMEOUT=2' >> /etc/default/grub"
    fi
    run grub-mkconfig -o /boot/grub/grub.cfg || fail "grub-mkconfig failed"
elif [ -f /boot/loader/loader.conf ]; then
    info "systemd-boot detected."
    if grep -q '^timeout' /boot/loader/loader.conf; then
        run sed -i 's/^timeout.*/timeout 2/' /boot/loader/loader.conf
    else
        run bash -c "echo 'timeout 2' >> /boot/loader/loader.conf"
    fi
else
    warn "Neither GRUB nor systemd-boot detected; skipping the bootloader step."
fi

# ==============================================================================
# 15. FLATPAK & FIRMWARE
# ==============================================================================
info "Configuring Flatpak (Flathub)..."
run flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo \
    || fail "Could not add the Flathub remote"
run flatpak update -y || true

if command -v fwupdmgr >/dev/null 2>&1; then
    info "Checking for firmware updates..."
    run fwupdmgr refresh --force || true
    run fwupdmgr update -y || true
fi

# ==============================================================================
# 16. USABILITY POLISH
# ==============================================================================
info "Enabling sudo password feedback..."
cat <<'EOF' | apply /etc/sudoers.d/pwfeedback
Defaults pwfeedback
EOF
run chmod 0440 /etc/sudoers.d/pwfeedback

# ==============================================================================
# 17. ENABLE SERVICES
# ==============================================================================
info "Enabling services..."
SERVICES=(
    sddm.service
    NetworkManager.service
    systemd-resolved.service
    systemd-timesyncd.service
    tlp.service
    tlp-pd.service
    earlyoom.service
    ufw.service
    bluetooth.service
    cups.socket
    fstrim.timer
    paccache.timer
    reflector.timer
    arch-audit.timer
    smartd.service
    apparmor.service
    snapper-timeline.timer
    snapper-cleanup.timer
    btrfs-scrub.timer
    avahi-daemon.service
    irqbalance.service
    fwupd-refresh.timer
)
for svc in "${SERVICES[@]}"; do
    if [ "$DRY_RUN" = 1 ]; then
        printf '  [dry-run] enable %s\n' "$svc"
    elif systemctl enable "$svc" >/dev/null 2>&1; then
        ok "Enabled $svc"
    else
        warn "Could not enable $svc"
    fi
done

if [ -f /etc/default/grub ] && command -v grub-mkconfig >/dev/null 2>&1; then
    run systemctl enable grub-btrfsd.service || warn "Could not enable grub-btrfsd.service"
fi

run systemctl daemon-reload || true
if ! run systemctl start systemd-zram-setup@zram0.service; then
    warn "zram will activate on the next boot."
fi

# ==============================================================================
# SUMMARY
# ==============================================================================
echo ""
echo "=============================================================================="
if [ "$FAILURES" -gt 0 ]; then
    echo "Setup finished with $FAILURES non-fatal warning(s) or failure(s)."
else
    echo "Setup complete. All steps finished successfully."
fi
echo "=============================================================================="
echo "Quick verification:"
echo "  node -v                  # Active Node.js version (fnm)"
echo "  java --version           # Latest OpenJDK SDK"
echo "  vainfo                   # AMD VCN VA-API acceleration"
echo "  vulkaninfo --summary     # Radeon Vulkan"
echo "  tlp-stat -b              # Battery state and charge threshold"
echo "  snapper list             # Btrfs snapshots"
echo "  aa-status                # AppArmor profiles"
echo "  ufw status               # Firewall"
echo "  resolvectl status        # DNS-over-TLS state"
echo "  zramctl                  # Compressed swap"
echo "  findmnt /                # Btrfs mount options"
echo "  echo \$SHELL             # /usr/bin/zsh after re-login"
if [ "$DRY_RUN" = 1 ]; then
    echo ""
    echo "Dry run finished. No changes were made."
elif [ "$DO_REBOOT" = 1 ]; then
    echo ""
    echo "Rebooting to apply graphics, session, and kernel changes..."
    sync
    systemctl reboot
else
    echo ""
    echo "Reboot skipped (--no-reboot). Reboot before using the desktop."
fi
