# Arch Linux Laptop Setup

Two phases for an AMD Ryzen/Picasso laptop (amdgpu, Vega 8, VCN): install Arch with
`archinstall`, then run the setup script in this repo for a lean KDE Plasma 6 desktop
and the system tuning.

## Phase 1: install Arch with archinstall

Boot the Arch ISO in UEFI mode with Secure Boot off and run the guided installer:

```bash
archinstall
```

Use the default flow and answer the prompts. Reboot when the installer finishes.

Phase 2 adapts to whatever the installer produced: it detects GRUB or systemd-boot,
replaces the installer's zram configuration with a 1:1 size, and installs its own minimal
Plasma 6 set regardless of the desktop profile you chose.

### Choices worth making in the installer

None of these are required for the script to run, but each changes the result.

- **Disk** — `nvme0n1` only. `sda` is a separate 465 GB data disk, and nothing in this repo touches it.
- **Filesystem** — Btrfs, compression on, mount option `noatime,compress=zstd:1`. Compression enabled at install time also compresses the base system; enabling it later only affects new files.
- **Snapshots** — in the Btrfs options pick **snapper**, not Timeshift. archinstall then creates `root` (`/`) and `home` (`/home`) snapper configs, enables the timeline and cleanup timers, and with GRUB it installs `grub-btrfs` and `inotify-tools` and enables `grub-btrfsd`. This script adds `snap-pac`, which archinstall does not install, and tightens both timelines.
- **Bootloader** — GRUB. The snapshot menu depends on it.
- **Swap** — off. The script owns zram. If you leave it on, your `zram-generator.conf` is backed up and replaced with a 1:1 configuration.
- **Profile** — Minimal. The KDE profile installs `plasma-meta`, which this repo avoids on purpose.
- **Kernels** — `linux` and `linux-lts`. The second kernel is cheap insurance on a rolling release.
- **Audio** — pipewire. **Network** — NetworkManager. **NTP** — on.
- **User** — your account in `wheel`, with sudo.
- **Additional packages** — `git curl`. archinstall installs only `base`, `sudo`, `linux-firmware`, `mkinitcpio`, the kernel and `amd-ucode`, so without `curl` the one-liner in phase 2 fails.
- **ESP** — 1 GiB if it asks for a size. 512 MiB is enough for GRUB with standard kernels.
- **Timezone, keymap, locale** — set them here; the script does not touch them.

## Phase 2: run the setup script

If you did not add `git` and `curl` in the installer, add them first:

```bash
sudo pacman -S --needed git curl
```

Then clone and run it:

```bash
git clone https://github.com/roguehunter7/linux-laptop-setup && cd linux-laptop-setup
sudo ./setup.sh
```

Or without cloning:

```bash
curl -fsSL https://raw.githubusercontent.com/roguehunter7/linux-laptop-setup/main/setup.sh | sudo bash
```

Options:

- `--dry-run` prints every action without installing or writing anything.
- `--no-reboot` skips the reboot at the end.
- `-h`, `--help` shows usage.

The script reboots when it finishes so the graphics, session and kernel changes take
effect. Hibernation is not supported: swap is zram only.

Every file it may overwrite is copied to `/var/backups/arch-setup-<timestamp>/` first,
and the run is logged to `/var/log/arch-setup-<timestamp>.log`.

### What it does

- **Repos and mirrors** — pacman color and parallel downloads, `[multilib]`, reflector mirror ranking, full system upgrade.
- **Packages** — a curated set instead of `plasma-meta`: plasma-desktop, KWin, SDDM, Dolphin, Kate, Gwenview, Spectacle, Ark, print-manager, PipeWire with 32-bit support, SOF and ALSA firmware, AMD VA-API and Vulkan drivers, the dev toolchain, Python, Go, Rust, the latest OpenJDK SDK, Node.js through fnm, Firefox, qBittorrent, LibreOffice, Flatpak.
- **System** — 1:1 zstd zram, earlyoom, ufw with incoming denied, journald capped at 200M, fstrim and paccache timers, 2s GRUB timeout, AMD microcode through mkinitcpio, fwupd with its refresh timer, and `smartd` scanning every SMART-capable device.
- **Storage** — Btrfs root remounted with `noatime,compress=zstd:1` after `findmnt --verify` accepts the new fstab, makepkg builds in `/tmp`, Firefox disk cache disabled.
- **Desktop** — dark Breeze, empty session on login, doubled animation speed, Super+Space for KRunner, Baloo indexing off, SDDM on Wayland, LibreOffice with Colibre icons, tabbed UI and OOXML save defaults.
- **Shell and fonts** — zsh as the login shell with Starship, autosuggestions, syntax highlighting, history substring search, completions and fzf; Fira Code Nerd Font from the repos, Microsoft core fonts, and sub-pixel RGB rendering with the LCD filter turned on.
- **Network** — systemd-resolved on Cloudflare with opportunistic DNS-over-TLS, NetworkManager pointed at resolved, systemd-timesyncd, Avahi with `nss-mdns` for `.local` discovery, and `cloudflared` for tunnels.
- **Power** — TLP with a 60% charge limit for this laptop's battery, radio kill-switch handling and `lm_sensors`. `power-profiles-daemon` is removed; `tlp-pd` provides the D-Bus power profiles KDE expects.
- **Snapshots** — `snapper` and `snap-pac` take a pre/post snapshot of `/` on every pacman transaction, `grub-btrfs` lists them in the GRUB menu, `btrfs-assistant` is the GUI, and `btrfs-scrub.timer` runs monthly scrubs.
- **Security** — AppArmor enabled as a default LSM via the kernel command line, `arch-audit.timer`, `smartd`, and ufw.
- **Maintenance** — `informant` holds pacman until you have read the Arch news, `downgrade` (AUR) rolls a package back, `arch-audit` reports advisories, `smartmontools` and `nvme-cli` cover the SSD.
- **Audio** — `easyeffects` with the LSP and Calf plugin sets for the laptop speakers.
- **Utilities** — `openssh`, `rsync`, `dosfstools`, `mtools`, `usbutils`, `unrar`, `yt-dlp`, `pipewire-jack`, and `irqbalance`. Mirror ranking is pinned by `/etc/xdg/reflector/reflector.conf` so the timer does not pick random worldwide mirrors.

### Requirements

An installed Arch system with UEFI boot, an existing sudo user, and network access.
GRUB and systemd-boot are both handled. TLP replaces `power-profiles-daemon`, which the
script removes. The Btrfs mount and snapshot setup is skipped on other filesystems.
Written for AMD graphics; it does nothing useful on NVIDIA or Intel machines. It does not
partition disks, install a bootloader, or create users.

### Verify after reboot

```bash
vainfo                  # VA-API on Vega 8
vulkaninfo --summary    # RADV Vulkan
zramctl                 # compressed swap
findmnt /               # Btrfs mount options
resolvectl status       # DNS-over-TLS state
ufw status              # firewall active
tlp-stat -b             # battery state and the 60% charge limit
snapper list            # pre/post snapshots
aa-status               # AppArmor profiles
arch-audit              # security advisories
node -v                 # Node.js through fnm
java --version          # latest OpenJDK SDK
```

### Notes

- **Informant blocks pacman on purpose.** Once installed, `pacman -Syu` stops if there is
  unread Arch news. Run `informant list` to see the items, then `informant read` to mark
  them read. A re-run of this script will hit that block until you do.
- **Rollback.** `snapper list` shows the snapshots. After a bad upgrade, pick a pre-upgrade
  entry under the GRUB snapshots submenu to boot it. `snap-pac` creates the pair around
  every pacman transaction.
- **Secure Boot is not automated.** `sbctl` can set it up, but the firmware must be put
  into Setup Mode by hand and a half-finished job leaves the machine unbootable. If you
  want it: `sbctl create-keys`, `sbctl enroll-keys -m`, then sign the kernel and the GRUB
  EFI binary and regenerate the bootloader configuration. See the Arch Wiki page on
  Secure Boot.
- **Hibernation is not configured**, because swap is zram only.
