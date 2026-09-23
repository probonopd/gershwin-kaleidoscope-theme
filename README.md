# Kaleidoscope Theme

A GNUstep theme that draws the interface out of a **Kaleidoscope colour
scheme** - the schemes people made for Classic Mac OS between 1997 and 2001 -
and a preference pane that fetches them from
[Mac Themes Garden](https://macthemes.garden) while the desktop is running.

The theme ships no artwork of its own. Click a scheme in the Kaleidoscope
preference pane and every running application follows, without logging out.

## How it works

A Kaleidoscope scheme is a Mac file with an empty data fork; everything is in
its resource fork, as QuickDraw colour icons and icon families at fixed
negative resource ids.

- `KResourceFork` reads the fork out of whatever the unpacker produced
  (AppleDouble sidecar, MacBinary, or the bare fork) and walks the resource
  map. Every offset is bounds checked: these files come off the internet.
- `KIconDecoder` decodes `cicn` colour icons - PixMap, mask, colour table,
  pixels, at 1, 2, 4 and 8 bits - and the icon families `ics8`, `ics4`, `ics#`
  and `icl8`, which carry no header at all and index the Macintosh system
  palette.
- `KScheme` maps resource type and id to interface roles, reads the scheme's
  name, author and version from `vers`, its capability flags from `Colr`, its
  colours from the window colour table and its accent tables from `clut`.
- `Kaleidoscope` is the `GSTheme` subclass. It answers each drawing hook with
  the scheme's own art.
- `KSchemeStore` keeps the user's library in `~/Library/Kaleidoscope/Schemes`
  and installs schemes out of `.sit` archives using The Unarchiver's `unar`.
  One archive often holds several schemes alongside read-mes, icons and
  sometimes fonts; only files whose Finder type is `Colr` are taken.
- `KGarden` fetches from Mac Themes Garden: the RSS feed for browsing, and one
  scheme page per download for the `.sit` link and the MD5 published beside it.

### Where the resource map came from

The format was never documented publicly, but **SchemeChecker 1.4.7**, the
scheme validator Sven Berg Ryen wrote in 1999, is a HyperCard stack carrying a
table of every resource the format uses - 2018 of them, with a description
each. That table is the authority for the map in `KScheme.m`; the role names
there are our own wording for what it describes.

Two things about it are easy to get wrong, and both were got wrong here first:

- **The type matters as much as the id.** `cicn` -14336 is a document window's
  grow box while `ics8` -14336 is its close box. A part is the pair.
- **The obvious widgets are not in `cicn`.** Check boxes, radio buttons, scroll
  arrows and title bar widgets all live in the small icon families. So does the
  collapse box, which Mac OS called *WindowShade* - which is why searching the
  format for "collapse" finds nothing.

92 parts are mapped. `cicn` -14336 is deliberately left out: SchemeChecker
describes both it and -14330 as the active document grow box, so one of them is
something else and guessing would put the wrong picture on a widget.

### Where the colours come from

A scheme states its colours rather than implying them. The body, frame and text
colours are entries 0, 1 and 2 of the window colour table it ships as `dctb`
-14336 (`actb` -14336 is the alert equivalent, read only when the dialog table
is missing). Verified against four schemes rendered by Kaleidoscope itself:

| scheme | measured from its rendered sampler | `dctb` -14336 entry 0 |
| --- | --- | --- |
| Ireland | `#CEFFCE` | `#CEFFCE` |
| Planets - Saturn | `#FFCC00` | `#FFCC00` |
| iMac Bondi | `#CEFFCE` | `#CEFFCE` |
| Younameit II Plus | `#DDDDDD` | `#DDDDDD` |

Sampling the artwork instead does not work: Ireland's buttons are orange while
its window body is pale mint. The bevel highlight and shadow still do come from
the artwork, because that is where they live - no table names them.

`clut` 300 to 318 are the accent colour tables (Lavender, Gold, Emerald,
Turquoise, Crimson, Magenta, Sapphire, Silver and ten more). `KScheme` reads
them; the theme does not use them yet.

### Which scheme is in use

One setting, `KaleidoscopeScheme` in `NSGlobalDomain`. Every running
application's copy of the theme watches it, which is what makes a change take
effect everywhere at once.

It has to be written to the **global** domain explicitly.
`-[NSUserDefaults setObject:forKey:]` writes the running application's own
domain, which is searched first, so a scheme chosen that way changes in
whichever application hosts the preference pane and in no other.

## Building

```bash
gmake                       # the scheme library and the theme
(cd PrefPane && gmake)      # the preference pane
(cd Tests && gmake)         # the tests
(cd Tools/kscdump && gmake) # the developer tool
```

Install (to the SYSTEM domain, which is where the makefiles point). The library
goes in first, since the theme and the pane both link it:

```bash
sudo -E gmake install
(cd PrefPane && sudo -E gmake install)
```

Select the theme, then pick a scheme in System Preferences:

```bash
defaults write NSGlobalDomain GSTheme Kaleidoscope
```

## Tests

```bash
cd Tests && gmake
for t in ./obj/t_*; do "$t"; done
```

159 assertions, all headless and offline. The fixtures build resource forks,
colour icons and icon family members **byte by byte in the test**: no scheme is
bundled, because they belong to their authors and a test that needs one cannot
run on a fresh checkout.

`t_KSchemeStore` exercises the real defaults, saving the selected scheme and
putting it back, so running the tests does not change which scheme the desktop
is using.

## Tools

`Tools/kscdump` is what the map was made with and how to extend it:

```bash
./obj/kscdump <scheme>                # what is in it, and what the theme resolves
./obj/kscdump <scheme> <dir>          # every cicn part as a PNG
./obj/kscdump --icons <scheme> <dir>  # the icon families as PNGs
./obj/kscdump --recent                # what the Garden added lately
./obj/kscdump --download <slug>       # download with progress, verify, discard
./obj/kscdump --select <name>         # choose a scheme the way the pane does
./obj/kscdump --list                  # the library
```

`Tools/panehost` shows one `.prefPane` in a window of its own, which System
Preferences cannot do while another copy of it is running.

## Requirements

- GNUstep (gnustep-make, gnustep-base, gnustep-gui)
- The Unarchiver's `unar`, at `/System/Library/Tools/unar`, for StuffIt
- `/usr/bin/md5sum`, for the download integrity check

## Known gaps

- The theme uses 92 parts; a rich scheme ships three to four times as many, and
  the sliders, tabs and small scroll bars in the table are not wired up yet.
- The accent tables are read but unused.
- Some schemes on the Garden are packaged as Installer VISE applications rather
  than as StuffIt archives of the scheme file. Their payload is in MindVision's
  own compressed format, which `unar` cannot open, so they cannot be installed;
  the pane says so instead of reporting an empty download.

## Credit and licensing

The schemes are **not** part of this software and none are bundled. They are
the work of their original authors, archived by
[Mac Themes Garden](https://macthemes.garden), which states that "all the
themes showcased are the property of their respective authors". This theme
downloads them at the user's request, one at a time.

Kaleidoscope itself was written by Arlo Rose and Greg Landweber. Nothing of it
is used or included here. The resource map was built from the table inside
Sven Berg Ryen's SchemeChecker; only the id-to-role facts are used, not his
wording.

The code in this repository is BSD 2-Clause, see `LICENSE`.
