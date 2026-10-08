# Custom source restore

The fork's `src/` tree is the canonical customized source. `restore.sh` copies that tree into an existing installation after the upstream installer or updater replaces the installed source. Run `./custom/restore.sh` from this checkout; set `SERPANTINUM_INSTALL_DIR` if the installation is not at `${XDG_DATA_HOME:-$HOME/.local/share}/serpantinum`.

`config-sources/` contains code-only snapshots from the optional local custom directory for reference, including an earlier Snake implementation and timer patch. The restore script uses the newer active modules in the fork's `src/` tree. Settings, backups, caches, bytecode, cookies, and runtime Drop Shelf thumbnails are excluded.
