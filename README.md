# Fedora Workstation (GNOME) - Post-Install Setup

A from-scratch bootstrap for a **fresh Fedora Workstation (GNOME Wayland)**
install on an AMD Ryzen/Picasso laptop (amdgpu, Vega 8, VCN). It sets up a
Bash + Readline shell with Starship and FZF, installs **Brave Origin** as the
native RPM browser, and manages Node.js through **fnm** (no system Node, no
global npm crud).

## Usage

The script changes system files, installs third-party repos and runs `dnf` —
**read it first, then run it locally** (never `curl | sudo bash`):

```bash
git clone <this-repo> && cd fedora-setup
sudo ./setup.sh
```

If the executable bit is not set, run `sudo bash setup.sh` (or
`chmod +x setup.sh` first).

## What it does (in order)

1. **DNF speedup** — drop-in `/etc/dnf/libdnf5.conf.d/80-parallel-downloads.conf`
   with `max_parallel_downloads = 10`.
2. **Base upgrade** — full `dnf upgrade --refresh`.
3. **Repositories** — RPM Fusion free/nonfree; Brave Browser, VS Code and Google
   Cloud CLI (first-party vendor repos); duplicate Workstation NVIDIA/Steam
   sections disabled.
4. **Multimedia** — swap `ffmpeg-free` for full `ffmpeg`, install the
   RPM Fusion `multimedia` group.
5. **Core packages** — removes stock Firefox; installs Brave Origin, AMD VA-API
   acceleration (`mesa-dri-drivers`, `mesa-va-drivers-freeworld`,
   `libva-utils`), apps (mpv, GNOME Boxes, VS Code, GCLI, LibreOffice),
   dev tools, shell utilities (`fzf`, `bash-completion`), archivers/fonts,
   and Flatpak. Firmware updates via `fwupdmgr`.
6. **System tuning** — weekly SSD TRIM timer, disable
   `NetworkManager-wait-online`, 500M journal cap, GRUB timeout 2s, and
   disable ModemManager/cups/abrtd (disable, not mask).
7. **Flatpak** — add Flathub, remove the stock Fedora remote, update.
8. **Shell ergonomics** — Install Starship; write `~/.inputrc` (Tab
   menu-complete, Shift-Tab reverse, prefix history search) and a marked
   `~/.bashrc` block (autocd, globstar, cdspell, history, `~/.local/bin`,
   fnm, fzf, Starship). Write-once: later manual edits are preserved.
9. **Node via fnm** — install Fast Node Manager as the user, then the latest
   Node.js release set as default. Nothing is installed globally as root.
10. **GNOME** — prefer-dark color scheme; disable the GNOME Software autostart
    entry and its search provider.
11. **Fonts** — Fira Code Nerd Font (user-local), Microsoft Core Fonts, then
    `fc-cache -f`.
12. **Usability** — sudo password feedback (`pwfeedback`).
13. **DNS** — systemd-resolved with Cloudflare/Google and strict DNS-over-TLS;
    NetworkManager configured to use `systemd-resolved`.

## Notes / things to review before running

- **Piped installers**: Starship and fnm are installed by piping upstream
  `curl ... | sh` scripts to a shell. Review or pin them if that matters to you.
- **Microsoft Core Fonts** are installed unconditionally from a third-party
  SourceForge RPM with no signature verification, and `rpm -i` errors are
  suppressed. The metric-compatible Carlito/Caladea fonts cover LibreOffice;
  drop this step if you do not need the real MS fonts.
- **DNS-over-TLS is forced on** (`DNSOverTLS=yes`) with `#hostname` servers. Networks
  that block port 853 (some captive portals and corporate networks) will break
  name resolution. Relax it if you roam.
- There are no opt-out flags in this revision; every step runs. Comment out or
  gate steps in the script itself if you don't want them.

## Post-run

Reboot, log in to GNOME, then verify:

```bash
node -v            # active Node from fnm
npm -v             # bundled npm
brave-origin       # launch the browser
vainfo             # AMD VCN video decode (H.264/HEVC)
powerprofilesctl   # GNOME power profiles daemon
```
