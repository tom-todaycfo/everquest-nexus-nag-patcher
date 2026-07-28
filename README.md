# NAG Overlay Enhancements

Two quality-of-life fixes for the EQ NAG overlay, applied by a one-click patcher.

This is the full source of the patch offered on
[Manafire's EverQuest Nexus](https://everquestnexus.com/eq1/downloads/nag-overlay-enhancements).
It is public so you can read every line before you run it. Nothing here is compiled, packed, or
hidden. The `.bat`, `.ps1`, `.js`, and `.txt` files are the whole thing.

**NAG is not mine.** It is [guildantix/eq-nag](https://github.com/guildantix/eq-nag), and all
credit for it goes to its author. This patch only edits the copy of NAG already installed on your
computer, and it does not include or redistribute any part of NAG itself.

## What it does

**1. Auto-hide when you tab out of EverQuest.** Adds a checkbox to NAG's tray menu,
"Auto-hide overlay when tabbed out of EQ." Tick it and the overlay hides the moment EverQuest is
not the window you are using. It comes back the instant you tab in, and it never steals focus from
the game. The setting is remembered between restarts.

**2. Multi-monitor and sleep recovery.** Fixes NAG's overlays collapsing onto your main monitor
after a display powers off or the PC sleeps or locks. NAG now watches for display and wake events
and silently re-anchors the overlays a few seconds later, once Windows has finished re-detecting
your monitors. This uses NAG's own "Enable relative window positions" setting, so that has to be
on.

## Installing

Download the packaged zip from
[the Nexus download page](https://everquestnexus.com/eq1/downloads/nag-overlay-enhancements),
unzip it anywhere, and double-click `1 - INSTALL patch (double-click).bat`.

Cloning this repo works the same way. The repo layout and the zip layout are identical, so you can
run the `.bat` straight out of a clone.

To undo it, double-click `2 - REVERT to original (double-click).bat`.

## How it works

The patcher borrows NAG's own bundled Electron runtime and runs it as Node, so nothing has to be
installed first. It then:

1. Finds your NAG install by looking for `resources\app.asar`.
2. Copies the original to `app.asar.orig`, once, as a backup.
3. Unpacks `app.asar` into a temp folder.
4. Applies six small source edits, each matched against a fixed anchor of surrounding code.
5. Syntax-checks every edited file before committing to anything.
6. Repacks `app.asar`, keeping `node_modules/active-win` unpacked, and swaps it into place.

It is safe to run more than once. Each edit carries a marker string, and an edit whose marker is
already present is skipped.

It fails safe. If an anchor is missing or matches more than once, which is what a different NAG
version looks like, the patcher stops before writing anything and your `app.asar` is left
untouched.

## Exactly what changes

Six edits, all in [`apply.js`](apply.js), which holds the inserted code inline so you can read the
edit and the reason for it together. The one long insertion lives in
[`payload/main-recovery.txt`](payload/main-recovery.txt).

| File in NAG | Edit |
| --- | --- |
| `src/electron/data/user-preferences.js` | Adds a `focusFollowsEq` getter and setter, so the toggle persists |
| `src/electron/window-manager.js` | Adds `setOverlayVisible()`, which shows or hides the overlay without taking focus |
| `main.js` | Adds the tray-menu checkbox |
| `main.js` | Hides or shows the overlay inside the existing `checkActiveWindow()` loop |
| `main.js` | Imports `powerMonitor` from Electron |
| `main.js` | Adds the display and power event handlers that re-anchor the overlays |

Nothing is deleted, and nothing outside your NAG folder is touched. There is no network access
anywhere in the patcher.

## Compatibility

Built and tested against **EQ NAG 0.2.22** on Windows, which installs itself as
`electron-angular-eq-parse` under `%LOCALAPPDATA%\Programs`. That folder name is what the installer
searches for, so it is worth knowing if it ever fails to find your install.

Any other version either patches cleanly or is refused outright, because the anchors have to match
exactly. There is no middle case where it half-applies.

If NAG ships an official update it will overwrite the patch. Run the installer again afterward.

## Repo layout

```
1 - INSTALL patch (double-click).bat   double-click to install
2 - REVERT to original (double-click).bat   double-click to undo
patch-nag.ps1        install logic: find NAG, back it up, run apply.js
revert-nag.ps1       restore-from-backup logic
apply.js             the source edits themselves
payload/             the long insertion, kept out of apply.js for readability
lib/                 a vendored copy of the "asar" tool, used to unpack and repack app.asar
README.txt           the readme that ships inside the zip, written for players
scripts/pack.ps1     builds the release zip
```

`lib/node_modules/` is committed on purpose. It is what lets the patch run on a machine with no
Node.js installed, and committing it means a clone and the shipped zip hold the same bytes.

## Building the zip

```powershell
powershell -ExecutionPolicy Bypass -File scripts/pack.ps1 -Version 1.0
```

Writes `dist/NAG Overlay Enhancements v1.0.zip`, with the same top-level folder and the same
contents as the released download. Repo-only files (this README, the license, `scripts/`, and the
git metadata) are left out.

## License

MIT, see [LICENSE](LICENSE). That covers the patch. It does not cover EQ NAG, which belongs to its
own author, or the vendored `asar` tool under `lib/`, which keeps its own MIT license.