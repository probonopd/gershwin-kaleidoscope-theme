/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

@class KResourceFork;

/* The parts of the interface a scheme draws, as roles rather than as the
 * resource type and id they happen to live at.
 *
 * Which resource means which part is documented by SchemeChecker, the scheme
 * validator Sven Berg Ryen wrote in 1999, which carries a table of every
 * resource the format uses. That table is the authority for this map; the role
 * names below are our own wording for what it describes.
 *
 * Two things about it are easy to get wrong. The type matters as much as the
 * id: 'cicn' -14336 is a document window's grow box while 'ics8' -14336 is its
 * close box, so a part is identified by the pair. And the widgets that look
 * like the obvious candidates in the 'cicn' block are not: check boxes, radio
 * buttons, scroll arrows and title bar widgets all live in the small icon
 * families, not in 'cicn'.
 */
typedef NS_ENUM(NSInteger, KSchemePart) {
    KPartNone = 0,

    /* Push buttons and the ring around the default one. */
    KPartButton,
    KPartButtonPressed,
    KPartButtonDisabled,
    KPartDefaultRing,
    KPartDefaultRingDisabled,

    /* Pop-up menus and pop-up buttons. */
    KPartPopUpMenu,
    KPartPopUpMenuPressed,
    KPartPopUpMenuDisabled,
    KPartPopUpButton,
    KPartPopUpButtonPressed,
    KPartPopUpButtonDisabled,

    /* Scroll bar tracks, per orientation and state. */
    KPartScrollTrackV,
    KPartScrollTrackVEmpty,
    KPartScrollTrackVPressed,
    KPartScrollTrackVDisabled,
    KPartScrollTrackH,
    KPartScrollTrackHEmpty,
    KPartScrollTrackHPressed,
    KPartScrollTrackHDisabled,

    /* Scroll bar thumbs. The ghost thumb is what Kaleidoscope draws while
     * a proportional thumb is being dragged. */
    KPartScrollThumbV,
    KPartScrollThumbVPressed,
    KPartScrollThumbVGhost,
    KPartScrollThumbH,
    KPartScrollThumbHPressed,
    KPartScrollThumbHGhost,

    /* Progress bars: the empty trough and the filled part. */
    KPartProgressEmpty,
    KPartProgressFilled,

    /* Window frames and title bars, per window kind. A scheme draws the
     * frame and the bar as separate pieces, and has a disabled version of
     * each for a window that is not in front. */
    KPartDocumentFrame,
    KPartDocumentTitleBar,
    KPartDocumentGrowBox,
    KPartDocumentGrowBoxOff,
    KPartDialogFrame,
    KPartDialogTitleBar,
    KPartDialogFrameOff,
    KPartAlertFrame,
    KPartAlertTitleBar,
    KPartAlertFrameOff,
    KPartUtilityFrameTop,
    KPartUtilityFrameSide,
    KPartUtilityTitleBarTop,
    KPartUtilityTitleBarSide,
    KPartUtilityGrowBox,
    KPartUtilityFrameTopOff,
    KPartUtilityFrameSideOff,
    KPartUtilityGrowBoxOff,
    KPartFinderHeader,
    KPartFinderHeaderOff,
    KPartMenuBar,
    KPartMenuSelection,
    KPartLogo,

    /* Check boxes. Kaleidoscope has a mixed state as well as on and off,
     * and a pressed and a disabled version of all three. */
    KPartCheckBox,
    KPartCheckBoxOn,
    KPartCheckBoxMixed,
    KPartCheckBoxPressed,
    KPartCheckBoxOnPressed,
    KPartCheckBoxMixedPress,
    KPartCheckBoxOff,
    KPartCheckBoxOnOff,
    KPartCheckBoxMixedOff,

    /* Radio buttons, with the same nine states as check boxes. */
    KPartRadio,
    KPartRadioOn,
    KPartRadioMixed,
    KPartRadioPressed,
    KPartRadioOnPressed,
    KPartRadioMixedPressed,
    KPartRadioOff,
    KPartRadioOnOff,
    KPartRadioMixedOff,

    /* Scroll bar arrows: four directions, three states each. */
    KPartArrowUp,
    KPartArrowDown,
    KPartArrowLeft,
    KPartArrowRight,
    KPartArrowUpPressed,
    KPartArrowDownPressed,
    KPartArrowLeftPressed,
    KPartArrowRightPressed,
    KPartArrowUpDisabled,
    KPartArrowDownDisabled,
    KPartArrowLeftDisabled,
    KPartArrowRightDisabled,

    /* Title bar widgets. WindowShade is what Mac OS called collapsing a
     * window to its title bar. */
    KPartCloseBox,
    KPartShadeBox,
    KPartZoomBox,
    KPartCloseBoxPressed,
    KPartShadeBoxPressed,
    KPartZoomBoxPressed,
    KPartCloseBoxUtility,
    KPartShadeBoxUtility,
    KPartZoomBoxUtility,
    KPartCloseBoxUtilPressed,
    KPartShadeBoxUtilPressed,
    KPartZoomBoxUtilPressed,

    KPartCount
};

/* One Kaleidoscope colour scheme, loaded from the file a .sit unpacks to.
 *
 * A scheme file has no data fork; everything is in the resource fork, so this
 * is a thin layer over KResourceFork that knows which resource means what. */
@interface KScheme : NSObject
{
  KResourceFork *_fork;
  NSString *_path;
  NSString *_name;
  NSString *_about;
  NSString *_version;
  NSMutableDictionary *_images;        /* part number -> NSImage */
  NSArray *_accentColors;              /* NSColor, from the accent clut */
  BOOL _hasAccentColors;
  BOOL _stretchThumbFromCenter;
}

/* Nil unless the file really is a scheme: the Finder type must be 'Colr' and
 * the fork must hold the parts we draw with. Nothing is guessed. */
+ (instancetype)schemeWithContentsOfFile:(NSString *)path;

/* YES when the file at path is a Kaleidoscope scheme, judged by its Finder
 * type. Used to pick the scheme out of an unpacked archive, which also holds
 * read-me files, icons and sometimes fonts. */
+ (BOOL)isSchemeAtPath:(NSString *)path;

@property (nonatomic, readonly) NSString *path;
/* The scheme's own name for itself, from its 'vers' resource, falling back to
 * the file name when it carries none. */
@property (nonatomic, readonly) NSString *name;
/* The long version string, which is where a scheme puts its author and
 * copyright; nil when it has none. */
@property (nonatomic, readonly) NSString *about;
@property (nonatomic, readonly) NSString *version;

/* From the scheme's 'Colr' resource, whose layout its own 'TMPL' documents. */
@property (nonatomic, readonly) BOOL hasAccentColors;
@property (nonatomic, readonly) BOOL stretchThumbFromCenter;

/* The scheme's accent colours, from the 'clut' it ships at 300 and up - one
 * table per accent, in the order Kaleidoscope named them (lavender, gold,
 * emerald, turquoise, crimson, magenta, sapphire, silver and ten more). Nil
 * when the scheme ships none. */
- (NSArray *)accentColors;

/* The colours a scheme states outright, rather than ones guessed at from its
 * artwork. They come from the window colour table it ships as 'dctb' -14336,
 * whose entries are indexed by the classic Dialog Manager part codes: 0 is the
 * content colour, 1 the frame, 2 the text. Measured against four schemes of
 * very different looks, entry 0 is the window body in every one.
 *
 * Nil when the scheme ships no such table, which is the caller's cue to fall
 * back to something it can defend. */
- (NSColor *)bodyColor;
- (NSColor *)frameColor;
- (NSColor *)textColor;

/* The art for a part, or nil when this scheme does not ship that part.
 * Decoded once and kept. */
- (NSImage *)imageForPart:(KSchemePart)part;
- (BOOL)hasPart:(KSchemePart)part;

/* Every part this scheme could supply, as NSNumbers; for diagnostics. */
- (NSArray *)availableParts;

@end

/* The resource id a part lives at, or 0 for KPartNone. */
NSInteger KResourceIdForPart(KSchemePart part);
/* The four-character resource type a part lives in, or nil for KPartNone. */
NSString *KResourceTypeForPart(KSchemePart part);
/* A short name for a part, for logs and for kscdump. */
NSString *KNameForPart(KSchemePart part);
