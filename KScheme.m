/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "KScheme.h"
#import "KResourceFork.h"
#import "KIconDecoder.h"

@interface KScheme (Private)
- (NSArray *)windowColorTable;
- (NSColor *)colorFromWindowTableAtIndex:(NSUInteger)index;
- (void)readMetadata;
- (NSArray *)stringsFromVers:(NSInteger)resourceId;
@end

/* A Kaleidoscope scheme is a file of this Finder type. The creator is 'Acid',
 * but only the type is checked: it is what Kaleidoscope itself keyed on. */
#define K_SCHEME_TYPE 0x436F6C72          /* 'Colr' */

/* The first of the accent colour tables a scheme can ship: 'clut' 300 is
 * lavender, 301 gold, 302 emerald, and so on. */
#define K_FIRST_ACCENT_CLUT 300
#define K_LAST_ACCENT_CLUT  318

/* The part table: each row is a role and the resource type and id it lives at.
 * Kept in one place so kscdump, the theme and the tests cannot disagree. */
static const struct {
  KSchemePart part;
  NSString *type;
  NSInteger resourceId;
  const char *name;
} KPartTable[] = {
  { KPartButton,               @"cicn", -10239,  "button" },
  { KPartButtonPressed,        @"cicn", -10238,  "button pressed" },
  { KPartButtonDisabled,       @"cicn", -10240,  "button disabled" },
  { KPartDefaultRing,          @"cicn", -10231,  "default button ring" },
  { KPartDefaultRingDisabled,  @"cicn", -10232,  "default button ring disabled" },
  { KPartPopUpMenu,            @"cicn", -8223,   "pop-up menu" },
  { KPartPopUpMenuPressed,     @"cicn", -8222,   "pop-up menu pressed" },
  { KPartPopUpMenuDisabled,    @"cicn", -8224,   "pop-up menu disabled" },
  { KPartPopUpButton,          @"cicn", -8215,   "pop-up button" },
  { KPartPopUpButtonPressed,   @"cicn", -8214,   "pop-up button pressed" },
  { KPartPopUpButtonDisabled,  @"cicn", -8216,   "pop-up button disabled" },
  { KPartScrollTrackV,         @"cicn", -8278,   "vertical scroll track" },
  { KPartScrollTrackVEmpty,    @"cicn", -8279,   "vertical scroll track empty" },
  { KPartScrollTrackVPressed,  @"cicn", -8277,   "vertical scroll track pressed" },
  { KPartScrollTrackVDisabled, @"cicn", -8280,   "vertical scroll track disabled" },
  { KPartScrollTrackH,         @"cicn", -8286,   "horizontal scroll track" },
  { KPartScrollTrackHEmpty,    @"cicn", -8287,   "horizontal scroll track empty" },
  { KPartScrollTrackHPressed,  @"cicn", -8285,   "horizontal scroll track pressed" },
  { KPartScrollTrackHDisabled, @"cicn", -8288,   "horizontal scroll track disabled" },
  { KPartScrollThumbV,         @"cicn", -10208,  "vertical scroll thumb" },
  { KPartScrollThumbVPressed,  @"cicn", -10207,  "vertical scroll thumb pressed" },
  { KPartScrollThumbVGhost,    @"cicn", -8272,   "vertical ghost thumb" },
  { KPartScrollThumbH,         @"cicn", -10206,  "horizontal scroll thumb" },
  { KPartScrollThumbHPressed,  @"cicn", -10205,  "horizontal scroll thumb pressed" },
  { KPartScrollThumbHGhost,    @"cicn", -8271,   "horizontal ghost thumb" },
  { KPartProgressEmpty,        @"cicn", -10224,  "progress bar empty" },
  { KPartProgressFilled,       @"cicn", -10223,  "progress bar filled" },
  { KPartDocumentFrame,        @"cicn", -14332,  "document window" },
  { KPartDocumentTitleBar,     @"cicn", -14331,  "document title bar" },
  { KPartDocumentGrowBox,      @"cicn", -14330,  "document grow box" },
  { KPartDocumentGrowBoxOff,   @"cicn", -14334,  "document grow box disabled" },
  { KPartDialogFrame,          @"cicn", -14326,  "dialog window" },
  { KPartDialogTitleBar,       @"cicn", -14325,  "dialog title bar" },
  { KPartDialogFrameOff,       @"cicn", -14328,  "dialog window disabled" },
  { KPartAlertFrame,           @"cicn", -14322,  "alert window" },
  { KPartAlertTitleBar,        @"cicn", -14321,  "alert title bar" },
  { KPartAlertFrameOff,        @"cicn", -14324,  "alert window disabled" },
  { KPartUtilityFrameTop,      @"cicn", -14316,  "utility window, title bar on top" },
  { KPartUtilityFrameSide,     @"cicn", -14315,  "utility window, title bar at the side" },
  { KPartUtilityTitleBarTop,   @"cicn", -14314,  "utility title bar on top" },
  { KPartUtilityTitleBarSide,  @"cicn", -14318,  "utility title bar at the side" },
  { KPartUtilityGrowBox,       @"cicn", -14313,  "utility grow box" },
  { KPartUtilityFrameTopOff,   @"cicn", -14320,  "utility window disabled, title bar on top" },
  { KPartUtilityFrameSideOff,  @"cicn", -14319,  "utility window disabled, title bar at the side" },
  { KPartUtilityGrowBoxOff,    @"cicn", -14317,  "utility grow box disabled" },
  { KPartFinderHeader,         @"cicn", -14311,  "Finder window header" },
  { KPartFinderHeaderOff,      @"cicn", -14312,  "Finder window header disabled" },
  { KPartMenuBar,              @"cicn", -12288,  "menu bar corners and colours" },
  { KPartMenuSelection,        @"cicn", -12287,  "menu selection colour" },
  { KPartLogo,                 @"cicn", -14305,  "the scheme's own logo" },
  { KPartCheckBox,             @"ics8", -10236,  "check box" },
  { KPartCheckBoxOn,           @"ics8", -10235,  "check box ticked" },
  { KPartCheckBoxMixed,        @"ics8", -10234,  "check box mixed" },
  { KPartCheckBoxPressed,      @"ics8", -10232,  "check box pressed" },
  { KPartCheckBoxOnPressed,    @"ics8", -10231,  "check box ticked, pressed" },
  { KPartCheckBoxMixedPress,   @"ics8", -10230,  "check box mixed, pressed" },
  { KPartCheckBoxOff,          @"ics8", -10240,  "check box disabled" },
  { KPartCheckBoxOnOff,        @"ics8", -10239,  "check box ticked, disabled" },
  { KPartCheckBoxMixedOff,     @"ics8", -10238,  "check box mixed, disabled" },
  { KPartRadio,                @"ics8", -10220,  "radio button" },
  { KPartRadioOn,              @"ics8", -10219,  "radio button selected" },
  { KPartRadioMixed,           @"ics8", -10218,  "radio button mixed" },
  { KPartRadioPressed,         @"ics8", -10216,  "radio button pressed" },
  { KPartRadioOnPressed,       @"ics8", -10215,  "radio button selected, pressed" },
  { KPartRadioMixedPressed,    @"ics8", -10214,  "radio button mixed, pressed" },
  { KPartRadioOff,             @"ics8", -10224,  "radio button disabled" },
  { KPartRadioOnOff,           @"ics8", -10223,  "radio button selected, disabled" },
  { KPartRadioMixedOff,        @"ics8", -10222,  "radio button mixed, disabled" },
  { KPartArrowUp,              @"ics8", -10204,  "scroll arrow up" },
  { KPartArrowDown,            @"ics8", -10203,  "scroll arrow down" },
  { KPartArrowLeft,            @"ics8", -10202,  "scroll arrow left" },
  { KPartArrowRight,           @"ics8", -10201,  "scroll arrow right" },
  { KPartArrowUpPressed,       @"ics8", -10200,  "scroll arrow up pressed" },
  { KPartArrowDownPressed,     @"ics8", -10199,  "scroll arrow down pressed" },
  { KPartArrowLeftPressed,     @"ics8", -10198,  "scroll arrow left pressed" },
  { KPartArrowRightPressed,    @"ics8", -10197,  "scroll arrow right pressed" },
  { KPartArrowUpDisabled,      @"ics8", -10208,  "scroll arrow up disabled" },
  { KPartArrowDownDisabled,    @"ics8", -10207,  "scroll arrow down disabled" },
  { KPartArrowLeftDisabled,    @"ics8", -10206,  "scroll arrow left disabled" },
  { KPartArrowRightDisabled,   @"ics8", -10205,  "scroll arrow right disabled" },
  { KPartCloseBox,             @"ics8", -14336,  "close box" },
  { KPartShadeBox,             @"ics8", -14335,  "WindowShade box" },
  { KPartZoomBox,              @"ics8", -14334,  "zoom box" },
  { KPartCloseBoxPressed,      @"ics8", -14333,  "close box pressed" },
  { KPartShadeBoxPressed,      @"ics8", -14332,  "WindowShade box pressed" },
  { KPartZoomBoxPressed,       @"ics8", -14331,  "zoom box pressed" },
  { KPartCloseBoxUtility,      @"ics8", -14320,  "close box, utility window" },
  { KPartShadeBoxUtility,      @"ics8", -14319,  "WindowShade box, utility window" },
  { KPartZoomBoxUtility,       @"ics8", -14318,  "zoom box, utility window" },
  { KPartCloseBoxUtilPressed,  @"ics8", -14317,  "close box pressed, utility window" },
  { KPartShadeBoxUtilPressed,  @"ics8", -14316,  "WindowShade box pressed, utility window" },
  { KPartZoomBoxUtilPressed,   @"ics8", -14315,  "zoom box pressed, utility window" },
};
static const NSUInteger KPartTableCount
  = sizeof(KPartTable) / sizeof(KPartTable[0]);

NSInteger KResourceIdForPart(KSchemePart part)
{
  NSUInteger i;

  for (i = 0; i < KPartTableCount; i++)
    if (KPartTable[i].part == part)
      return KPartTable[i].resourceId;
  return 0;
}

NSString *KResourceTypeForPart(KSchemePart part)
{
  NSUInteger i;

  for (i = 0; i < KPartTableCount; i++)
    if (KPartTable[i].part == part)
      return KPartTable[i].type;
  return nil;
}

NSString *KNameForPart(KSchemePart part)
{
  NSUInteger i;

  for (i = 0; i < KPartTableCount; i++)
    if (KPartTable[i].part == part)
      return [NSString stringWithUTF8String: KPartTable[i].name];
  return @"none";
}

@implementation KScheme

@synthesize path = _path;
@synthesize name = _name;
@synthesize about = _about;
@synthesize version = _version;
@synthesize hasAccentColors = _hasAccentColors;
@synthesize stretchThumbFromCenter = _stretchThumbFromCenter;

+ (BOOL)isSchemeAtPath:(NSString *)path
{
  KResourceFork *fork = [KResourceFork forkWithContentsOfFile: path];

  return fork != nil && [fork fileType] == K_SCHEME_TYPE;
}

+ (instancetype)schemeWithContentsOfFile:(NSString *)path
{
  KScheme *scheme = [[[self alloc] init] autorelease];
  KResourceFork *fork = [KResourceFork forkWithContentsOfFile: path];

  if (fork == nil || [fork fileType] != K_SCHEME_TYPE)
    return nil;
  // A scheme draws with colour icons and the small icon families. With
  // neither there is nothing to draw, so the file is refused rather than
  // loaded into a theme that would then draw nothing.
  if ([[fork resourceIdsOfType: @"cicn"] count] == 0
      && [[fork resourceIdsOfType: @"ics8"] count] == 0)
    return nil;
  scheme->_fork = [fork retain];
  ASSIGN(scheme->_path, path);
  [scheme readMetadata];
  return scheme;
}

- (id)init
{
  if ((self = [super init]) != nil)
    _images = [[NSMutableDictionary alloc] init];
  return self;
}

- (void)dealloc
{
  [_fork release];
  [_path release];
  [_name release];
  [_about release];
  [_version release];
  [_images release];
  [_accentColors release];
  [super dealloc];
}

/* A 'vers' resource is a version byte pair, a country code, then two Pascal
 * strings: the short version and the long one, which is where a scheme puts
 * its title, author and copyright. */
- (NSArray *)stringsFromVers:(NSInteger)resourceId
{
  NSData *data = [_fork resourceOfType: @"vers" id: resourceId];
  const uint8_t *p;
  NSUInteger len, off, i;
  NSMutableArray *strings;

  if (data == nil || [data length] < 7)
    return nil;
  p = (const uint8_t *)[data bytes];
  len = [data length];
  strings = [NSMutableArray array];
  off = 6;
  for (i = 0; i < 2; i++)
    {
      NSUInteger l;

      if (off >= len)
        break;
      l = p[off];
      if (off + 1 + l > len)
        break;
      [strings addObject:
        [[[NSString alloc] initWithBytes: p + off + 1
                                  length: l
                                encoding: NSMacOSRomanStringEncoding] autorelease]];
      off += 1 + l;
    }
  return strings;
}

- (void)readMetadata
{
  NSArray *vers = [self stringsFromVers: 1];
  NSData *colr;

  if ([vers count] >= 1)
    ASSIGN(_version, [vers objectAtIndex: 0]);
  if ([vers count] >= 2)
    {
      // The long string runs "<name> <version> (c) <year>\r<author>"; the
      // first line is what the scheme calls itself.
      NSString *full = [vers objectAtIndex: 1];
      NSArray *lines = [full componentsSeparatedByCharactersInSet:
        [NSCharacterSet characterSetWithCharactersInString: @"\r\n"]];

      ASSIGN(_about, full);
      if ([lines count] > 0)
        ASSIGN(_name, [[lines objectAtIndex: 0]
          stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceCharacterSet]]);
    }
  // Plenty of schemes put nothing but a version number in 'vers', which is no
  // use as a title, so a name without a single letter in it is discarded in
  // favour of the file name the author gave the scheme.
  if ([_name rangeOfCharacterFromSet:
        [NSCharacterSet letterCharacterSet]].location == NSNotFound)
    DESTROY(_name);
  if ([_name length] == 0)
    ASSIGN(_name, [[_path lastPathComponent] stringByDeletingPathExtension]);

  /* 'Colr': version, format version, minimum Kaleidoscope version, then the
   * two flags. The layout is documented by the scheme's own 'TMPL' 128. */
  colr = [_fork resourceOfType: @"Colr" id: 129];
  if (colr == nil)
    colr = [_fork resourceOfType: @"Colr" id: 128];
  if ([colr length] >= 5)
    {
      const uint8_t *p = (const uint8_t *)[colr bytes];

      _hasAccentColors = (p[3] != 0);
      _stretchThumbFromCenter = (p[4] != 0);
    }
}

- (NSArray *)accentColors
{
  NSMutableArray *tables;
  NSInteger rid;

  if (_accentColors != nil)
    return [_accentColors count] > 0 ? _accentColors : nil;
  tables = [NSMutableArray array];
  for (rid = K_FIRST_ACCENT_CLUT; rid <= K_LAST_ACCENT_CLUT; rid++)
    {
      NSData *clut = [_fork resourceOfType: @"clut" id: rid];
      NSArray *colors = clut != nil ? [KIconDecoder colorsFromClut: clut] : nil;

      if (colors != nil)
        [tables addObject: colors];
    }
  ASSIGN(_accentColors, tables);
  return [tables count] > 0 ? tables : nil;
}

/* The window colour table: 'dctb' -14336 is the dialog one and the only table
 * every scheme was found to carry; 'actb' -14336 is the alert equivalent and
 * is read only when the dialog table is missing, because a scheme is allowed
 * to colour its alerts differently from its windows. */
- (NSArray *)windowColorTable
{
  NSData *table = [_fork resourceOfType: @"dctb" id: -14336];

  if (table == nil)
    table = [_fork resourceOfType: @"actb" id: -14336];
  if (table == nil)
    return nil;
  return [KIconDecoder colorsFromClut: table];
}

- (NSColor *)colorFromWindowTableAtIndex:(NSUInteger)index
{
  NSArray *table = [self windowColorTable];

  return index < [table count] ? [table objectAtIndex: index] : nil;
}

- (NSColor *)bodyColor
{
  return [self colorFromWindowTableAtIndex: 0];
}

- (NSColor *)frameColor
{
  return [self colorFromWindowTableAtIndex: 1];
}

- (NSColor *)textColor
{
  return [self colorFromWindowTableAtIndex: 2];
}

- (NSImage *)imageForPart:(KSchemePart)part
{
  NSNumber *key = [NSNumber numberWithInteger: part];
  id cached = [_images objectForKey: key];
  NSInteger resourceId = KResourceIdForPart(part);
  NSString *type = KResourceTypeForPart(part);
  NSData *res;
  NSImage *image = nil;

  if (cached != nil)
    return cached == [NSNull null] ? nil : cached;
  if (resourceId == 0 || type == nil)
    return nil;
  res = [_fork resourceOfType: type id: resourceId];
  if (res != nil)
    {
      if ([type isEqualToString: @"cicn"])
        image = [KIconDecoder imageFromCicn: res];
      else
        {
          /* An icon family member carries no mask of its own; the mask is the
           * second half of the 'ics#' or 'ICN#' at the same id. */
          NSString *maskType = [type hasPrefix: @"ics"] ? @"ics#" : @"ICN#";
          NSInteger depth = [type hasSuffix: @"4"] ? 4
            : ([type hasSuffix: @"#"] ? 1 : 8);

          image = [KIconDecoder
            imageFromIconFamilyMember: res
                                depth: depth
                                 mask: [_fork resourceOfType: maskType
                                                          id: resourceId]];
        }
    }
  // Remembered either way: a part a scheme does not ship is asked for on
  // every redraw otherwise.
  [_images setObject: (image != nil ? (id)image : (id)[NSNull null]) forKey: key];
  return image;
}

- (BOOL)hasPart:(KSchemePart)part
{
  return [self imageForPart: part] != nil;
}

- (NSArray *)availableParts
{
  NSMutableArray *parts = [NSMutableArray array];
  NSUInteger i;

  for (i = 0; i < KPartTableCount; i++)
    if ([self hasPart: KPartTable[i].part])
      [parts addObject: [NSNumber numberWithInteger: KPartTable[i].part]];
  return parts;
}

@end
