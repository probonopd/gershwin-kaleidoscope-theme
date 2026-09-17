/* t_KScheme.m - the part table, scheme recognition and metadata.
 * Needs AppKit but no display; no network, no bundled scheme.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>
#import "Testing.h"
#import "KScheme.h"
#import "KResourceFork.h"
#import "KTestFixtures.h"

/* A synthetic scheme on disk: a 'Colr' file whose fork holds a cicn at every
 * mapped id, plus whatever extra resources the test wants. */
static NSString *WriteScheme(NSString *tag, NSDictionary *extra, OSType type)
{
  NSMutableDictionary *contents = [NSMutableDictionary dictionary];
  NSMutableDictionary *cicns = [NSMutableDictionary dictionary];
  NSMutableDictionary *ics8s = [NSMutableDictionary dictionary];
  NSMutableDictionary *hashes = [NSMutableDictionary dictionary];
  KSchemePart part;
  NSString *path;
  char typeChars[5];

  /* A part is identified by its resource type as well as its id, so the
   * fixture has to put each one in the family it really lives in. */
  for (part = KPartNone + 1; part < KPartCount; part++)
    {
      NSInteger rid = KResourceIdForPart(part);
      NSString *resType = KResourceTypeForPart(part);
      NSNumber *key = [NSNumber numberWithInteger: rid];

      if (rid == 0 || resType == nil)
        continue;
      if ([resType isEqualToString: @"cicn"])
        [cicns setObject: KMakeCicn(0xDD, 0xDD, 0xDD, 0x22, 0x22, 0x22)
                  forKey: key];
      else
        {
          [ics8s setObject: KMakeIcs8(0, 215) forKey: key];
          [hashes setObject: KMakeIcsHash() forKey: key];
        }
    }
  if ([cicns count] > 0)
    [contents setObject: cicns forKey: @"cicn"];
  if ([ics8s count] > 0)
    {
      [contents setObject: ics8s forKey: @"ics8"];
      [contents setObject: hashes forKey: @"ics#"];
    }
  [contents addEntriesFromDictionary: extra];

  typeChars[0] = (type >> 24) & 0xFF; typeChars[1] = (type >> 16) & 0xFF;
  typeChars[2] = (type >> 8) & 0xFF;  typeChars[3] = type & 0xFF;
  typeChars[4] = 0;
  path = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat: @"k-%@-%d.rsrc", tag, (int)getpid()]];
  [[NSFileManager defaultManager] removeItemAtPath: path error: NULL];
  [KMakeAppleDouble(KMakeFork(contents), typeChars, "Acid")
    writeToFile: path atomically: YES];
  return path;
}

/* A 'vers' resource: version bytes, country, then the short and long strings. */
static NSData *MakeVers(NSString *shortText, NSString *longText)
{
  NSMutableData *d = [NSMutableData data];
  NSData *s = [shortText dataUsingEncoding: NSMacOSRomanStringEncoding];
  NSData *l = [longText dataUsingEncoding: NSMacOSRomanStringEncoding];
  uint8_t len;

  KAppend16(d, 0x0100);                /* version */
  KAppend16(d, 0);                     /* release stage */
  KAppend16(d, 0);                     /* country */
  len = (uint8_t)[s length];
  [d appendBytes: &len length: 1];
  [d appendData: s];
  len = (uint8_t)[l length];
  [d appendBytes: &len length: 1];
  [d appendData: l];
  return d;
}

/* A window colour table, the way a scheme ships it: the classic Dialog
 * Manager part codes, so entry 0 is the content colour, 1 the frame and 2 the
 * text. */
static NSData *MakeWindowColorTable(void)
{
  NSMutableData *d = [NSMutableData data];
  static const uint8_t rgb[5][3] = {
    { 0xCE, 0xFF, 0xCE },              /* 0 content: pale mint */
    { 0x00, 0x00, 0x00 },              /* 1 frame */
    { 0x21, 0x21, 0x21 },              /* 2 text */
    { 0x00, 0x00, 0x00 },              /* 3 hilite */
    { 0xFF, 0xFF, 0xFF }               /* 4 title bar */
  };
  NSUInteger i;

  KAppend32(d, 0);                     /* ctSeed */
  KAppend16(d, 0);                     /* ctFlags */
  KAppend16(d, 4);                     /* five entries */
  for (i = 0; i < 5; i++)
    {
      KAppend16(d, (uint16_t)i);       /* the part code this entry is for */
      KAppend16(d, rgb[i][0] << 8 | rgb[i][0]);
      KAppend16(d, rgb[i][1] << 8 | rgb[i][1]);
      KAppend16(d, rgb[i][2] << 8 | rgb[i][2]);
    }
  return d;
}

static BOOL IsColor(NSColor *color, uint8_t r, uint8_t g, uint8_t b)
{
  NSColor *c = [color colorUsingColorSpaceName: NSCalibratedRGBColorSpace];

  return c != nil
    && fabs([c redComponent] - r / 255.0) < 0.01
    && fabs([c greenComponent] - g / 255.0) < 0.01
    && fabs([c blueComponent] - b / 255.0) < 0.01;
}

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];

  [NSApplication sharedApplication];

  /* --- the part table is well formed --- */
  {
    NSMutableSet *ids = [NSMutableSet set];
    NSMutableSet *names = [NSMutableSet set];
    KSchemePart part;
    BOOL everyPartHasAnId = YES;
    BOOL everyIdIsNegative = YES;
    BOOL idsUnique = YES;
    BOOL namesUnique = YES;
    BOOL everyPartHasAType = YES;

    for (part = KPartNone + 1; part < KPartCount; part++)
      {
        NSInteger rid = KResourceIdForPart(part);
        NSString *name = KNameForPart(part);
        NSString *resType = KResourceTypeForPart(part);
        /* The pair is the identity: 'cicn' -14336 is a grow box while 'ics8'
         * -14336 is a close box, so the id alone is not unique. */
        NSString *key = [NSString stringWithFormat: @"%@/%ld",
          resType, (long)rid];

        if (rid == 0)
          everyPartHasAnId = NO;
        if ([resType length] != 4)
          everyPartHasAType = NO;
        // Schemes keep every part at a negative id; a positive one would mean
        // the table picked up an application's own resource by mistake.
        if (rid >= 0)
          everyIdIsNegative = NO;
        if ([ids containsObject: key])
          idsUnique = NO;
        [ids addObject: key];
        if ([name length] == 0 || [names containsObject: name])
          namesUnique = NO;
        [names addObject: name];
      }
    PASS(everyPartHasAnId, "every part in the enum has a resource id");
    PASS(everyPartHasAType, "every part names a four character resource type");
    PASS(everyIdIsNegative, "every mapped id is negative");
    PASS(idsUnique, "no two parts claim the same resource type and id");
    PASS(namesUnique, "every part has its own name");
    PASS(KResourceIdForPart(KPartNone) == 0, "KPartNone maps to no id");
    PASS(KResourceTypeForPart(KPartNone) == nil, "KPartNone maps to no type");
    /* The mistake this guards against: an id on its own does not identify a
     * widget, because the same number means different things in different
     * resource families. Proven from the table rather than from one hardcoded
     * pair, so it keeps holding as the map grows. */
    {
      NSMutableDictionary *typesById = [NSMutableDictionary dictionary];
      NSUInteger collisions = 0;
      KSchemePart p2;

      for (p2 = KPartNone + 1; p2 < KPartCount; p2++)
        {
          NSNumber *rid = [NSNumber numberWithInteger: KResourceIdForPart(p2)];
          NSString *resType = KResourceTypeForPart(p2);
          NSMutableSet *seenTypes = [typesById objectForKey: rid];

          if (seenTypes == nil)
            {
              seenTypes = [NSMutableSet set];
              [typesById setObject: seenTypes forKey: rid];
            }
          [seenTypes addObject: resType];
        }
      {
        NSEnumerator *e = [typesById objectEnumerator];
        NSMutableSet *seenTypes;

        while ((seenTypes = [e nextObject]) != nil)
          if ([seenTypes count] > 1)
            collisions++;
      }
      PASS(collisions > 0,
           "some ids are used by more than one resource family, so the type"
           " is part of a part's identity");
    }
    PASS_EQUAL(KNameForPart(KPartNone), @"none", "KPartNone is named none");
    PASS(KPartCount > 1, "the table is not empty");
  }

  /* --- recognising a scheme --- */
  {
    NSString *scheme = WriteScheme(@"good", @{}, 0x436F6C72 /* 'Colr' */);
    NSString *notScheme = WriteScheme(@"font", @{}, 0x6666696C /* 'ffil' */);

    PASS([KScheme isSchemeAtPath: scheme],
         "a file of Finder type Colr is a scheme");
    PASS(![KScheme isSchemeAtPath: notScheme],
         "a file of another Finder type is not, whatever it contains");
    PASS(![KScheme isSchemeAtPath: @"/nonexistent/x.rsrc"],
         "a file that is not there is not a scheme");
    PASS([KScheme schemeWithContentsOfFile: notScheme] == nil,
         "a file of the wrong type does not load as a scheme");
    [fm removeItemAtPath: scheme error: NULL];
    [fm removeItemAtPath: notScheme error: NULL];
  }

  /* --- a scheme with no colour icons has nothing to draw with --- */
  {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
      [NSString stringWithFormat: @"k-empty-%d.rsrc", (int)getpid()]];
    NSData *fork = KMakeFork(@{ @"Colr": @{ @128: [NSData dataWithBytes: "\1\1\25\0\0" length: 5] } });

    [KMakeAppleDouble(fork, "Colr", "Acid") writeToFile: path atomically: YES];
    PASS([KScheme schemeWithContentsOfFile: path] == nil,
         "a scheme with no cicn resources is refused rather than half loaded");
    [fm removeItemAtPath: path error: NULL];
  }

  /* --- parts come back as images --- */
  {
    NSString *path = WriteScheme(@"parts", @{}, 0x436F6C72);
    KScheme *scheme = [KScheme schemeWithContentsOfFile: path];
    KSchemePart part;
    BOOL allPresent = YES;

    PASS(scheme != nil, "a scheme with colour icons loads");
    for (part = KPartNone + 1; part < KPartCount; part++)
      if (![scheme hasPart: part])
        allPresent = NO;
    PASS(allPresent, "every mapped part is found when the scheme ships them all");
    PASS([[scheme availableParts] count] == (NSUInteger)(KPartCount - 1),
         "availableParts lists them all");
    PASS([scheme imageForPart: KPartNone] == nil, "KPartNone has no image");
    PASS([[scheme imageForPart: KPartButton] size].width == 2,
         "a colour icon part is the size of its artwork");
    PASS([[scheme imageForPart: KPartCloseBox] size].width == 16,
         "an icon family part is 16 pixels square");
    PASS([scheme imageForPart: KPartButton]
         == [scheme imageForPart: KPartButton],
         "a decoded part is kept, not decoded again on every draw");
    [fm removeItemAtPath: path error: NULL];
  }

  /* --- a scheme that ships only some parts --- */
  {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
      [NSString stringWithFormat: @"k-some-%d.rsrc", (int)getpid()]];
    NSData *cicn = KMakeCicn(0x11, 0x22, 0x33, 0x44, 0x55, 0x66);
    NSNumber *buttonId = [NSNumber numberWithInteger:
      KResourceIdForPart(KPartButton)];
    NSData *fork = KMakeFork(@{ @"cicn": @{ buttonId: cicn } });
    KScheme *scheme;

    [KMakeAppleDouble(fork, "Colr", "Acid") writeToFile: path atomically: YES];
    scheme = [KScheme schemeWithContentsOfFile: path];
    PASS(scheme != nil, "a scheme with one part still loads");
    PASS([scheme hasPart: KPartButton], "the part it ships is found");
    PASS(![scheme hasPart: KPartDocumentGrowBox],
         "a part it does not ship reports absent rather than raising");
    PASS([[scheme availableParts] count] == 1,
         "availableParts lists only what is really there");
    [fm removeItemAtPath: path error: NULL];
  }

  /* --- the name, version and author out of 'vers' --- */
  {
    // Built rather than written as a literal: the copyright sign has to reach
    // the fixture as the MacRoman byte a real scheme stores, which is not what
    // a UTF-8 source file would put there.
    NSString *first = [NSString stringWithFormat:
      @"Apple Gray with Lights 1.5 %C 1997", (unichar)0x00A9];
    NSString *path = WriteScheme(@"named", @{
      @"vers": @{ @1: MakeVers(@"1.5",
                    [NSString stringWithFormat: @"%@\rAkamai Design", first]) }
    }, 0x436F6C72);
    KScheme *scheme = [KScheme schemeWithContentsOfFile: path];

    PASS_EQUAL([scheme version], @"1.5", "the short version string is read");
    PASS_EQUAL([scheme name], first,
               "the name is the first line of the long version string");
    PASS([[scheme about] rangeOfString: @"Akamai Design"].location != NSNotFound,
         "the author line is kept in about");
    [fm removeItemAtPath: path error: NULL];
  }

  /* --- a version number is not a name --- */
  {
    NSString *path = WriteScheme(@"versonly", @{
      @"vers": @{ @1: MakeVers(@"1.0", @"1.0") }
    }, 0x436F6C72);
    KScheme *scheme = [KScheme schemeWithContentsOfFile: path];

    // Plenty of schemes put nothing but a number in 'vers', which is no use as
    // a title, so the file name the author gave it is used instead.
    PASS([[scheme name] rangeOfString: @"versonly"].location != NSNotFound,
         "a name with no letters in it falls back to the file name");
    [fm removeItemAtPath: path error: NULL];
  }

  /* --- a scheme with no 'vers' at all --- */
  {
    NSString *path = WriteScheme(@"nameless", @{}, 0x436F6C72);
    KScheme *scheme = [KScheme schemeWithContentsOfFile: path];

    PASS([[scheme name] length] > 0, "a scheme without 'vers' still has a name");
    [fm removeItemAtPath: path error: NULL];
  }

  /* --- the flags in 'Colr', whose layout the scheme's own TMPL documents --- */
  {
    NSString *path = WriteScheme(@"flags", @{
      /* version, format, minimum Kaleidoscope version, accent, stretch */
      @"Colr": @{ @129: [NSData dataWithBytes: "\1\1\25\1\1" length: 5] }
    }, 0x436F6C72);
    KScheme *scheme = [KScheme schemeWithContentsOfFile: path];

    PASS([scheme hasAccentColors], "the accent colour flag is read");
    PASS([scheme stretchThumbFromCenter], "the SmartScroll flag is read");
    [fm removeItemAtPath: path error: NULL];
  }
  {
    NSString *path = WriteScheme(@"noflags", @{
      @"Colr": @{ @129: [NSData dataWithBytes: "\1\1\25\0\0" length: 5] }
    }, 0x436F6C72);
    KScheme *scheme = [KScheme schemeWithContentsOfFile: path];

    PASS(![scheme hasAccentColors], "a cleared accent flag reads as cleared");
    PASS(![scheme stretchThumbFromCenter], "so does a cleared stretch flag");
    [fm removeItemAtPath: path error: NULL];
  }


  /* --- the colours a scheme states, rather than ones sampled from its art --- */
  {
    NSString *path = WriteScheme(@"colors", @{
      @"dctb": @{ @-14336: MakeWindowColorTable() }
    }, 0x436F6C72);
    KScheme *scheme = [KScheme schemeWithContentsOfFile: path];

    /* Measured against four schemes rendered by Kaleidoscope itself, entry 0
     * of this table is the window body in every one. Sampling the artwork
     * gave the frame colour instead, which is what made a green scheme come
     * out saturated green rather than pale mint. */
    PASS(IsColor([scheme bodyColor], 0xCE, 0xFF, 0xCE),
         "the body colour is entry 0 of the window colour table");
    PASS(IsColor([scheme frameColor], 0x00, 0x00, 0x00),
         "the frame colour is entry 1");
    PASS(IsColor([scheme textColor], 0x21, 0x21, 0x21),
         "the text colour is entry 2");
    [fm removeItemAtPath: path error: NULL];
  }

  /* --- the alert table stands in when there is no dialog table --- */
  {
    NSString *path = WriteScheme(@"altcolors", @{
      @"actb": @{ @-14336: MakeWindowColorTable() }
    }, 0x436F6C72);
    KScheme *scheme = [KScheme schemeWithContentsOfFile: path];

    PASS(IsColor([scheme bodyColor], 0xCE, 0xFF, 0xCE),
         "a scheme with only an alert table still yields a body colour");
    [fm removeItemAtPath: path error: NULL];
  }

  /* --- a scheme that states no colours at all --- */
  {
    NSString *path = WriteScheme(@"nocolors", @{}, 0x436F6C72);
    KScheme *scheme = [KScheme schemeWithContentsOfFile: path];

    // Nil rather than a guess: it is the caller's cue to fall back to
    // something it can defend, and say so.
    PASS([scheme bodyColor] == nil,
         "a scheme with no colour table reports no body colour");
    PASS([scheme textColor] == nil, "and no text colour");
    [fm removeItemAtPath: path error: NULL];
  }

  /* --- the accent tables --- */
  {
    NSMutableData *accent = [NSMutableData data];
    NSString *path;
    KScheme *scheme;

    KAppend32(accent, 0);
    KAppend16(accent, 0);
    KAppend16(accent, 0);              /* one entry */
    KAppend16(accent, 0);
    KAppend16(accent, 0x9999); KAppend16(accent, 0x9999); KAppend16(accent, 0xFFFF);
    path = WriteScheme(@"accent", @{ @"clut": @{ @300: accent } }, 0x436F6C72);
    scheme = [KScheme schemeWithContentsOfFile: path];

    /* 'clut' 300 is the lavender accent, 301 gold, and so on up to 318. */
    PASS([[scheme accentColors] count] == 1,
         "an accent table at clut 300 is found");
    PASS([scheme accentColors] == [scheme accentColors],
         "the accent tables are read once and kept");
    [fm removeItemAtPath: path error: NULL];
  }
  {
    NSString *path = WriteScheme(@"noaccent", @{}, 0x436F6C72);
    KScheme *scheme = [KScheme schemeWithContentsOfFile: path];

    PASS([scheme accentColors] == nil,
         "a scheme with no accent table reports none");
    [fm removeItemAtPath: path error: NULL];
  }

  [arp release];
  return 0;
}
