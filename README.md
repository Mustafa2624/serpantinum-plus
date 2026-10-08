<div align="center">
  <img src="docs/assets/banner.png" alt="Serpantinum Plus banner" width="850" />

  <h1>Serpantinum Plus</h1>
  <p>Serpantinum for Hyprland, plus a video downloader, music player, window overview, drop shelf and Snake.</p>

  <a href="LICENSE.md"><img alt="AGPL-3.0-or-later" src="https://img.shields.io/badge/license-AGPL--3.0-blue.svg"></a>
  <img alt="Arch Linux" src="https://img.shields.io/badge/platform-Arch%20Linux-1793D1?logo=arch-linux&logoColor=white">
  <img alt="Hyprland" src="https://img.shields.io/badge/compositor-Hyprland-58E1FF">
  <img alt="Quickshell" src="https://img.shields.io/badge/shell-Quickshell-7B68EE">
</div>

## Install

**Already have Serpantinum?** This repository is for adding the custom modules to an existing install. The installer previews its changes, asks first, backs up files it overwrites, and restarts the shell when it can:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Mustafa2624/serpantinum-plus/master/custom/install-addons.sh)
```

**Update:** after an official Serpantinum update, rerun this script to add the custom modules again.

<details>
<summary>Prefer to read the script first?</summary>

```bash
git clone --depth 1 https://github.com/Mustafa2624/serpantinum-plus.git
cd serpantinum-plus
bash custom/install-addons.sh --dry-run   # preview, changes nothing
bash custom/install-addons.sh             # install
```

</details>

## What's inside

### In the bar

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/video-downloader.png" width="300" alt="Video downloader"><br><b>Video downloader</b><br><sub>Video, audio, playlists and transcripts via yt-dlp</sub></td>
    <td align="center"><img src="docs/screenshots/music-player.jpg" width="300" alt="Music player"><br><b>Music player</b><br><sub>Local library, seekbar, shuffle, repeat</sub></td>
    <td align="center"><img src="docs/screenshots/expose-overview.jpg" width="300" alt="Expose overview"><br><b>Expose overview</b><br><sub>All windows from every workspace, macOS style</sub></td>
  </tr>
</table>

### In Quickactions

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/music-player.jpg" width="300" alt="Music player"><br><b>Music player</b><br><sub>Also available from Quickactions</sub></td>
    <td align="center"><img src="docs/screenshots/drop-shelf.jpg" width="300" alt="Drop shelf"><br><b>Drop shelf</b><br><sub>Hold files and links, drag them out when needed</sub></td>
    <td align="center"><img src="docs/screenshots/snake-game.jpg" width="300" alt="Snake"><br><b>Snake</b><br><sub>A quick game in the Quickactions switcher</sub></td>
  </tr>
</table>

## Setup

Start the shell with `serpantinumd start`. Needs Arch Linux (or similar), Hyprland and Quickshell.

<details>
<summary>Autostart lines for clipboard and equalizer</summary>

```lua
hl.on("hyprland.start", function()
  hl.exec_cmd("wl-paste --type text --watch cliphist store")
  hl.exec_cmd("wl-paste --type image --watch cliphist store")
  hl.exec_cmd("systemctl --user enable --now easyeffects")
end)
```

</details>

<details>
<summary>Something not working?</summary>

- **Downloader error:** install `yt-dlp` and `ffmpeg`, then restart the shell.
- **No music playback:** install `mpv`, then restart the shell.
- **Clipboard or equalizer missing:** add the autostart lines above.
- **Patch conflict:** the installer lists the file that conflicts and stops before changing anything. Update Serpantinum or review the conflicting file before retrying.

</details>

## Credits and license

Based on [Serpantinum by ilyamiro](https://github.com/ilyamiro/serpantinum). Snake is inspired by [omarchy-snake-plugin](https://github.com/jhgundersen/omarchy-snake-plugin), the downloader by [omarchy-yt-downloader](https://github.com/dlpwaters/omarchy-yt-downloader). Thanks to Darkall44/Qylock for the material SDDM theme.

[![Support the original author (ilyamiro)](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/ilyamiro)

AGPL-3.0-or-later, see [LICENSE.md](LICENSE.md). Third-party notices: [`custom/THIRD_PARTY_NOTICES.md`](custom/THIRD_PARTY_NOTICES.md).

Copyright (C) 2026 Illia Miroshnichenko. Modified by Mustafa2624, 2026.

<details>
<summary>Upstream contributors</summary>

<div align="center">
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

</details>
