# Arch Linux Laptop Setup

Two phases for an AMD Ryzen/Picasso laptop (amdgpu, Vega 8, VCN): install Arch with
`archinstall`, then run the setup script in this repo for a lean KDE Plasma 6 desktop
and the system tuning.

## Phase 1: install Arch with archinstall

Boot the Arch ISO in UEFI mode with Secure Boot off and run the guided installer:

```bash
archinstall
```

Use the default flow and answer the prompts. Nothing else is needed before or after it.
Reboot when the installer finishes.

Phase 2 adapts to whatever the installer produced: it detects GRUB or systemd-boot,
replaces the installer's zram configuration with a 1:1 size, and installs its own minimal
Plasma 6 set regardless of the desktop profile you chose.

## Phase 2: run the setup script

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
- **System** — 1:1 zstd zram, earlyoom, ufw with incoming denied, journald capped at 200M, fstrim and paccache timers, 2s GRUB timeout, AMD microcode through mkinitcpio, fwupd.
- **Storage** — Btrfs root remounted with `noatime,compress=zstd:1` after `findmnt --verify` accepts the new fstab, makepkg builds in `/tmp`, Firefox disk cache disabled.
- **Desktop** — dark Breeze, empty session on login, doubled animation speed, Super+Space for KRunner, Baloo indexing off, SDDM on Wayland, LibreOffice with Colibre icons, tabbed UI and OOXML save defaults.
- **Shell and fonts** — zsh as the login shell with Starship, autosuggestions, syntax highlighting and fzf; Fira Code Nerd Font and Microsoft core fonts.
- **Network** — systemd-resolved on Cloudflare with opportunistic DNS-over-TLS, NetworkManager pointed at resolved, systemd-timesyncd.

### Requirements

An installed Arch system with UEFI boot, an existing sudo user, and network access.
GRUB and systemd-boot are both handled. The Btrfs mount tuning is skipped on other
filesystems. Written for AMD graphics; it does nothing useful on NVIDIA or Intel
machines. It does not partition disks, install a bootloader, or create users.

### Verify after reboot

```bash
vainfo                  # VA-API on Vega 8
vulkaninfo --summary    # RADV Vulkan
zramctl                 # compressed swap
findmnt /               # Btrfs mount options
resolvectl status       # DNS-over-TLS state
ufw status              # firewall active
node -v                 # Node.js through fnm
java --version          # latest OpenJDK SDK
```
