# How the patch works

Design notes for the two patches, why each is built the way it is, and the
problems that had to be solved along the way. [`apply.js`](../apply.js) is the
authority on what actually changes. This explains the reasoning behind it.

If you only want to know whether this is safe to run, the
[README](../README.md) covers that. This file is for people who want to read
the code and understand the choices.

## The anchoring strategy

Every edit is defined by three things: a `marker` that proves the edit is
already present, an `anchor` of surrounding NAG code that has to match
**exactly once**, and the text to splice in before or after it.

That gives three properties worth having:

- **Idempotent.** An edit whose marker is already in the file is skipped, so
  running the installer twice is harmless.
- **Fail-safe on unknown versions.** Zero anchor matches, or more than one,
  aborts the whole run before anything is written. A NAG version the patcher
  does not recognize gets refused rather than half-patched.
- **Checkable by a reader.** The anchor is real NAG source, quoted verbatim, so
  you can see exactly where each insertion lands.

Anchors are compared with line endings normalized to LF first. Without that,
matching depends on whether NAG's files and this repo happen to agree on CRLF,
which is a silent failure: the anchor is right there in the file and still does
not match. This is also why [`.gitattributes`](../.gitattributes) sets
`* -text`, so git never rewrites these files on checkout.

Every edited file is parsed with `new vm.Script(...)` before the repack starts.
A syntax error aborts the run with the original untouched, rather than producing
a NAG that no longer launches.

## Patch 1: auto-hide when EverQuest is not in front

**The problem.** NAG's overlay sits on top of everything. Tab out to a browser
or Discord and you still have timers and alerts floating over it.

**The approach.** NAG already polls the foreground window every 100ms in
`checkActiveWindow()` in `main.js`, using the bundled `active-win`. That poll is
reused rather than adding a second one, so the feature costs nothing at rest and
needs no new dependency.

On each poll the overlay is shown if the foreground window is EverQuest (its
path ends in `eqgame.exe`, or its owner reports the name `EverQuest`) or NAG
itself, and hidden otherwise. NAG is in the "keep it visible" test so that
interacting with NAG's own windows does not make the overlay vanish. The owner
name is checked alongside the path because the path is what becomes unreadable
when EverQuest runs elevated and NAG does not.

**Showing without stealing focus.** The new `setOverlayVisible()` in
`window-manager.js` re-shows with `showInactive()`, not `show()`. `show()` would
take focus away from EverQuest every time you tabbed back, which in a game where
focus loss means dropped keystrokes would be worse than the original problem.
The method also checks current visibility first, so it is a no-op when nothing
needs to change, which matters when it is called ten times a second.

**Persistence.** The toggle is a tray-menu checkbox backed by a `focusFollowsEq`
getter and setter on NAG's existing `UserPreferences`, so it follows the same
storage path as every other NAG setting and survives a restart. Unchecking it
forces the overlay back to visible, so turning the feature off can never leave
the overlay stuck hidden.

## Patch 2: multi-monitor and sleep recovery

**The problem.** On a multi-monitor setup, NAG's overlays collapse onto the
primary display when a monitor drops out. That happens when a monitor sleeps and
when the whole PC sleeps or locks. The usual workaround is restarting NAG, daily.

**The approach.** NAG already knows how to fix this. `checkOverlayPositions()`
re-anchors the overlays, and it takes a flag controlling whether it warns. The
patch calls it with `false`, so recovery is silent and you do not get a dialog
every time you wake the machine. No new positioning logic was written.

The real work is *when* to call it.

**Timing is the whole problem.** Windows re-enumerates displays over one to
three seconds after a wake, and it does not do it atomically. Re-anchoring
immediately reads a display topology that is still settling and lands the
overlays in the wrong place, which looks identical to not having the fix at all.

So recovery fires on a stagger, not once, and each new trigger cancels the
pending timers rather than queueing more work:

| Trigger | Delays | Why |
| --- | --- | --- |
| `display-metrics-changed`, `display-added`, `display-removed` | 750ms, 3000ms | A monitor powering up or down. These arrive in bursts mid-transition, so they are coalesced. |
| `powerMonitor` `resume`, `unlock-screen` | 1500ms, 4000ms, 8000ms | Whole-PC sleep and lock. Longer and three-stage, because geometry stays unstable for several seconds after a real wake. |

**Why both event sources.** Sleep and lock do not reliably emit
`display-metrics-changed`, so the display events alone miss the most common
case. `powerMonitor` had to be added to the Electron `require` in `main.js`,
which is why one of the six edits is a one-line import change.

**The gate.** Recovery only runs when NAG's own "Enable relative window
positions" setting is on, since that setting is what makes re-anchoring
meaningful. With it off, the patch deliberately does nothing.

## Running with no prerequisites

The patcher needs Node to run and the `asar` tool to unpack and repack
`app.asar`. Requiring users to install Node would lose most of them.

Instead it borrows NAG's own bundled Electron, which is Node underneath, by
launching it with `ELECTRON_RUN_AS_NODE=1`. The `asar` tool is vendored in
`lib/`. Nothing is installed, and nothing is downloaded at runtime.

Four things that had to be solved to make that work:

- **`process.noAsar = true`.** Electron's patched `fs` treats any path ending in
  `.asar` as a virtual archive to look *inside*. Without this, copying or
  replacing `app.asar` as an ordinary file does not behave.
- **A temp directory with no leading dot.** `asar`'s unpack glob (`**`) does not
  traverse dot-directories, so a conventional `.nag-patch-tmp` silently loses
  files during the repack.
- **A short temp path.** NAG's bundled dependencies nest deeply enough that a
  long extraction root pushes paths past the Windows 260-character limit, so the
  extraction root is kept short deliberately.
- **Quoting, and not waiting.** Electron is a GUI-subsystem executable, so
  PowerShell's `-Wait` is unreliable against it. `patch-nag.ps1` starts it with
  `-PassThru`, tails the redirected output file to show live progress, and
  decides success from the patcher's own output rather than an exit code.

The progress spinner exists because unpack and repack take ten to thirty seconds
each on a roughly 170 MB archive, and a console that prints nothing for that long
reads as frozen.

## Repacking safely

`node_modules/active-win` is kept unpacked (`unpack: '**/active-win/**'`),
because it contains a native `.node` binary that cannot be loaded from inside an
asar archive. Packing it would break the foreground-window detection that
patch 1 depends on.

After the repack and before anything is swapped into place, the patcher checks
that the native binary is still present in the output. If the repack lost it,
the run aborts with the original untouched.

The pristine `app.asar` is copied to `app.asar.orig` once, on the first run, and
never overwritten afterward. That matters: it means the backup is always the
pristine original rather than a previously patched copy, no matter how many
times the installer runs.

## The update problem

NAG's auto-updater replaces `app.asar` wholesale, which removes the patch. This
is not hypothetical; it has happened. There is no way to survive it from
outside, because the update is a full-file replacement.

The answer is to run the installer again after a NAG update. It is idempotent,
so re-running is always safe.

This is also the strongest argument for these two features living upstream
rather than in a patch.
