# Where From

A menu-bar utility that surfaces the provenance metadata macOS keeps but Finder
hides — the origin URL (`kMDItemWhereFroms`), download date, and last-opened date
of every file — and turns it into a full **triage & organization** tool: group by
source, type, or date; find duplicates and junk; and move files into tidy
subfolders. Works on any folder, not just Downloads.

No Dock icon, no cloud, no AI. Everything stays on your Mac.

## What it does

- **Group four ways** (segmented control in the sidebar):
  - **Source** — everything from one domain (`github.com · 7 files · 45 MB`).
  - **Type** — Images, Documents, Archives, Installers, Audio, Video, Code,
    3D & CAD, Data, …
  - **Date** — Today / This week / This month / This year / Older.
  - **Cleanup** — smart buckets: **Duplicates** (SHA-256 verified), **Old
    installers** (`.dmg`/`.pkg`), **Incomplete downloads** (`.crdownload`/`.part`),
    **Big & never opened**.
- **Sortable table** — click any header: Name, Source, Kind, Added, Last opened,
  Size. Never-opened files are flagged in orange.
- **Filters** — text search, "Never opened", and "Older than N days" — they stack
  on top of whatever grouping is selected.
- **Organize into subfolders** — *Organize ▸ By source / By type / By month* moves
  the shown (or selected) files into subfolders, with **collision-safe naming**
  and a one-click **Undo**.
- **Recoverable cleanup** — *Trash Selected*, *Trash All Shown*, or right-click a
  group to trash it. Everything goes to the **Trash** (never a permanent delete);
  every destructive action confirms with a file count + total size.
- **Any folder, fast** — scan Downloads, Desktop, Documents, Movies, Pictures,
  Home, or any folder you pick; optional recursive scan streams results live with
  a running count (skips `Library` / `node_modules` noise).
- **Quick Look** — select a row and press **Space** (or right-click ▸ Quick Look)
  for an inline preview, without leaving the panel. Space/Esc closes it.
- **Menu-bar badge** — optionally shows reclaimable space (e.g. `1.2 GB`) next to
  the icon, updated only after a scan. Toggle it in the ⋯ menu.
- **Use the origin** — right-click any file to *Open Source URL* (revisit where it
  came from in your browser) or *Copy Source URL*; hover the Source column for the
  full URL. Also *Open File* / *Reveal in Finder*.
- **Right-click a folder in Finder → "Open in Where From"** — a macOS Service that
  retargets the panel to that folder and opens it (see below).
- The **⋯ menu** holds Scan Location presets, Choose Folder…, the recursive
  toggle, About, and Quit.

## Finder right-click integration

Building the bundle installs a macOS **Service** so you can right-click any folder
in Finder (or Desktop) and choose **Open in Where From** — the running menu-bar app
switches to that folder and pops open.

- It's registered automatically by `make-app.sh` (`lsregister` + `pbs -update`).
- The item appears under the right-click menu (in **Services** / **Quick Actions**,
  or at the top level depending on your macOS). If you don't see it the first time,
  enable it in **System Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸ Services ▸ Files
  and Folders**, then relaunch Finder (`killall Finder`).
- The same entry point works from the command line: `open -a WhereFrom <folder>`.

The origin is read straight from the `com.apple.metadata:kMDItemWhereFroms`
extended attribute (a binary plist), so it works even for files Spotlight hasn't
indexed. Last-opened comes from Spotlight's `kMDItemLastUsedDate` (best-effort;
files it can't answer for are shown as "never").

## Install

Requires **macOS 14 or later**. The app is **`WhereFrom.app`**.

### Homebrew (easiest)

```bash
brew install --cask ishaanpilar/tap/wherefrom
```

This installs `WhereFrom.app` into `/Applications`.

**Unsigned app — one-time Gatekeeper step.** Because it isn't code-signed yet, the
first launch is blocked by macOS. Open it once via **right-click ▸ Open ▸ Open**,
or clear the quarantine flag:

```bash
xattr -dr com.apple.quarantine /Applications/WhereFrom.app
```

After that it launches normally.

### Direct download (DMG)

Grab `WhereFrom-<version>.dmg` from the
[Releases](https://github.com/ishaanpilar/MacOSWhereFrom/releases) page, open it, and
drag **WhereFrom** onto **Applications**. Same first-launch step as above.

## Launch & first run

`WhereFrom.app` has **no Dock icon** — its icon (a downward arrow) lives in the
**menu bar**. Click it to open the triage panel; click again (or click away) to
close it. The first time it reads a protected folder (Downloads, Desktop, …),
macOS shows a one-time "…would like to access files" prompt — click **Allow**.

To quit, open the panel and choose **⋯ ▸ Quit Where From**.

## Build from source

```bash
git clone https://github.com/ishaanpilar/MacOSWhereFrom.git
cd MacOSWhereFrom
./make-app.sh        # builds WhereFrom.app (release, ad-hoc signed)
open WhereFrom.app
# or: swift run       (dev run; access prompt is attributed to your terminal)
# or: ./make-dmg.sh   (produces dist/WhereFrom-<version>.dmg)
```

## How it runs (performance & footprint)

Designed to be light and fully on-demand:

- **Idle cost is ~zero.** Measured idle: **0.0% CPU**, ~**44 MB** RAM, with no
  CPU time accumulating while the panel is closed. It's an event-driven app — no
  timers, no polling, no file-system watchers running in the background.
- **It scans only when you ask.** A scan happens on: first launch, opening the
  panel (cheap folders only — see below), choosing a folder / Scan Location,
  toggling recursive, and right after a Trash/Organize. **There are no automatic
  or scheduled scans**, and it does not watch folders for changes.
- **Opening the panel is instant.** For a normal (non-recursive) folder it does a
  quick rescan on open; for a **recursive** scan it keeps your last results and
  waits for the **⟳ refresh** button, so a big tree is never re-walked just
  because you opened the menu.
- **Duplicate hashing is opt-in.** SHA-256 hashing only runs when you switch to
  the **Cleanup** group, and only over files that share a byte size.
- **It is not a login item.** It won't start at boot and isn't "always on" in any
  hidden way — it's simply a menu-bar process that stays resident until you pick
  **Quit** from the ⋯ menu. Launch it when you need it, quit when you're done; the
  resident cost between is negligible either way.

## Roadmap

Where From started as a "where did this file come from?" utility and is growing
into a full local file-hygiene tool. Planned directions:

**App uninstaller (with hard guardrails).** Uninstall an app *and* everything it
left behind — the way CleanMyMac / AppCleaner do — by locating its scattered
support files: `~/Library/Application Support`, `Caches`, `Preferences`,
`Containers`, `Logs`, `Saved Application State`, `LaunchAgents`, etc., matched by
bundle identifier. Guardrails are the whole point:

- **Nothing is ever auto-deleted.** The app only ever acts on an explicit click,
  never on a timer or "in the background."
- **Trash, not erase.** Removals go to the Trash (recoverable), never `rm`.
- **Review-before-remove.** Every leftover is shown with its full path and size,
  each individually checkable, before anything moves.
- **Protected list.** System apps, currently-running apps, and anything under
  `/System` are excluded and cannot be selected.
- **Bundle-ID matching, not fuzzy names**, so "Mail" can't sweep up an unrelated
  "MailChimp" folder.
- **Undo** for the whole operation, plus a plain-text log of exactly what moved.

**Other planned features:**

- **Menu-bar quick stats** — reclaimable breakdown in the dropdown without opening
  the full panel.
- **Saved smart filters** — e.g. "installers older than 90 days", one click.
- **Optional folder watching** — a strictly opt-in mode to flag new arrivals
  (off by default; the app stays fully on-demand unless you enable it).
- **Move/organize presets & rules** — remembered organize schemes per folder.
- **Login item toggle** — opt-in only, clearly labeled, never enabled silently.
- **Real file/app icons** in the list (currently SF Symbols by category).
- **Larger duplicate scan** — cross-folder duplicate finding with a progress view.

Every destructive capability follows the same rule already used for Trash and
Organize: **explicit action, recoverable result, clear confirmation, and undo.**

## Notes & limitations

- **"Unknown" is normal.** Files created locally, unzipped, AirDropped, or saved
  before the app that made them wrote WhereFroms have no origin xattr. On a
  typical Downloads folder a large share fall here — the tool still triages them
  by age and last-opened.
- Recursive scans skip `Library` and `node_modules` (system noise); scanning all
  of Home is possible but naturally slower than a single folder.
- Duplicate detection is exact (byte-for-byte SHA-256), not "similar files".
- Trash and Organize are both reversible — Trash via Finder's Trash, Organize via
  the in-app **Undo Organize** button (until the next scan/organize).

## Project layout

```text
Sources/WhereFrom/
  main.swift            # NSStatusItem + popover host, Finder Service, open events
  Provenance.swift      # xattr / WhereFroms / last-used metadata reading
  Categorization.swift  # file-type categories + date buckets
  DownloadsModel.swift  # streaming scan, grouping, cleanup, organizer, trash
  ContentView.swift     # SwiftUI split-view panel (grouping + table + actions)
  QuickLook.swift       # inline Quick Look preview (QLPreviewView)
  AboutView.swift       # About window
make-app.sh             # wraps the release binary into WhereFrom.app (LSUIElement)
install-quick-action.sh # installs the Finder right-click Quick Action
```
