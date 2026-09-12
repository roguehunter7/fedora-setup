# Fedora Workstation (GNOME) - Post-Install Setup

Sets up a fresh Fedora Workstation (GNOME/Wayland) install.

## What the script does

1. Enables DNF parallel downloads (`max_parallel_downloads = 10`).
2. Runs a full system upgrade.
3. Adds the RPM Fusion free/nonfree, Brave, VS Code and Google Cloud CLI repositories; disables the duplicate Workstation NVIDIA/Steam repos.
4. Swaps `ffmpeg-free` for full `ffmpeg` and installs the RPM Fusion `multimedia` group.
5. Removes Firefox.
6. Installs Brave Origin, the AMD VA-API drivers (`mesa-dri-drivers`, `mesa-va-drivers-freeworld`, `libva-utils`), mpv, GNOME Boxes, VS Code, Google Cloud CLI, LibreOffice, `@development-tools`, Python, Distrobox, git, curl, unzip, fzf, bash-completion, fuse-libs, Flatpak, cabextract, mkfontscale, fontconfig, 7zip, and the Carlito/Caladea fonts.
7. Checks for and applies firmware updates.
8. Enables the weekly fstrim timer.
9. Disables `NetworkManager-wait-online`.
10. Caps the systemd journal at 500M.
11. Sets the GRUB timeout to 2 seconds.
12. Disables ModemManager, cups and abrtd.
13. Adds Flathub, removes the stock Fedora remote, and updates Flatpaks.
14. Installs Starship.
15. Writes `~/.inputrc` for case-insensitive completion, Tab cycling and prefix history search.
16. Appends a `~/.bashrc` block: autocd, globstar, cdspell/dirspell, checkwinsize, histappend, history settings, `~/.local/bin` on PATH, fnm, fzf and Starship.
17. Installs fnm and the latest Node.js as the user.
18. Sets GNOME to prefer dark and disables the GNOME Software autostart entry and search provider.
19. Installs Fira Code Nerd Font and Microsoft Core Fonts, then rebuilds the font cache.
20. Enables sudo password feedback.
21. Configures systemd-resolved with Cloudflare/Google DNS and DNS-over-TLS, and points NetworkManager at systemd-resolved.
