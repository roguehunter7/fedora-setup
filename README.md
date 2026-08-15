# Fedora Post-Install Setup

This repository contains a unified, zero-dependency Bash script designed to automate post-installation configuration, system optimization, package management, and custom desktop/terminal modifications on a fresh installation of **Fedora Linux**.

By running this script, you can quickly bootstrap your Fedora desktop into a fully configured, high-performance development workstation.

---

## 🚀 Quick-Start One-Liner

On a fresh Fedora installation, open your terminal and run the following command to initiate the entire setup automatically:

```bash
curl -fsSL https://raw.githubusercontent.com/roguehunter7/fedora-setup/main/setup.sh | sudo bash
```

This single command fetches the setup script directly and executes it with root privileges to configure your system.

---

## What this Script Does

1. **DNF Speed Optimizations**: Configures `max_parallel_downloads=20` and `defaultyes=True` for both DNF and DNF5 to make package updates much faster.
2. **App Cleanup (Removal)**: Uninstalls the default **Firefox** browser (Chrome is the preferred browser).
3. **System-wide Package Upgrade**: Upgrades all pre-installed system packages to their latest versions, including the **core package group** (`dnf group upgrade core`).
4. **Repository Configuration**:
   - Enables **RPM Fusion (Free & Non-Free)** repositories.
   - Enables the **Terra Repository** (maintained by Fyra Labs).
   - Configures the official repositories for **Visual Studio Code**, **Google Chrome**, and the **Google Cloud CLI** (architecture-aware via `$basearch`).
   - Enables the **CachyOS COPR** repository for sched-ext.
   - Disables unused, limited third-party repositories (**NVIDIA** and **Steam** subsets) to prevent DNF metadata bloat on AMD hardware.
5. **General Linux & Storage Optimizations**:
   - **Memory Tuning**: Configures `vm.swappiness = 10`, `vm.vfs_cache_pressure = 50`, `kernel.nmi_watchdog = 0` (disables NMI watchdog), and `vm.dirty_writeback_centisecs = 1500` via a custom sysctl drop-in file (`/etc/sysctl.d/99-swappiness.conf`).
   - **Btrfs Performance Tuning**: Safely updates `/etc/fstab` to append the `noatime` option to Btrfs subvolumes, reducing write amplification on SSDs/NVMes, then remounts the root filesystem.
   - **Bluetooth Battery Reporting**: Enables BlueZ experimental features to show battery levels for connected Bluetooth devices in the GNOME Quick Settings.
   - **SSD TRIM & Lifespan**: Activates the weekly `fstrim.timer`.
   - **HDD Auto-Spindown**: Adds a `udev` rule that spins down mechanical drives using `hdparm` after 10 minutes of inactivity.
   - **Boot Speed**: Disables `NetworkManager-wait-online.service` (saves seconds on boot), caps the systemd journal at 500MB, reduces the GRUB timeout to 2 seconds, and masks unneeded services (`ModemManager`, `cups`, `abrtd`) when present.
   - **DNS**: Enables `systemd-resolved` with Cloudflare **1.1.1.1 / 1.0.0.1**, falling back to Google **8.8.8.8**, with **DNS over TLS**.
   - **Firmware**: Refreshes LVFS metadata and installs pending device firmware updates via `fwupdmgr`.
6. **GNOME Customization & Desktop Tweaks**:
   - Installs **GNOME Tweaks** and the graphical **GNOME Extensions App**.
   - Installs and enables the **Dash to Dock** and **AppIndicator** extensions.
   - Configures window controls to **enable Minimize and Maximize buttons**.
   - Sets the global system color scheme preference to **Dark Mode**.
   - Applies desktop polish via gsettings: battery percentage, night light, tap-to-click, and pinned favorite apps (Files, Chrome, VS Code).
   - Disables **GNOME Software** autostart and its search provider to save memory.
7. **Multimedia Swap & Video Acceleration**:
   - Swaps out Fedora's restricted `ffmpeg-free` for full `ffmpeg` from RPM Fusion.
   - Installs the `@multimedia` package group.
   - Installs hardware-accelerated video decoding drivers (`mesa-va-drivers-freeworld` and `intel-media-driver`).
8. **Consolidated Package Installation**: Installs all application, runtime, and development packages in a **single DNF transaction**:
   - **Applications**: VLC, GNOME Boxes, Google Chrome, Visual Studio Code, LibreOffice.
   - **Runtimes & Build Tools**: Python 3 (with pip and dev headers), Go, Node.js, Java OpenJDK, and the Fedora **Development Tools** group.
   - **Container tools**: Distrobox.
   - **System tools**: flatpak, cabextract, mkfontscale, fontconfig, hdparm, plus archive support (`unrar`, `p7zip`, `p7zip-plugins`).
9. **Performance Scheduler (sched-ext)**: Installs **SCX** from the CachyOS COPR and configures the system to use the **`scx_bpfland`** scheduler (pure-BPF, battery-friendly — ideal for laptops) for desktop responsiveness.
10. **Flatpak Integration**: Registers **Flathub**, removes the Fedora Flatpak remote, and installs **Flatseal**.
11. **Font Polish (Nerd Fonts & Microsoft Fonts)**:
    - Downloads and extracts the **Fira Code Nerd Font** into the user's local fonts directory.
    - Installs the **Microsoft TrueType Core Fonts** installer, plus metric-compatible **Carlito** and **Caladea** fonts.
    - Rebuilds the system font cache.
12. **Dev Toolchains & Language Servers**:
    - **Rust** via the official `rustup` installer, plus the **rust-analyzer** language server.
    - **gopls** (Go language server) via `go install`.
    - **jdtls** (Eclipse JDT Language Server for Java) from the `karlinator/jdtls` COPR.
    - **TypeScript** and the **TypeScript language server** via npm.
    - **Reasonix** (terminal coding agent) via npm.
13. **Usability & Shell Customization (Zsh)**:
    - Installs **Zsh** and the official plugins **zsh-syntax-highlighting** and **zsh-autosuggestions**.
    - Sets the default shell to **Zsh**.
    - Configures `~/.zshrc` to initialize the **Starship** prompt and put toolchain binaries (`~/.cargo/bin`, `~/go/bin`, `~/.local/bin`) on `PATH`.
    - Enables **Sudo Password Feedback** (shows asterisks as you type passwords).
14. **LibreOffice Microsoft Compatibility**: Configures LibreOffice to default to saving in Microsoft Office XML formats (DOCX, XLSX, PPTX) via a global registry override.

---

## Alternative Execution (Manual)

If you prefer to download and run the script manually:

### Step 1: Clone the Repository
```bash
git clone https://github.com/roguehunter7/fedora-setup.git
cd fedora-setup
```

### Step 2: Make the Script Executable
```bash
chmod +x setup.sh
```

### Step 3: Run the Script
```bash
sudo ./setup.sh
```
