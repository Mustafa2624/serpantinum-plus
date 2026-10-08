<div align="center">
  <img src="docs/assets/banner.png" alt="Serpantinum Plus banner" width="850" />

  <h1>Serpantinum Plus</h1>
  <p>A Hyprland desktop shell fork with handy media tools and quick actions.</p>

  <a href="LICENSE.md"><img alt="AGPL-3.0-or-later" src="https://img.shields.io/badge/license-AGPL--3.0-blue.svg"></a>
  <img alt="Arch Linux" src="https://img.shields.io/badge/platform-Arch%20Linux-1793D1?logo=arch-linux&logoColor=white">
  <img alt="Hyprland" src="https://img.shields.io/badge/compositor-Hyprland-58E1FF">
  <img alt="Quickshell" src="https://img.shields.io/badge/shell-Quickshell-7B68EE">
</div>

## Contents

- [What's new](#whats-new)
- [Fork vs upstream](#fork-vs-upstream)
- [Features](#features)
- [Installation](#installation)
- [Requirements / Setup](#requirements--setup)
- [Updating](#updating)
- [Troubleshooting](#troubleshooting)
- [Credits](#credits)

## What's new

| Feature | What it does | Where |
|---|---|---|
| Video downloader | Download videos, audio, playlists, and transcripts with yt-dlp. | Bar |
| Music player | Browse a local library and control playback, repeat, shuffle, and seeking. | Bar and Quickactions |
| Drop shelf | Hold files and links temporarily while dragging and dropping. | Quickactions |
| Snake | Play Snake from the Quickactions switcher. | Quickactions |
| Expose overview | Show open windows across workspaces in a macOS-inspired overview. | Bar |

## Fork vs upstream

| | Original Serpantinum | Serpantinum Plus |
|---|---|---|
| Core shell and installer | Yes | Based on the original project |
| Video downloader and music player | — | Added |
| Quickactions drop shelf and Snake | — | Added |
| Expose overview across workspaces | — | Added |

## Features

### Video downloader

A bar pill opens yt-dlp controls for video, audio, playlists, and transcripts. It requires `yt-dlp` and `ffmpeg` on `PATH`.

![Video downloader](docs/screenshots/video-downloader.png)

### Music player

Play local music from the bar or Quickactions with a library, seekbar, repeat, shuffle, and previous/play-pause/next controls. Playback uses `mpv`.

![Music player](docs/screenshots/music-player.jpg)

### Drop shelf

Keep files and links in a temporary Quickactions shelf, ready to drag into another app.

![Drop shelf](docs/screenshots/drop-shelf.jpg)

### Snake

Play Snake as an item in the Quickactions switcher.

![Snake game](docs/screenshots/snake-game.jpg)

### Expose overview

Open a macOS-inspired overview from the bar to see and activate windows across all workspaces.

![Expose overview](docs/screenshots/expose-overview.jpg)

## Installation

### Path A - Fresh install (whole shell from this fork)

1. Clone this fork and enter the checkout:

   ```bash
   git clone --depth 1 --branch master https://github.com/Mustafa2624/serpantinum-plus.git
   cd serpantinum-plus
   ```

2. Run this fork's installer:

   ```bash
   REPO_SLUG=Mustafa2624/serpantinum-plus bash install/install.sh
   ```

   The installer uses the checked-out fork source. The original project's installer is documented by the upstream project; the command above installs Serpantinum Plus.

3. Restart the shell after installation:

   ```bash
   serpantinumd stop && serpantinumd start
   ```

### Path B - Already have Serpantinum (install only my additions)

1. An add-ons-only installer is **coming soon**. There is currently no supported command that overlays just these additions. `custom/restore.sh` copies the entire fork `src/` tree and is intended to restore the customized shell after an update, not to install only the add-ons onto an existing Serpantinum install.

2. Until that installer exists, use Path A for a complete installation from this fork. Do not copy the fork's whole `src/` directory if you need to preserve a different existing Serpantinum source tree.

## Requirements / Setup

- Arch Linux or an Arch-based distribution, Hyprland, and Quickshell. The fork installer installs the shell's declared system dependencies.
- Install `yt-dlp` separately for the video downloader; `ffmpeg` is part of the installer's dependency list.
- Install `mpv` separately for the local music player; it is not in the installer's dependency list.
- Clipboard integration uses `wl-paste` and `cliphist`; the installer includes `wl-clipboard` and `cliphist`.
- The equalizer integration uses EasyEffects, which is included in the installer's dependency list.

### Required autostart

Add clipboard listeners and the EasyEffects user service to your compositor's startup configuration. Example on Hyprland:

```lua
hl.on("hyprland.start", function()
  hl.exec_cmd("wl-paste --type text --watch cliphist store")
  hl.exec_cmd("wl-paste --type image --watch cliphist store")
  hl.exec_cmd("systemctl --user enable --now easyeffects")
end)
```

## Updating

Run the installer again from this fork checkout to update from Serpantinum Plus. If an official upstream update has replaced customized source files, restore the fork's full `src/` tree from the checkout:

```bash
./custom/restore.sh
serpantinumd stop && serpantinumd start
```

`custom/restore.sh` copies all of this fork's `src/` into the installed shell; it is not an add-ons-only overlay.

## Troubleshooting

<details>
<summary>The video downloader says a dependency is missing</summary>

Install `yt-dlp` and ensure both `yt-dlp` and `ffmpeg` are available on `PATH`, then restart Serpantinum.

</details>

<details>
<summary>The music player cannot start playback</summary>

Install `mpv`, make sure it is available on `PATH`, and restart Serpantinum.

</details>

<details>
<summary>Clipboard history or the equalizer is not working</summary>

Check the required autostart commands above. Clipboard history needs `wl-paste` and `cliphist`; the equalizer needs the EasyEffects user service.

</details>

## Credits

Serpantinum Plus is based on [Serpantinum by ilyamiro](https://github.com/ilyamiro/serpantinum). Snake is inspired by [jhgundersen/omarchy-snake-plugin](https://github.com/jhgundersen/omarchy-snake-plugin), and the downloader is inspired by [dlpwaters/omarchy-yt-downloader](https://github.com/dlpwaters/omarchy-yt-downloader). Special thanks to Darkall44/Qylock for the material SDDM theme.

[![Support the original author (ilyamiro)](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/ilyamiro)

## License

The original Serpantinum code is distributed under the GNU Affero General Public License, version 3 or later; see [LICENSE.md](LICENSE.md). Third-party component terms and attribution for custom additions are listed in [`custom/THIRD_PARTY_NOTICES.md`](custom/THIRD_PARTY_NOTICES.md).

Modified by Mustafa2624, 2026.

<br><br><br>

<div align="center">
  <h3>Upstream contributors</h3>
  <br>

  <a href="https://github.com/TheRinder2"><img src="https://avatars.githubusercontent.com/u/48689803?v=4&s=48" width="48" height="48" alt="TheRinder2"></a>
  <a href="https://github.com/bizneskind-droid"><img src="https://avatars.githubusercontent.com/u/245046997?v=4&s=48" width="48" height="48" alt="bizneskind-droid"></a>
  <a href="https://github.com/Pigeon78"><img src="https://avatars.githubusercontent.com/u/151051379?v=4&s=48" width="48" height="48" alt="Pigeon78"></a>
  <a href="https://github.com/Eduarduar"><img src="https://avatars.githubusercontent.com/u/104547727?v=4&s=48" width="48" height="48" alt="Eduarduar"></a>
  <a href="https://github.com/Spinty-dev"><img src="https://avatars.githubusercontent.com/u/123001216?v=4&s=48" width="48" height="48" alt="Spinty-dev"></a>
  <a href="https://github.com/MrDexstor"><img src="https://avatars.githubusercontent.com/u/97257847?v=4&s=48" width="48" height="48" alt="MrDexstor"></a>
  <a href="https://github.com/coloramamoe"><img src="https://avatars.githubusercontent.com/u/117035740?v=4&s=48" width="48" height="48" alt="coloramamoe"></a>
  <a href="https://github.com/Zyxilon"><img src="https://avatars.githubusercontent.com/u/234867627?v=4&s=48" width="48" height="48" alt="Zyxilon"></a>
  <a href="https://github.com/gouthamkrishnap"><img src="https://avatars.githubusercontent.com/u/224089015?v=4&s=48" width="48" height="48" alt="gouthamkrishnap"></a>
  <a href="https://github.com/Stoltembergg"><img src="https://avatars.githubusercontent.com/u/312632452?v=4&s=48" width="48" height="48" alt="Stoltembergg"></a>
  <a href="https://github.com/andckadir"><img src="https://avatars.githubusercontent.com/u/175446585?v=4&s=48" width="48" height="48" alt="andckadir"></a>
  <a href="https://github.com/ArseniiTkachuk"><img src="https://avatars.githubusercontent.com/u/257102547?v=4&s=48" width="48" height="48" alt="ArseniiTkachuk"></a>
  <a href="https://github.com/MCUxDaredevil"><img src="https://avatars.githubusercontent.com/u/59441946?v=4&s=48" width="48" height="48" alt="MCUxDaredevil"></a>
  <a href="https://github.com/MILKv2"><img src="https://avatars.githubusercontent.com/u/142674287?v=4&s=48" width="48" height="48" alt="MILKv2"></a>
  <a href="https://github.com/pedrolourencosilva"><img src="https://avatars.githubusercontent.com/u/184855780?v=4&s=48" width="48" height="48" alt="pedrolourencosilva"></a>
  <a href="https://github.com/Vaspyyy"><img src="https://avatars.githubusercontent.com/u/197029450?v=4&s=48" width="48" height="48" alt="Vaspyyy"></a>
  <a href="https://github.com/Sergi122"><img src="https://avatars.githubusercontent.com/u/171693999?v=4&s=48" width="48" height="48" alt="Sergi122"></a>
  <a href="https://github.com/Syrup5845"><img src="https://avatars.githubusercontent.com/u/310795939?v=4&s=48" width="48" height="48" alt="Syrup5845"></a>
  <a href="https://github.com/forteleaf"><img src="https://avatars.githubusercontent.com/u/14119264?v=4&s=48" width="48" height="48" alt="forteleaf"></a>
  <a href="https://github.com/kranks-uga"><img src="https://avatars.githubusercontent.com/u/179175113?v=4&s=48" width="48" height="48" alt="kranks-uga"></a>
  <a href="https://github.com/zynx-real"><img src="https://avatars.githubusercontent.com/u/320626542?v=4&s=48" width="48" height="48" alt="zynx-real"></a>
</div>

---
