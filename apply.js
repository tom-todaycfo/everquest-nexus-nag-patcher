/*
 * apply.js — NAG "focus-follows-EQ" patcher.
 *
 * Runs under NAG's own bundled Electron, invoked as Node:
 *   ELECTRON_RUN_AS_NODE=1  "EQ Nag.exe"  apply.js  <resourcesDir>  <libDir>
 *
 * It extracts the target's app.asar, applies four small source edits by
 * matching stable code anchors, re-validates each file's syntax, then repacks
 * app.asar (keeping node_modules/active-win unpacked). It is idempotent and
 * fails safe: if it can't recognise the code (unknown NAG version) it aborts
 * WITHOUT writing anything, leaving the original untouched.
 */
'use strict';

// We run under NAG's Electron, whose patched fs treats any ".asar" path as a virtual
// archive. Disable that so we can copy/replace app.asar as an ordinary file.
process.noAsar = true;

const path = require('path');
const fs = require('fs');
const os = require('os');
const vm = require('vm');

const resourcesDir = process.argv[2];
const libDir = process.argv[3];
if (!resourcesDir || !libDir) { fail('Internal error: missing arguments.'); }

const asar = require(path.join(libDir, 'node_modules', 'asar'));

const asarPath = path.join(resourcesDir, 'app.asar');
const backupPath = path.join(resourcesDir, 'app.asar.orig');
// Keep the temp path SHORT so deep bundled paths stay under the Windows 260-char limit.
// NOTE: no leading dot in the folder name - asar's unpack glob (**) won't traverse dot-directories.
const tmpDir = path.join(os.homedir(), 'nag-focus-patch-tmp');

function fail(msg) { console.error('ERROR: ' + msg); process.exit(1); }
function info(msg) { console.log(msg); }
// Normalise line endings so matching is robust whether files (or this script) use LF or CRLF.
function lf(s) { return String(s).replace(/\r\n/g, '\n'); }

/* ------------------------------------------------------------------ *
 * The edits. Each: file, a `marker` proving it's already applied,
 * an `anchor` (must appear exactly once), and `text` to splice in
 * either 'after' or 'before' the anchor.
 * ------------------------------------------------------------------ */
const edits = [
  {
    label: 'preferences: focusFollowsEq setting',
    file: ['src', 'electron', 'data', 'user-preferences.js'],
    marker: 'focusFollowsEq',
    where: 'after',
    anchor:
`    set enableGpuAcceleration( val ) {
        log.info( '[UserPreferences:enableGpuAcceleration]', val );
        this.#data.enableGpuAcceleration = val === true;
        this.storeDataFile( this.#data );
    }`,
    text:
`

    /** @type {boolean} If true, Nag hides the overlay when EverQuest isn't the foreground window. */
    get focusFollowsEq() {
        return this.#data.focusFollowsEq === true;
    }
    set focusFollowsEq( val ) {
        log.info( '[UserPreferences:focusFollowsEq]', val );
        this.#data.focusFollowsEq = val === true;
        this.storeDataFile( this.#data );
    }`,
  },
  {
    label: 'window-manager: setOverlayVisible()',
    file: ['src', 'electron', 'window-manager.js'],
    marker: 'setOverlayVisible',
    where: 'after',
    anchor:
`    resumeRendererMouseForwarding() {
        this.#renderer?.webContents.send( 'renderer:mouse-forwarding:resume', {} );
        this.#renderer?.setIgnoreMouseEvents( true, { forward: true } );
    }`,
    text:
`


    /**
     * Shows or hides the primary overlay renderer without stealing focus.
     * Used by the focus-follows-EQ feature.
     *
     * @param {boolean} visible True to show the overlay, false to hide it.
     */
    setOverlayVisible( visible ) {
        if ( !this.#renderer || this.#renderer.isDestroyed() ) { return; }
        if ( visible ) {
            if ( !this.#renderer.isVisible() ) { this.#renderer.showInactive(); }
        } else {
            if ( this.#renderer.isVisible() ) { this.#renderer.hide(); }
        }
    }`,
  },
  {
    label: 'main: tray checkbox',
    file: ['main.js'],
    marker: 'Auto-hide overlay when tabbed out of EQ',
    where: 'before',
    anchor:
`        {
            label: 'Exit', click: function () {`,
    text:
`        {
            label: 'Auto-hide overlay when tabbed out of EQ',
            type: 'checkbox',
            checked: userPreferences.focusFollowsEq === true,
            click: function ( menuItem ) {
                userPreferences.focusFollowsEq = menuItem.checked === true;
                if ( !menuItem.checked ) { winManager.setOverlayVisible( true ); }
            }
        },
`,
  },
  {
    label: 'main: focus toggle in checkActiveWindow()',
    file: ['main.js'],
    marker: 'Focus-follows-EQ: hide the overlay',
    where: 'after',
    anchor:
`    if ( nagProcessId == undefined && (data?.owner?.name === 'Electron' || data?.owner?.name === 'EQ Nag') && data?.title === 'Nag' ) {
        nagProcessId = data?.owner?.processId;
    }`,
    text:
`

    // Focus-follows-EQ: hide the overlay unless EverQuest (or Nag itself) is the foreground window.
    if ( data && userPreferences.focusFollowsEq === true ) {
        const fgPath = data.owner?.path ? data.owner.path.toLowerCase() : '';
        const isEq  = fgPath.endsWith( '\\\\eqgame.exe' ) || data.owner?.name === 'EverQuest';
        const isNag = data.owner?.processId != null && data.owner.processId === nagProcessId;
        winManager.setOverlayVisible( isEq || isNag );
    }`,
  },
  {
    label: 'main: import powerMonitor (display-recovery)',
    file: ['main.js'],
    marker: 'powerMonitor',
    where: 'replace',
    anchor: `Tray, Menu, globalShortcut } = require( "electron" );`,
    replacement: `Tray, Menu, globalShortcut, powerMonitor } = require( "electron" );`,
  },
  {
    label: 'main: overlay display/sleep recovery',
    file: ['main.js'],
    marker: 'scheduleOverlayRecheck',
    where: 'after',
    anchor: `        winManager.onReady();`,
    textFile: 'main-recovery.txt',
  },
];

function rmrf(p) {
  // maxRetries rides out transient Windows locks (antivirus / freshly written .node files).
  if (fs.existsSync(p)) { fs.rmSync(p, { recursive: true, force: true, maxRetries: 8, retryDelay: 150 }); }
}
function rmrfQuiet(p) { try { rmrf(p); } catch (e) { /* best-effort cleanup; ignore */ } }

async function main() {
  if (!fs.existsSync(asarPath)) { fail('Could not find app.asar at ' + asarPath); }

  // 1) Back up the pristine original exactly once.
  if (!fs.existsSync(backupPath)) {
    fs.copyFileSync(asarPath, backupPath);
    info('Backed up original -> app.asar.orig');
  } else {
    info('Backup already exists (app.asar.orig) - leaving it as the pristine copy.');
  }

  // 2) Extract into a short-pathed temp dir.
  rmrf(tmpDir);
  fs.mkdirSync(tmpDir, { recursive: true });
  info('Unpacking NAG (~170 MB, this can take 10-30 seconds) ...');
  asar.extractAll(asarPath, tmpDir);
  info('Unpacked. Applying changes ...');

  // 3) Apply edits (idempotent + fail-safe).
  let applied = 0, already = 0;
  for (const e of edits) {
    const fp = path.join(tmpDir, ...e.file);
    if (!fs.existsSync(fp)) { fail('Expected file missing from this NAG build: ' + e.file.join('/')); }
    let src = lf(fs.readFileSync(fp, 'utf8'));
    const anchor = lf(e.anchor), marker = lf(e.marker);
    // Insertion text may be inline (e.text) or loaded from a payload file (e.textFile).
    const text = e.textFile ? lf(fs.readFileSync(path.join(__dirname, 'payload', e.textFile), 'utf8'))
               : (e.text != null ? lf(e.text) : '');

    if (src.includes(marker)) { already++; info('  = already applied: ' + e.label); continue; }

    const count = src.split(anchor).length - 1;
    if (count === 0) {
      fail('Could not recognise this NAG version (anchor not found for "' + e.label + '").\n' +
           '       Nothing was changed. Your app.asar is untouched.');
    }
    if (count > 1) {
      fail('Ambiguous anchor for "' + e.label + '" (' + count + ' matches). Aborting to be safe.');
    }

    if (e.where === 'replace') {
      src = src.replace(anchor, lf(e.replacement));
    } else {
      src = e.where === 'after'
        ? src.replace(anchor, anchor + text)
        : src.replace(anchor, text + anchor);
    }

    // 4) Syntax-check the edited file before we commit to repacking.
    try {
      new vm.Script(src, { filename: e.file.join('/') });
    } catch (err) {
      fail('Edit produced a syntax error in ' + e.file.join('/') + ': ' + err.message + '\n       Aborting; original untouched.');
    }

    fs.writeFileSync(fp, src);
    applied++;
    info('  + applied: ' + e.label);
  }

  if (applied === 0) {
    info('\nAlready fully patched - nothing to do. (' + already + '/' + edits.length + ')');
    rmrfQuiet(tmpDir);
    return;
  }

  // 5) Repack to a temp asar, keeping active-win unpacked, then move into place.
  const outAsar = path.join(tmpDir + '-out', 'app.asar');
  rmrf(path.dirname(outAsar));
  fs.mkdirSync(path.dirname(outAsar), { recursive: true });
  info('Repacking NAG (another 10-30 seconds) ...');
  await asar.createPackageWithOptions(tmpDir, outAsar, { unpack: '**/active-win/**' });
  info('Repacked. Installing patched files ...');

  // Sanity: repacked archive must contain our marker and the native binary.
  const outUnpacked = outAsar + '.unpacked';
  const nodeBin = path.join(outUnpacked, 'node_modules', 'active-win', 'lib', 'binding', 'napi-6-win32-unknown-x64', 'node-active-win.node');
  if (!fs.existsSync(nodeBin)) { fail('Repack lost the active-win native module. Aborting; original untouched.'); }

  // 6) Swap into place.
  fs.copyFileSync(outAsar, asarPath);
  rmrf(asarPath + '.unpacked');
  fs.cpSync(outUnpacked, asarPath + '.unpacked', { recursive: true });

  info('\nDONE - patched ' + applied + ' section(s). NAG now has the overlay auto-hide toggle + multi-monitor/sleep recovery.');

  // Cleanup is best-effort: the patch is already in place, so never fail here.
  rmrfQuiet(tmpDir);
  rmrfQuiet(path.dirname(outAsar));
}

main().catch(err => fail(err && err.stack ? err.stack : String(err)));
