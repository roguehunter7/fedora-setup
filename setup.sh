#!/usr/bin/env bash
# ==============================================================================
# Fedora Post-Install Setup Bootstrapper
# ==============================================================================
# This script automates system optimization, repository configurations, package
# management, GNOME customizations, and development tool installs on Fedora.
# ==============================================================================

{
set -euo pipefail
FAILURES=0

# Ensure script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run with root privileges (sudo)." >&2
    exit 1
fi

# Redirect standard input from /dev/null to prevent commands from swallowing the script when piped (e.g. curl | bash)
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

echo "--> Target User: $TARGET_USER"
echo "--> Target Home: $TARGET_HOME"

# ==============================================================================
# PACKAGE MANAGER OPTIMIZATIONS (DNF / DNF5) & SYSTEM UPGRADE
# ==============================================================================
configure_dnf_speedups() {
    local conf_file="$1"
    [ -f "$conf_file" ] || return 0
    echo "--> Configuring DNF speedups in $conf_file..."
    for opt in max_parallel_downloads=20 defaultyes=True; do
        local key="${opt%%=*}" val="${opt#*=}"
        sed -i "/^$key[[:space:]]*=/d" "$conf_file"
        sed -i "/^\[main\]/a $key = $val" "$conf_file"
    done
    chmod 0644 "$conf_file"
}

configure_dnf_speedups "/etc/dnf/dnf.conf"
configure_dnf_speedups "/etc/dnf5/dnf.conf"

# ==============================================================================
# REMOVE UNWANTED DEFAULT APPLICATIONS
# ==============================================================================
echo "--> Uninstalling Firefox..."
dnf remove -y 'firefox*' || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }
echo "--> Upgrading all system packages..."
dnf upgrade -y
echo "--> Upgrading the core package group..."
dnf group upgrade core -y || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }

echo "--> Refreshing firmware update metadata and installing updates..."
if command -v fwupdmgr >/dev/null 2>&1; then
    fwupdmgr refresh --force || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }
    fwupdmgr update -y || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }
fi

# ==============================================================================
# REPOSITORIES SETUP
# ==============================================================================
FEDORA_VERSION=$(rpm -E %fedora)
echo "--> Installing RPM Fusion Free and Nonfree repositories..."
dnf install -y "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm"
dnf install -y "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm"

echo "--> Adding third-party repositories..."
# Terra repository
cat <<EOF > /etc/yum.repos.d/terra.repo
[terra]
name=Terra \$releasever
baseurl=https://repos.fyralabs.com/terra\$releasever
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://repos.fyralabs.com/terra\$releasever/key.asc
skip_if_unavailable=1
enabled=1
EOF

# VS Code repository
cat <<EOF > /etc/yum.repos.d/vscode.repo
[vscode]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
enabled=1
EOF

# Google Chrome repository
cat <<EOF > /etc/yum.repos.d/google-chrome.repo
[google-chrome]
name=Google Chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/\$basearch
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
enabled=1
EOF

# Google Cloud CLI repository
cat <<EOF > /etc/yum.repos.d/google-cloud-cli.repo
[google-cloud-cli]
name=Google Cloud CLI
baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el9-\$basearch
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
enabled=1
EOF

echo "--> Enabling CachyOS COPR repository for sched-ext..."
dnf copr enable -y bieszczaders/kernel-cachyos-addons

# Disable unused workstation repositories if file exists
WORKSTATION_REPOS="/etc/yum.repos.d/fedora-workstation-repositories.repo"
if [ -f "$WORKSTATION_REPOS" ]; then
    echo "--> Disabling unused Workstation repositories (NVIDIA & Steam)..."
    for section in rpmfusion-nonfree-nvidia-driver rpmfusion-steam; do
        sed -i "/^\[$section\]/,/^\[/{s/^enabled=.*/enabled=0/}" "$WORKSTATION_REPOS"
    done
fi
# ==============================================================================
# APPLICATIONS & MULTIMEDIA SWAP (MUST RUN INDEPENDENTLY FOR ALLOWERASING)
# ==============================================================================
echo "--> Swapping ffmpeg-free with full ffmpeg..."
dnf install -y ffmpeg --allowerasing

echo "--> Installing RPM Fusion multimedia group..."
dnf group install -y "multimedia" --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin

# ==============================================================================
# CONSOLIDATED PACKAGE INSTALLATION (FASTER TRANSACTION RESOLUTION)
# ==============================================================================
echo "--> Installing all applications, runtimes, development tools, and dependencies..."
dnf install -y \
  @development-tools \
  vlc gnome-boxes gstreamer1-plugins-ugly gstreamer1-plugins-bad-freeworld gstreamer1-libav lame-libs \
  code google-chrome-stable google-cloud-cli libxcrypt-compat \
  golang nodejs python3 python3-pip python3-devel distrobox zsh zsh-syntax-highlighting zsh-autosuggestions starship \
  gnome-tweaks gnome-extensions-app gnome-shell-extension-dash-to-dock gnome-shell-extension-appindicator \
  scx-scheds scx-tools flatpak cabextract mkfontscale fontconfig mesa-va-drivers-freeworld intel-media-driver unrar p7zip p7zip-plugins \
  libreoffice google-carlito-fonts google-crosextra-caladea-fonts

# ==============================================================================
# SYSTEM OPTIMIZATIONS (SWAPPINESS & BTRFS)
# ==============================================================================
echo "--> Configuring VM swappiness, cache pressure, and power-saving sysctls..."
cat > /etc/sysctl.d/99-swappiness.conf <<'EOF'
vm.swappiness = 10
vm.vfs_cache_pressure = 50
kernel.nmi_watchdog = 0
vm.dirty_writeback_centisecs = 1500
EOF
chmod 0644 /etc/sysctl.d/99-swappiness.conf
sysctl -p /etc/sysctl.d/99-swappiness.conf >/dev/null || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }

echo "--> Enabling noatime mount option for Btrfs volumes in /etc/fstab..."
cp -a /etc/fstab /etc/fstab.bak 2>/dev/null || true
sed -i '/\sbtrfs\s/{/noatime/!s/\(subvol=[^[:space:],]*\)/\1,noatime/; s/,relatime//}' /etc/fstab
echo "--> Reloading systemd daemon to refresh mounts..."
systemctl daemon-reload

echo "--> Remounting root filesystem..."
mount -o remount / || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }

echo "--> Disabling NetworkManager-wait-online.service to speed up boot..."
systemctl disable NetworkManager-wait-online.service || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }

echo "--> Enabling weekly SSD TRIM timer..."
systemctl enable fstrim.timer || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }

echo "--> Enabling Bluetooth battery status reporting..."
if [ -f /etc/bluetooth/main.conf ]; then
    if ! grep -q '^Experimental[[:space:]]*=' /etc/bluetooth/main.conf; then
        if grep -q '^\[Policy\]' /etc/bluetooth/main.conf; then
            sed -i '/^\[Policy\]/a Experimental=true' /etc/bluetooth/main.conf
        else
            printf '\n[Policy]\nExperimental=true\n' >> /etc/bluetooth/main.conf
        fi
    fi
    systemctl restart bluetooth || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }
fi

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
    grub2-mkconfig -o /etc/grub2-efi.cfg >/dev/null 2>&1 || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }
fi

echo "--> Masking unneeded services (ModemManager, cups, abrtd) if present..."
for svc in ModemManager cups abrtd; do
    systemctl list-unit-files "$svc.service" >/dev/null 2>&1 && systemctl mask --now "$svc.service" >/dev/null 2>&1 || true
done

# ==============================================================================
# GNOME CONFIGURATIONS (SYSTEM-WIDE DEFAULTS)
# ==============================================================================
echo "--> Configuring GNOME system-wide defaults (Dark Mode, Window Buttons, Extensions)..."

cat > /usr/share/glib-2.0/schemas/99-fedora-setup.gschema.override <<'EOF'
[org.gnome.desktop.interface]
color-scheme='prefer-dark'

[org.gnome.desktop.wm.preferences]
button-layout='appmenu:minimize,maximize,close'

[org.gnome.shell]
enabled-extensions=['dash-to-dock@micxgx.gmail.com', 'appindicatorsupport@rgcjonas.gmail.com']
EOF

echo "--> Compiling GLib schemas..."
glib-compile-schemas /usr/share/glib-2.0/schemas/ || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }

echo "--> Disabling GNOME Software autostart and search provider..."
if [ "$TARGET_USER" != "root" ]; then
    sudo -u "$TARGET_USER" mkdir -p "$TARGET_HOME/.config/autostart"
    if [ -f /usr/share/applications/org.gnome.Software.desktop ]; then
        sudo -u "$TARGET_USER" cp /usr/share/applications/org.gnome.Software.desktop "$TARGET_HOME/.config/autostart/"
        if ! grep -q 'X-GNOME-Autostart-enabled=false' "$TARGET_HOME/.config/autostart/org.gnome.Software.desktop" 2>/dev/null; then
            echo "X-GNOME-Autostart-enabled=false" | sudo -u "$TARGET_USER" tee -a "$TARGET_HOME/.config/autostart/org.gnome.Software.desktop" >/dev/null
        fi
    fi
    sudo -u "$TARGET_USER" dbus-run-session gsettings set org.gnome.desktop.search-providers disabled "['org.gnome.Software.desktop']" || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }
fi

echo "--> Applying GNOME desktop polish (battery %, night light, tap-to-click, pinned apps)..."
if [ "$TARGET_USER" != "root" ]; then
    sudo -u "$TARGET_USER" dbus-run-session gsettings set org.gnome.desktop.interface show-battery-percentage true || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }
    sudo -u "$TARGET_USER" dbus-run-session gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled true || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }
    sudo -u "$TARGET_USER" dbus-run-session gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }
    sudo -u "$TARGET_USER" dbus-run-session gsettings set org.gnome.shell favorite-apps "['org.gnome.Nautilus.desktop', 'google-chrome.desktop', 'code.desktop']" || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }
fi

# ==============================================================================
# PERFORMANCE SCHEDULER & FLATPAK
# ==============================================================================
echo "--> Configuring sched-ext (SCX) to use scx_bpfland..."
mkdir -p /etc/default
echo "SCX_SCHEDULER=scx_bpfland" > /etc/default/scx

echo "--> Enabling and starting sched-ext (SCX) service..."
systemctl enable --now scx_loader || systemctl enable --now scx || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }

echo "--> Setting up Flatpaks (Flathub repo + update)..."
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }
if flatpak remote-list | grep -q '^fedora'; then
    flatpak remote-delete fedora || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }
fi
flatpak update -y || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }

# ==============================================================================
# LIBREOFFICE MICROSOFT COMPATIBILITY CONFIGURATION
# ==============================================================================
echo "--> Setting up LibreOffice Microsoft Office compatibility defaults..."

REGISTRY_DIR=""
for dir in /usr/lib64/libreoffice/share/registry /usr/share/libreoffice/share/registry /usr/lib/libreoffice/share/registry; do
    if [ -d "$dir" ]; then
        REGISTRY_DIR="$dir"
        break
    fi
done

if [ -n "$REGISTRY_DIR" ]; then
    cat > "$REGISTRY_DIR/microsoft-compatibility.xcd" <<'XCD'
<?xml version="1.0" encoding="UTF-8"?>
<oor:data xmlns:oor="http://openoffice.org/2001/registry" xmlns:xs="http://www.w3.org/2001/XMLSchema">
  <dependency file="main"/>
  <oor:component-data oor:name="Setup" oor:package="org.openoffice">
    <node oor:name="Office">
      <node oor:name="Factories">
        <node oor:name="org.openoffice.Setup:Factory['com.sun.star.text.TextDocument']">
          <prop oor:name="ooSetupFactoryDefaultFilter" oor:op="fuse">
            <value>MS Word 2007 XML</value>
          </prop>
        </node>
        <node oor:name="org.openoffice.Setup:Factory['com.sun.star.sheet.SpreadsheetDocument']">
          <prop oor:name="ooSetupFactoryDefaultFilter" oor:op="fuse">
            <value>MS Excel 2007 XML</value>
          </prop>
        </node>
        <node oor:name="org.openoffice.Setup:Factory['com.sun.star.presentation.PresentationDocument']">
          <prop oor:name="ooSetupFactoryDefaultFilter" oor:op="fuse">
            <value>MS PowerPoint 2007 XML</value>
          </prop>
        </node>
      </node>
    </node>
  </oor:component-data>
</oor:data>
XCD
    echo "Created global LibreOffice compatibility overrides at: $REGISTRY_DIR/microsoft-compatibility.xcd"
else
    echo "Warning: Could not find LibreOffice share/registry directory."
fi

# ==============================================================================
# FONTS (NERD FONTS & MICROSOFT CORE FONTS)
# ==============================================================================
if [ "$TARGET_USER" != "root" ]; then
    echo "--> Creating local fonts directory..."
    FONT_DIR="$TARGET_HOME/.local/share/fonts"
    mkdir -p "$FONT_DIR"
    chown "$TARGET_USER":"$TARGET_GROUP" "$FONT_DIR"
    chmod 0755 "$FONT_DIR"

    if ! ls "$FONT_DIR"/*.ttf >/dev/null 2>&1; then
        echo "--> Downloading and extracting Fira Code Nerd Font..."
        sudo -u "$TARGET_USER" curl -fsSL -o "$TARGET_HOME/FiraCode.tar.xz" https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.tar.xz
        sudo -u "$TARGET_USER" tar -xf "$TARGET_HOME/FiraCode.tar.xz" -C "$FONT_DIR"
        rm -f "$TARGET_HOME/FiraCode.tar.xz"
    fi
fi

echo "--> Installing Microsoft Core Fonts installer..."
if ! rpm -q msttcore-fonts-installer >/dev/null 2>&1; then
    rpm -i --nodeps --nodigest https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }
fi

echo "--> Rebuilding font cache..."
fc-cache -f || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }

# ==============================================================================
# DEV TOOLCHAINS & LANGUAGE SERVERS
# ==============================================================================
if [ "$TARGET_USER" != "root" ]; then
    echo "--> Installing Rust via rustup..."
    sudo -u "$TARGET_USER" bash -c "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"

    echo "--> Installing rust-analyzer..."
    sudo -u "$TARGET_USER" "$TARGET_HOME/.cargo/bin/rustup" component add rust-analyzer || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }

    echo "--> Installing gopls (Go language server)..."
    sudo -u "$TARGET_USER" env HOME="$TARGET_HOME" go install golang.org/x/tools/gopls@latest || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }
fi

echo "--> Installing TypeScript, its language server, and Reasonix CLI..."
npm install -g typescript typescript-language-server reasonix || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }

# ==============================================================================
# SHELL & USABILITY POLISH
# ==============================================================================
if [ "$TARGET_USER" != "root" ]; then
    echo "--> Changing user shell to Zsh..."
    usermod -s /bin/zsh "$TARGET_USER"

    echo "--> Configuring Zsh options and plugins in .zshrc..."
    ZSHRC_FILE="$TARGET_HOME/.zshrc"
    if ! grep -q 'BEGIN SETUP BLOCKS' "$ZSHRC_FILE" 2>/dev/null; then
        cat >> "$ZSHRC_FILE" <<'ZSHBLOCK'

# BEGIN SETUP BLOCKS
# Initialize Starship Prompt
eval "$(starship init zsh)"

# Enable syntax highlighting and autosuggestions from DNF packages
source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh

# Ensure local bin and toolchain binaries are in PATH
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/go/bin:$PATH"

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
# DNS (SYSTEMD-RESOLVED) — DONE LAST SO A NETWORK RESTART CANNOT INTERRUPT EARLIER STEPS
# ==============================================================================
echo "--> Configuring systemd-resolved DNS (Cloudflare 1.1.1.1/1.0.0.1, fallback Google 8.8.8.8)..."
mkdir -p /etc/systemd/resolved.conf.d
cat > /etc/systemd/resolved.conf.d/99-dns.conf <<'EOF'
[Resolve]
DNS=1.1.1.1 1.0.0.1
FallbackDNS=8.8.8.8
DNSOverTLS=yes
EOF
systemctl enable --now systemd-resolved || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }
mkdir -p /etc/NetworkManager/conf.d
printf '[main]\ndns=systemd-resolved\n' > /etc/NetworkManager/conf.d/99-systemd-resolved.conf
systemctl restart NetworkManager || { FAILURES=$((FAILURES+1)); echo "  !! FAILED - see above"; }

if [ "$FAILURES" -gt 0 ]; then
    echo "Setup finished with $FAILURES failed step(s) - look for '!!' markers above."
    echo "=============================================================================="
else
    echo "Setup complete! Please restart your system or log out and back in to apply all updates."
    echo "=============================================================================="
fi
}
