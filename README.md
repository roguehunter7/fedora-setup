# Fedora Workstation Setup

Personal post-install setup script for a fresh Fedora Workstation (GNOME/Wayland)
install, aimed at an AMD Ryzen/Picasso laptop (amdgpu, Vega 8, VCN).

## What it does

- **Repos & upgrade** — RPM Fusion free/nonfree, Brave / VS Code / Google Cloud CLI repos; full system upgrade; full `ffmpeg`, the RPM Fusion `multimedia` group, and the `sound-and-video` group.
- **Packages** — Brave Origin, AMD VA-API/Vulkan drivers (`mesa-dri-drivers`, `mesa-va-drivers-freeworld`, `mesa-vulkan-drivers-freeworld`, `libva-utils`), mpv, GNOME Boxes, VS Code, Google Cloud CLI, LibreOffice, dev tools, Flatpak, archives and fonts.
- **System** — fstrim timer, 500M journal cap, 2s GRUB timeout, firmware updates; disables `NetworkManager-wait-online`, ModemManager, cups and abrtd.
- **Shell** — Zsh set as the login shell, with a `.zshrc` matching Ultramarine's defaults (Starship, zsh-autosuggestions, zsh-syntax-highlighting, fzf, history and keybindings), plus fnm with the latest Node.js.
- **Desktop & fonts** — GNOME dark theme, GNOME Software autostart/search disabled, Fira Code Nerd Font and MS core fonts.
- **Network** — systemd-resolved with Cloudflare/Google DNS-over-TLS, NetworkManager pointed at resolved.
- **Other** — Flatpak/Flathub with the Fedora remote removed, sudo password feedback.

## Run

One-liner:

```bash
curl -fsSL https://raw.githubusercontent.com/roguehunter7/fedora-setup/main/setup.sh | sudo bash
```

Or from a clone:

```bash
git clone https://github.com/roguehunter7/fedora-setup && cd fedora-setup
sudo ./setup.sh
```
