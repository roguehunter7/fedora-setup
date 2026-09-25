# Fedora KDE Post Install Guide

Things to do after installing the Fedora KDE Plasma Desktop Edition. Written for an ASUS VivoBook X409DA (AMD Ryzen 5 3500U / Vega 8, NVMe, Btrfs); most steps suit any Fedora KDE machine.

Run top to bottom. Each block is copy-paste into a terminal. Reboot where told. Graphics, session, and kernel changes need it.

## DNF tuning

Speed up dnf before the first upgrade (10 parallel downloads, fastest mirror, assume yes):

```bash
sudo dnf config-manager setopt max_parallel_downloads=10 fastestmirror=True defaultyes=True
```

Check it (should print `10`, `True`, `True`):

```bash
dnf config-manager show max_parallel_downloads fastestmirror defaultyes
```

## Update

Update everything first, then reboot:

```bash
sudo dnf upgrade --refresh -y
sudo systemctl reboot
```

## RPM Fusion

Fedora leaves out non-free software (codecs, drivers, firmware) by default. Enable RPM Fusion:

```bash
sudo dnf install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
```

```bash
sudo dnf upgrade --refresh -y
```

Show RPMFusion apps in Discover:

```bash
sudo dnf update @core
```

```bash
sudo dnf install rpmfusion-*-appstream-data
```

Enable the Cisco OpenH264 repo (Firefox uses it for WebRTC calls):

```bash
sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1
```

## Multimedia

Full ffmpeg instead of the stripped `ffmpeg-free`, plus the codec complements for GStreamer apps (straight from the [RPMFusion docs](https://rpmfusion.org/Howto/Multimedia)):

```bash
sudo dnf swap ffmpeg-free ffmpeg --allowerasing || sudo dnf install -y ffmpeg
```

```bash
sudo dnf install @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
```

AMD hardware decode (H.264/H.265/VC-1 on this Vega 8 — stock Mesa leaves these out):

```bash
sudo dnf swap mesa-va-drivers mesa-va-drivers-freeworld || sudo dnf install -y mesa-va-drivers-freeworld
```

```bash
sudo dnf swap mesa-vulkan-drivers mesa-vulkan-drivers-freeworld || sudo dnf install -y mesa-vulkan-drivers-freeworld
```

## Firmware

If your system supports firmware delivery through LVFS:

```bash
fwupdmgr refresh --force
```

```bash
fwupdmgr get-devices
```

Lists devices with available updates.

```bash
fwupdmgr get-updates
```

Fetches the list of available updates.

```bash
fwupdmgr update
```

## Flatpak

Enable access to all Flathub flatpaks (skip if you ticked "Enable Third Party Repositories" on first boot):

```bash
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
```

## Extra apps

Compilers and build tools as a group:

```bash
sudo dnf group install -y development-tools
```

This installs the extra apps. The spin already ships Plasma, KWin, Dolphin, Konsole, and PipeWire, so those are not listed. (`kio-zeroconf` has no Fedora build, so it is omitted. `nss-mdns` in the list below covers `.local` discovery (it pulls in Avahi itself). Niche extras from the old script (KRfb, Skanlite, Haruna, Rust toolchain, JACK, `kfind`, KColorChooser and friends) are left out. Install them from Discover when you need them.)

```bash
sudo dnf install -y gwenview spectacle ark kdegraphics-thumbnailers ffmpegthumbs kf6-kimageformats kio-extras dolphin-plugins plasma-systemmonitor plasma-print-manager kinfocenter plasma-disks ksshaskpass filelight okular kde-partitionmanager kclock python3-pip python3-virtualenv java-latest-openjdk-devel golang mesa-dri-drivers vulkan-tools libva libva-utils dav1d libheif libavif libjxl libwebp mpv pipewire-pulseaudio pipewire-alsa alsa-sof-firmware alsa-ucm alsa-utils bluez firefox qbittorrent libreoffice 7zip unzip xdg-user-dirs cups snapper python3-dnf-plugin-snapper btrfs-assistant btrfsmaintenance easyeffects lsp-plugins calf smartmontools nvme-cli earlyoom zram-generator flatpak fwupd nss-mdns openssh rsync dosfstools mtools usbutils unrar yt-dlp zsh
```

## Battery charge limit (60%)

This ASUS exposes charge control directly, so no TLP is needed. Stop charging at 60% to slow battery wear:

```bash
echo 60 | sudo tee /sys/class/power_supply/BAT0/charge_control_end_threshold
```

Make it survive reboots:

```bash
printf 'w /sys/class/power_supply/BAT0/charge_control_end_threshold - - - - 60\n' | sudo tee /etc/tmpfiles.d/battery-charge-limit.conf >/dev/null
```

Check it (should print `60`):

```bash
cat /sys/class/power_supply/BAT0/charge_control_end_threshold
```

## Shell (zsh + Starship)

Make zsh the login shell, install the Starship prompt upstream (no Fedora package), and add the shell setup block:

```bash
chsh -s $(command -v zsh)
```

```bash
curl -sS https://starship.rs/install.sh | sh -s -- -y
```

Append this block to `~/.zshrc`. It is guarded, so re-running is safe:

```zsh
# BEGIN SETUP BLOCKS
export PATH="$HOME/.local/bin:$HOME/.local/share/fnm:$PATH"
if command -v fnm >/dev/null 2>&1; then
    eval "$(fnm env --use-on-cd --resolve-engines --shell zsh)"
fi
autoload -U compinit
compinit
setopt COMPLETE_IN_WORD
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt appendhistory
setopt SHARE_HISTORY
setopt autocd
unsetopt nomatch
eval "$(starship init zsh)"
[ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ] && source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
[ -f /usr/share/fzf/shell/key-bindings.zsh ] && source /usr/share/fzf/shell/key-bindings.zsh
[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ] && source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
bindkey "^[[1;5D" backward-word
bindkey "^[[1;5C" forward-word
bindkey '^H' backward-kill-word
bindkey '^[[3;5~' kill-word
bindkey "^[[3~" delete-char
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line
# END SETUP BLOCKS
```

## Node.js (fnm) [Optional]

Fedora ships no `fnm` package, so install it upstream, then take the latest Node:

```bash
curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell
```

```bash
export PATH="$HOME/.local/share/fnm:$PATH" && eval "$(fnm env --shell bash)" && fnm install --latest && fnm default $(fnm ls | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -1)
```

## KDE polish

Dark Breeze, empty session on login, double animation speed, Super+Space for KRunner:

```bash
kwriteconfig6 --file kdeglobals --group General --key ColorScheme BreezeDark
```

```bash
kwriteconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage org.kde.breezedark.desktop
```

```bash
kwriteconfig6 --file ksmserverrc --group General --key loginMode emptySession
```

```bash
kwriteconfig6 --file kdeglobals --group KDE --key AnimationDurationFactor 0.5
```

```bash
kwriteconfig6 --file kglobalshortcutsrc --group krunner.desktop --key _launch 'Alt+Space	Alt+F2,Meta+Space	Alt+Space	Alt+F2,KRunner'
```

Disable the Baloo file indexer:

```bash
mkdir -p ~/.config && printf '[Basic Settings]\nIndexing-Enabled=false\n' | tee ~/.config/baloofilerc >/dev/null && sudo mkdir -p /etc/xdg && printf '[Basic Settings]\nIndexing-Enabled=false\n' | sudo tee /etc/xdg/baloofilerc >/dev/null
```

Stop KClock's daemon from autostarting (alarms then only fire while KClock is open):

```bash
[ -f /etc/xdg/autostart/org.kde.kclockd-autostart.desktop ] && mkdir -p ~/.config/autostart && printf '[Desktop Entry]\nHidden=true\n' > ~/.config/autostart/org.kde.kclockd-autostart.desktop
```

Fedora uses `plasmalogin`, not SDDM, so there is no greeter config to write.

## Fonts

Sub-pixel RGB rendering with the LCD filter, then rebuild the cache:

```bash
sudo ln -sf /usr/share/fontconfig/conf.avail/10-sub-pixel-rgb.conf /etc/fonts/conf.d/10-sub-pixel-rgb.conf
```

```bash
sudo ln -sf /usr/share/fontconfig/conf.avail/11-lcdfilter-default.conf /etc/fonts/conf.d/11-lcdfilter-default.conf
```

```bash
sudo fc-cache -f
```

Metric-compatible fonts (same layout as Arial, Times, Courier, Calibri, Cambria — no EULA):

```bash
sudo dnf install -y liberation-sans-fonts liberation-serif-fonts liberation-mono-fonts google-carlito-fonts google-crosextra-caladea-fonts
```

Real Microsoft fonts [Optional]:

```bash
sudo dnf install -y lpf-mscore-fonts
```

Then follow the prompts (approves the EULA, downloads from SourceForge, builds and installs a local RPM):

```bash
lpf update mscore-fonts
```

## System tuning

Cap the journal at 200M:

```bash
sudo mkdir -p /etc/systemd/journald.conf.d && printf '[Journal]\nSystemMaxUse=200M\nSystemMaxFiles=5\nSyncIntervalSec=5m\n' | sudo tee /etc/systemd/journald.conf.d/99-ssd.conf >/dev/null && sudo systemctl restart systemd-journald
```

1:1 zstd zram (Fedora defaults to smaller lzo-rle zram; this replaces it):

```bash
printf '[zram0]\nzram-size = ram\ncompression-algorithm = zstd\nswap-priority = 100\nfs-type = swap\n' | sudo tee /etc/systemd/zram-generator.conf >/dev/null && sudo systemctl daemon-reload && sudo systemctl start systemd-zram-setup@zram0.service
```

Kernel and memory sysctls (aggressive swap into zram, Proton map count, inotify capacity):

```bash
sudo mkdir -p /etc/sysctl.d && printf 'vm.swappiness = 180\nvm.page-cluster = 0\nvm.watermark_boost_factor = 0\nvm.watermark_scale_factor = 125\nvm.max_map_count = 1048576\nvm.vfs_cache_pressure = 50\nfs.inotify.max_user_watches = 524288\nfs.inotify.max_user_instances = 8192\n' | sudo tee /etc/sysctl.d/99-performance.conf >/dev/null && sudo sysctl --system
```

earlyoom instead of systemd-oomd (this guide sets `vm.swappiness=180`, which keeps zram full — and oomd kills at 90% swap used, so oomd would fire constantly while earlyoom picks better victims):

```bash
printf 'EARLYOOM_ARGS="-m 5 -s 10 -r 60 --avoid '"'"'(^|/)(init|systemd|sddm|kwin_wayland|kwin|Xwayland|pipewire|wireplumber)$'"'"' --prefer '"'"'(^|/)(Web Content|firefox|chrome|electron)$'"'"'"\n' | sudo tee /etc/default/earlyoom >/dev/null && sudo systemctl disable --now systemd-oomd.service; sudo systemctl enable earlyoom.service
```

SMART monitoring on every capable device:

```bash
printf '# Scan every SMART-capable device\nDEVICESCAN -a\n' | sudo tee /etc/smartd.conf >/dev/null
```

Skip the boot-delaying waiter:

```bash
sudo systemctl disable NetworkManager-wait-online.service
```

## Firewall

Fedora ships `firewalld`. Use it and don't install `ufw` alongside it:

```bash
sudo systemctl enable --now firewalld
```

## DNS (Cloudflare DoT)

systemd-resolved on Cloudflare with opportunistic DNS-over-TLS:

```bash
sudo mkdir -p /etc/systemd/resolved.conf.d && printf '[Resolve]\nDNS=1.1.1.1#cloudflare-dns.com 1.0.0.1#cloudflare-dns.com\nFallbackDNS=1.1.1.1 1.0.0.1\nDNSOverTLS=opportunistic\nDomains=~.\n' | sudo tee /etc/systemd/resolved.conf.d/99-dns.conf >/dev/null && sudo systemctl enable --now systemd-resolved && sudo rm -f /etc/resolv.conf && sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
```

Point NetworkManager at resolved, then restart it:

```bash
sudo mkdir -p /etc/NetworkManager/conf.d && printf '[main]\ndns=systemd-resolved\n' | sudo tee /etc/NetworkManager/conf.d/99-systemd-resolved.conf >/dev/null && sudo systemctl restart NetworkManager
```

`nss-mdns` (in the install above) pulls in Avahi, so no action is needed.

## SSD longevity

Keep the Firefox disk cache in RAM:

```bash
sudo mkdir -p /etc/firefox/policies && printf '{"policies": {"Preferences": {"browser.cache.disk.enable": false, "browser.cache.memory.enable": true}}}\n' | sudo tee /etc/firefox/policies/policies.json >/dev/null
```

## Btrfs

The installer already sets `compress=zstd:1` on `/` and `/home`. Add `noatime` to Btrfs lines missing it (safe to re-run), then verify:

```bash
sudo sed -i -E '/[[:space:]]btrfs[[:space:]]/ { /noatime/! s/(btrfs +)([^ ]+)/\1noatime,\2/; }' /etc/fstab
```

Must pass before rebooting:

```bash
sudo findmnt --verify
```

`fstrim.timer` (enabled below) stays for `/boot`, which is ext4. The Btrfs mounts discard async on their own.

## Snapshots

Snapper takes pre/post snapshots of `/` on every dnf transaction (via `python3-dnf-plugin-snapper`, installed above). Create the configs if the installer didn't:

Skip if the installer already made it, since it errors when the config exists:

```bash
sudo snapper -c root create-config /
```

```bash
sudo snapper -c home create-config /home
```

Tighten the timelines (defaults keep 10 hourly / 10 daily):

```bash
for c in root home; do [ -f /etc/snapper/configs/$c ] && sudo sed -i 's/^TIMELINE_LIMIT_HOURLY=.*/TIMELINE_LIMIT_HOURLY="5"/; s/^TIMELINE_LIMIT_DAILY=.*/TIMELINE_LIMIT_DAILY="7"/' /etc/snapper/configs/$c; done
```

Monthly scrubs are covered by `btrfs-scrub.timer` (enabled below).

`grub-btrfs` is not in the Fedora repos, so there is no GRUB snapshot menu. Restore from a live USB if needed.

## Boot

Microcode ships via `linux-firmware`. No action is needed.

2s GRUB timeout:

```bash
sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=2/' /etc/default/grub && sudo grub2-mkconfig -o /boot/grub2/grub.cfg
```

## Sudo feedback

Show `*` while typing the sudo password:

```bash
echo 'Defaults pwfeedback' | sudo tee /etc/sudoers.d/pwfeedback >/dev/null && sudo chmod 0440 /etc/sudoers.d/pwfeedback
```

## Services

Enable everything in one go (the rest — display manager, NetworkManager, firewalld, Bluetooth, printing, trim, smartd, Avahi — ships enabled):

```bash
sudo systemctl enable systemd-resolved.service earlyoom.service snapper-timeline.timer snapper-cleanup.timer btrfs-scrub.timer fwupd-refresh.timer
```

```bash
sudo systemctl reboot
```

## Verify after reboot

VA-API on Vega 8:

```bash
vainfo
```

RADV Vulkan:

```bash
vulkaninfo --summary
```

Compressed swap:

```bash
zramctl
```

Btrfs mount options:

```bash
findmnt /
```

DNS-over-TLS state:

```bash
resolvectl status
```

Firewall running:

```bash
firewall-cmd --state
```

`60` = limit active:

```bash
cat /sys/class/power_supply/BAT0/charge_control_end_threshold
```

Pre/post snapshots:

```bash
sudo snapper list
```

SELinux enforcing:

```bash
getenforce
```

Node.js through fnm:

```bash
node -v
```

Latest OpenJDK SDK:

```bash
java --version
```

`/usr/bin/zsh` after re-login:

```bash
echo $SHELL
```

## Notes

**Rollback** is native:

```bash
sudo dnf history rollback
```

```bash
sudo dnf downgrade <pkg>-<ver>
```

**Hibernation is not configured** — swap is zram only.

**KClock alarms** only fire while KClock is open (its background daemon autostart is disabled per the desktop defaults above).
