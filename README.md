# Fedora Sway Spin - Post-Install Setup (F44+)

A from-scratch, Sway-first bootstrap for a **fresh Fedora 44+ Sway spin** install.
Written for a tiling-WM beginner coming from GNOME, on AMD APU laptops
(amdgpu/Vega, VCN video block) — but harmless on Intel/desktops.

It deliberately does **not** touch GNOME Shell, install GNOME extensions, or apply
GNOME-specific settings that Sway ignores.

## Usage

The script changes system files, installs third-party repos and runs `dnf` —
**read it first, then run it locally** (never `curl | sudo bash`):

```bash
git clone <this-repo> && cd fedora-setup
sudo ./setup.sh
```

Optional flags:

```bash
SCX=1 sudo ./setup.sh            # sched-ext (scx_bpfland) from CachyOS COPR
MS_CORE_FONTS=1 sudo ./setup.sh  # MS core fonts (third-party RPM)
DNS_OVER_TLS=1 sudo ./setup.sh   # DNS-over-TLS for resolved
```

## What it does (in order)

1. **DNF tuning** — `max_parallel_downloads=20`, `defaultyes=True` (both dnf/dnf5 configs).
2. **Base upgrade** — full `dnf upgrade` + `core` group, official repos only.
3. **Repositories** — RPM Fusion free/nonfree; VS Code, Chrome, Google Cloud CLI
   (first-party); CachyOS COPR only behind a flag; unused Workstation NVIDIA/Steam
   repos disabled on AMD. (No Terra/unrar — RAR isn't needed day-to-day; see notes.)
4. **Multimedia swap** — full `ffmpeg` + `@multimedia` group from RPM Fusion.
5. **Consolidated install (one transaction)** —
   - **Sway stack** (idempotent on the spin): `sway-config-fedora`, portals
     (`xdg-desktop-portal-wlr` + GTK — screen sharing & file dialogs),
     `cliphist`/`wl-clipboard`, `swappy`, `pavucontrol`, `kanshi`, `dunst`
   - **AMD acceleration**: `mesa-dri-drivers` + `mesa-va-drivers-freeworld` (Fedora 44
     is Mesa 26 — the base VA-API driver now lives in `mesa-dri-drivers`; freeworld adds
     the H.264/HEVC codecs; `libva-utils` gives you `vainfo`) for VCN decode
   - **Power**: `tlp` + `tlp-rdw` (right choice for Zen+/Picasso — this APU has no
     power-profiles-daemon support)
   - Apps: Firefox (kept — the spin's Wayland-native default), **mpv** (RPM Fusion's
     `vlc` and `gstreamer1-plugin-libav` are not built for F44 yet — install VLC later
     via `flatpak install flathub org.videolan.VLC` or when RPM Fusion ships it), GNOME Boxes,
     VS Code, Chrome, LibreOffice + Carlito/Caladea, Distrobox, git, dev toolchain, Zsh
     (Node.js in F44 is the versioned `nodejs24`; Starship is not packaged in Fedora 41+
     — the zshrc block tolerates its absence)
6. **System tweaks** — laptop sysctls, Btrfs `noatime` (backup kept), fstrim timer,
   journal cap, GRUB timeout 2s, `NetworkManager-wait-online` off, unneeded services
   disabled (not masked), fwupd firmware update.
7. **Flatpak** — Flathub added, Fedora remote removed.
8. **GTK/Qt theming** — dark mode + window buttons via gschema override; `qt6ct`/`qt5ct`.
9. **Sway user config** (write-once, never overwrites your edits) —
   - `~/.config/sway/config.d/10-usr-input.conf` — touchpad tap, natural scroll,
     middle-emo, dwt (Sway reads libinput; GNOME gsettings do **not** apply)
   - `~/.config/sway/config.d/40-usr-tools.conf` — clipboard history picker
     (`$mod+Shift+v`), swappy annotate (`$mod+Shift+Print`), `exec kanshi`
   - `~/.config/sway/environment` — `ELECTRON_OZONE_PLATFORM_HINT=auto` (native
     Wayland for VS Code/Discord/Slack/Obsidian), `QT_QPA_PLATFORMTHEME=qt6ct`
   - `~/.config/kanshi/config` — display-profile template
10. **Fonts** — Fira Code Nerd Font (user-local), Carlito/Caladea, optional MS core fonts.
11. **Node toolchain** — TypeScript, `typescript-language-server`, Reasonix CLI
    **as the user** (installs into `~/.local/bin`, no root-owned system globals).
12. **Shell** — Zsh default + syntax-highlighting/autosuggestions/Starship, sudo
    password feedback.
13. **DNS** — systemd-resolved with Cloudflare/Google, optional DoT — run **last**
    so the network restart can't interrupt earlier steps.

## Notes for the 3500U / AMD laptop

- VCN 1.0 decodes H.264/HEVC/VP9 in hardware; **AV1 is software-decoded** on this
  GPU generation — fine at 1080p in Firefox.
- TLP vs power-profiles-daemon: install only TLP (PPD has no profiles for Zen+).
- WiFi on these boards is often Realtek RTL8821CE — supported in-tree
  (`rtw88_8821ce`) on current Fedora kernels, no DKMS needed.
- Chrome on Wayland: the script sets Electron's ozone hint, but Chrome needs its
  own flag — edit `/usr/share/applications/google-chrome.desktop` `Exec=` to add
  `--ozone-platform-hint=auto`, or run `google-chrome --ozone-platform-hint=auto`.
- **RAR archives**: Fedora's `7zip` ships with RAR support disabled (license), and
  `unrar` lives only in third-party repos — so if you ever receive a `.rar`, install
  `unar` from the **official** Fedora repos: `sudo dnf install unar` (extracts
  RAR4/RAR5). No repo or flag needed.

## Post-run

Reboot, pick the **Sway** session, then verify:

```bash
swaymsg -t get_outputs     # display names/resolution (used by kanshi profiles)
swaymsg -t get_inputs      # touchpad tap/natural scroll active
vainfo                     # VCN 1.0 enumeration
systemctl status tlp --no-pager | head -3
```

If notifications never appear: `systemctl --user enable --now dunst` (dunst is
D-Bus-activatable in the spin; one-time nudge sometimes needed).
