EQ NAG - Overlay Enhancements
=============================

Two quality-of-life fixes for the EQ NAG overlay, applied by a one-click patcher.


WHAT YOU GET
------------
1. Auto-hide when tabbed out of EQ
   Adds a tray-menu checkbox: "Auto-hide overlay when tabbed out of EQ".
   When ticked, NAG's overlay hides automatically whenever EverQuest isn't the
   window you're using, and reappears the instant you tab back (without stealing
   focus from the game). The setting is remembered between restarts.

2. Multi-monitor / sleep recovery
   Fixes NAG's overlays collapsing onto your main monitor after a display turns
   off or the PC sleeps/locks on a multi-monitor setup (the "everything jumps to
   the primary screen, have to restart NAG" problem). NAG now silently re-anchors
   the overlays a few seconds after the displays wake up.
   (Requires NAG's "Enable relative window positions" setting to be ON.)


HOW TO INSTALL
--------------
1. Make sure EQ NAG is installed (run it at least once).
2. Double-click:   1 - INSTALL patch (double-click).bat
3. When it finishes, launch NAG. For feature 1, RIGHT-CLICK the NAG tray icon
   (bottom-right of the taskbar, by the clock) and tick
   "Auto-hide overlay when tabbed out of EQ".

No other software is required - the patcher uses NAG's own built-in runtime.

If Windows SmartScreen warns ("Windows protected your PC") because the file came
from the internet: click "More info" -> "Run anyway". Everything here is plain
text you can read in Notepad (the .ps1 files, apply.js, and payload\ folder).


HOW TO UNDO
-----------
Double-click:   2 - REVERT to original (double-click).bat
This restores NAG's original files from the automatic backup.


NOTES / LIMITATIONS
-------------------
* A safety backup of your original is saved at:
      ...\electron-angular-eq-parse\resources\app.asar.orig
* Running the installer twice is harmless - it detects an existing patch and
  skips anything already applied.
* If NAG ever installs an official update it will overwrite the patch; just run
  the INSTALL .bat again afterward.
* If EQ is run "as administrator" but NAG is not, Windows can hide EQ's window
  info from NAG and the overlay may stay hidden - run both the same way.
* Built and tested against NAG version 0.2.22. If you have a version whose code
  the patcher doesn't recognise, it stops safely and changes NOTHING.


WHAT'S IN THIS FOLDER
---------------------
  1 - INSTALL patch ....bat   double-click to install
  2 - REVERT ...........bat   double-click to undo
  patch-nag.ps1               install logic (find NAG, back up, run apply.js)
  revert-nag.ps1              restore-from-backup logic
  apply.js                    the actual source edits (open it to review)
  payload\                    exact code inserted for the display-recovery fix
  lib\                        a small copy of the "asar" tool used to
                              unpack/repack NAG's app.asar
