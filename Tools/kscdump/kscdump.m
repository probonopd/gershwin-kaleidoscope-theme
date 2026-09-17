/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

/* kscdump - lists what is inside a Kaleidoscope scheme and writes every part
 * it can decode out as a PNG.
 *
 * This is how the map from resource id to interface part is built: dump a
 * scheme, look at the pictures, and name what you see. It is also the quickest
 * way to find out why a particular scheme will not load. */

#import <AppKit/AppKit.h>
#import "KResourceFork.h"
#import "KIconDecoder.h"
#import "KScheme.h"
#import "KSchemeStore.h"
#import "KGarden.h"

int main(int argc, const char **argv)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  KResourceFork *fork;
  NSString *path, *outDir;
  NSEnumerator *types;
  NSString *type;
  NSFileManager *fm = [NSFileManager defaultManager];
  NSUInteger written = 0, failed = 0;

  if (argc < 2)
    {
      fprintf(stderr, "usage: kscdump <scheme file> [output directory]\n"
                      "       kscdump --install <archive.sit>\n"
                      "       kscdump --list\n");
      return 1;
    }
  if (strcmp(argv[1], "--download") == 0)
    {
      /* Downloads a scheme the way the preference pane does, printing the
       * progress the pane's bar is driven by. */
      NSError *err = nil;
      NSString *archive;
      __block NSUInteger reports = 0;
      __block double last = -2.0;

      [NSApplication sharedApplication];
      if (argc < 3)
        {
          fprintf(stderr, "kscdump: --download needs a scheme page or slug\n");
          return 1;
        }
      archive = [[KGarden sharedGarden]
        downloadArchiveForSchemePage: [NSString stringWithUTF8String: argv[2]]
                           progress: ^(double fraction) {
          reports++;
          if (fraction != last)
            {
              printf("  progress %6.1f%%\n",
                     fraction < 0 ? 0.0 : fraction * 100.0);
              last = fraction;
            }
        }
                              error: &err];
      if (archive == nil)
        {
          fprintf(stderr, "kscdump: %s\n", [[err localizedDescription] UTF8String]);
          return 1;
        }
      printf("%lu progress reports, archive %s (%lu bytes)\n",
             (unsigned long)reports, [[archive lastPathComponent] UTF8String],
             (unsigned long)[[NSData dataWithContentsOfFile: archive] length]);
      [[NSFileManager defaultManager] removeItemAtPath: archive error: NULL];
      [pool release];
      return 0;
    }
  if (strcmp(argv[1], "--select") == 0)
    {
      /* Selects a scheme exactly the way the preference pane does, so the
       * write path can be checked without a GUI. */
      [NSApplication sharedApplication];
      if (argc < 3)
        {
          fprintf(stderr, "kscdump: --select needs a scheme file name\n");
          return 1;
        }
      [[KSchemeStore sharedStore] selectSchemeWithFileName:
        [NSString stringWithUTF8String: argv[2]]];
      printf("selected %s\n", argv[2]);
      [pool release];
      return 0;
    }
  if (strcmp(argv[1], "--icons") == 0)
    {
      /* Dumps the icon families, which is where the check boxes, radio
       * buttons, scroll arrows and window widgets live. */
      KResourceFork *iconFork;
      NSString *dir;
      NSArray *families = @[@"ics8", @"ics4", @"ics#", @"icl8"];
      NSEnumerator *fe;
      NSString *family;
      NSUInteger wrote = 0;

      [NSApplication sharedApplication];
      if (argc < 4)
        {
          fprintf(stderr, "kscdump: --icons needs a scheme and an output directory\n");
          return 1;
        }
      iconFork = [KResourceFork forkWithContentsOfFile:
                   [NSString stringWithUTF8String: argv[2]]];
      dir = [NSString stringWithUTF8String: argv[3]];
      if (iconFork == nil)
        {
          fprintf(stderr, "kscdump: no readable resource fork\n");
          return 1;
        }
      [[NSFileManager defaultManager] createDirectoryAtPath: dir
                               withIntermediateDirectories: YES
                                                attributes: nil error: NULL];
      fe = [families objectEnumerator];
      while ((family = [fe nextObject]) != nil)
        {
          NSInteger depth = [family isEqualToString: @"ics#"] ? 1
            : ([family hasSuffix: @"4"] ? 4 : 8);
          NSEnumerator *e = [[iconFork resourceIdsOfType: family] objectEnumerator];
          NSNumber *n;

          while ((n = [e nextObject]) != nil)
            {
              NSData *icon = [iconFork resourceOfType: family id: [n integerValue]];
              NSData *mask = [iconFork resourceOfType:
                               ([family hasPrefix: @"ics"] ? @"ics#" : @"ICN#")
                                                   id: [n integerValue]];
              NSImage *image = [KIconDecoder imageFromIconFamilyMember: icon
                                                                depth: depth
                                                                 mask: mask];
              NSString *out;

              if (image == nil)
                continue;
              out = [dir stringByAppendingPathComponent:
                [NSString stringWithFormat: @"%@_%ld.png", family, (long)[n integerValue]]];
              [[[[image representations] objectAtIndex: 0]
                 representationUsingType: NSPNGFileType properties: nil]
                 writeToFile: out atomically: YES];
              wrote++;
            }
        }
      printf("wrote %lu icon family members to %s\n", (unsigned long)wrote,
             [dir UTF8String]);
      [pool release];
      return 0;
    }
  if (strcmp(argv[1], "--preview") == 0)
    {
      NSArray *schemes;
      NSError *err = nil;
      NSUInteger i;

      [NSApplication sharedApplication];
      schemes = [[KGarden sharedGarden] recentSchemesWithError: &err];
      if (schemes == nil)
        {
          fprintf(stderr, "kscdump: %s\n", [[err localizedDescription] UTF8String]);
          return 1;
        }
      for (i = 0; i < 5 && i < [schemes count]; i++)
        {
          KGardenScheme *scheme = [schemes objectAtIndex: i];
          NSString *url = [scheme thumbnailURL];
          NSData *data = url != nil
            ? [[KGarden sharedGarden] previewDataForURL: url] : nil;
          NSImage *image = data != nil
            ? [[NSImage alloc] initWithData: data] : nil;

          printf("%-28s url=%s bytes=%ld image=%s\n",
                 [[scheme title] UTF8String],
                 url != nil ? [url UTF8String] : "(none)",
                 (long)[data length],
                 image != nil ? "ok" : "NIL");
        }
      [pool release];
      return 0;
    }
  if (strcmp(argv[1], "--recent") == 0)
    {
      NSError *err = nil;
      NSArray *themes;
      NSEnumerator *e;
      KGardenScheme *t;

      [NSApplication sharedApplication];
      themes = [[KGarden sharedGarden] recentSchemesWithError: &err];
      if (themes == nil)
        {
          fprintf(stderr, "kscdump: %s\n", [[err localizedDescription] UTF8String]);
          return 1;
        }
      e = [themes objectEnumerator];
      while ((t = [e nextObject]) != nil)
        printf("  %-40s %s\n", [[t title] UTF8String],
               [[[t pageURL] lastPathComponent] UTF8String]);
      printf("%lu themes\n", (unsigned long)[themes count]);
      [pool release];
      return 0;
    }
  if (strcmp(argv[1], "--fetch") == 0)
    {
      NSError *err = nil;
      NSString *archive, *slug;
      NSArray *added;

      [NSApplication sharedApplication];
      if (argc < 3)
        {
          fprintf(stderr, "kscdump: --fetch needs a theme page or slug\n");
          return 1;
        }
      slug = [NSString stringWithUTF8String: argv[2]];
      archive = [[KGarden sharedGarden] downloadArchiveForSchemePage: slug
                                                              error: &err];
      if (archive == nil)
        {
          fprintf(stderr, "kscdump: %s\n", [[err localizedDescription] UTF8String]);
          return 1;
        }
      printf("downloaded %s\n", [archive UTF8String]);
      added = [[KSchemeStore sharedStore] installSchemesFromArchive: archive
                                                              error: &err];
      [[NSFileManager defaultManager] removeItemAtPath: archive error: NULL];
      if (added == nil)
        {
          fprintf(stderr, "kscdump: %s\n", [[err localizedDescription] UTF8String]);
          return 1;
        }
      printf("installed %lu: %s\n", (unsigned long)[added count],
             [[added componentsJoinedByString: @", "] UTF8String]);
      [pool release];
      return 0;
    }
  if (strcmp(argv[1], "--install") == 0 || strcmp(argv[1], "--list") == 0)
    {
      KSchemeStore *store = [KSchemeStore sharedStore];

      [NSApplication sharedApplication];
      if (strcmp(argv[1], "--install") == 0)
        {
          NSError *err = nil;
          NSArray *added;

          if (argc < 3)
            {
              fprintf(stderr, "kscdump: --install needs an archive\n");
              return 1;
            }
          added = [store installSchemesFromArchive:
                     [NSString stringWithUTF8String: argv[2]] error: &err];
          if (added == nil)
            {
              fprintf(stderr, "kscdump: %s\n",
                      [[err localizedDescription] UTF8String]);
              return 1;
            }
          printf("installed %lu: %s\n", (unsigned long)[added count],
                 [[added componentsJoinedByString: @", "] UTF8String]);
        }
      printf("library: %s\n", [[store schemeDirectory] UTF8String]);
      {
        NSEnumerator *e = [[store installedSchemes] objectEnumerator];
        KScheme *s;

        while ((s = [e nextObject]) != nil)
          printf("  %-34s %-10s %lu parts  (%s)\n", [[s name] UTF8String],
                 [[s version] UTF8String] ?: "",
                 (unsigned long)[[s availableParts] count],
                 [[[s path] lastPathComponent] UTF8String]);
      }
      printf("selected: %s\n",
             [[store selectedSchemeFileName] UTF8String] ?: "(none)");
      [pool release];
      return 0;
    }
  [NSApplication sharedApplication];   /* NSBitmapImageRep needs AppKit up */

  path = [NSString stringWithUTF8String: argv[1]];
  outDir = argc > 2 ? [NSString stringWithUTF8String: argv[2]] : nil;

  fork = [KResourceFork forkWithContentsOfFile: path];
  if (fork == nil)
    {
      fprintf(stderr, "kscdump: %s holds no readable resource fork\n", argv[1]);
      return 1;
    }
  printf("type '%s' creator '%s'\n",
         [KStringFromOSType([fork fileType]) UTF8String],
         [KStringFromOSType([fork fileCreator]) UTF8String]);

  types = [[fork resourceTypes] objectEnumerator];
  while ((type = [types nextObject]) != nil)
    {
      NSArray *ids = [fork resourceIdsOfType: type];
      NSUInteger total = 0;
      NSEnumerator *e = [ids objectEnumerator];
      NSNumber *n;

      while ((n = [e nextObject]) != nil)
        total += [[fork resourceOfType: type id: [n integerValue]] length];
      printf("%-6s n=%-4lu bytes=%lu\n", [type UTF8String],
             (unsigned long)[ids count], (unsigned long)total);
    }

  /* What the theme will actually get out of this file. */
  {
    KScheme *scheme = [KScheme schemeWithContentsOfFile: path];

    if (scheme == nil)
      printf("\nnot loadable as a scheme\n");
    else
      {
        KSchemePart part;

        printf("\nscheme name: %s\n", [[scheme name] UTF8String]);
        printf("version:     %s\n", [[scheme version] UTF8String]);
        printf("about:       %s\n",
               [[[scheme about] stringByReplacingOccurrencesOfString: @"\r"
                                                          withString: @" / "] UTF8String]);
        {
          NSColor *body = [scheme bodyColor];
          NSColor *rgb = [body colorUsingColorSpaceName: NSCalibratedRGBColorSpace];

          printf("body color:  %s\n", body == nil ? "(no window colour table)"
            : [[NSString stringWithFormat: @"#%02X%02X%02X",
                (int)([rgb redComponent] * 255 + 0.5),
                (int)([rgb greenComponent] * 255 + 0.5),
                (int)([rgb blueComponent] * 255 + 0.5)] UTF8String]);
        }
        printf("accent colors: %s   stretch thumb from center: %s\n",
               [scheme hasAccentColors] ? "yes" : "no",
               [scheme stretchThumbFromCenter] ? "yes" : "no");
        printf("parts:\n");
        for (part = KPartNone + 1; part < KPartCount; part++)
          printf("  %-34s %-5s %-8ld %s\n", [KNameForPart(part) UTF8String],
                 [KResourceTypeForPart(part) UTF8String],
                 (long)KResourceIdForPart(part),
                 [scheme hasPart: part] ? "present" : "-");
      }
  }

  if (outDir == nil)
    {
      [pool release];
      return 0;
    }
  if (![fm fileExistsAtPath: outDir]
      && ![fm createDirectoryAtPath: outDir withIntermediateDirectories: YES
                         attributes: nil error: NULL])
    {
      fprintf(stderr, "kscdump: cannot create %s\n", [outDir UTF8String]);
      return 1;
    }

  {
    NSEnumerator *e = [[fork resourceIdsOfType: @"cicn"] objectEnumerator];
    NSNumber *n;

    while ((n = [e nextObject]) != nil)
      {
        NSData *res = [fork resourceOfType: @"cicn" id: [n integerValue]];
        NSImage *image = [KIconDecoder imageFromCicn: res];
        NSString *name;
        NSData *png;

        if (image == nil)
          {
            printf("cicn %6ld  UNDECODABLE\n", (long)[n integerValue]);
            failed++;
            continue;
          }
        name = [outDir stringByAppendingPathComponent:
                 [NSString stringWithFormat: @"cicn_%ld.png", (long)[n integerValue]]];
        png = [[[image representations] objectAtIndex: 0]
                representationUsingType: NSPNGFileType properties: nil];
        if (![png writeToFile: name atomically: YES])
          {
            printf("cicn %6ld  COULD NOT WRITE\n", (long)[n integerValue]);
            failed++;
            continue;
          }
        printf("cicn %6ld  %.0fx%.0f -> %s\n", (long)[n integerValue],
               [image size].width, [image size].height,
               [[name lastPathComponent] UTF8String]);
        written++;
      }
  }
  printf("wrote %lu, failed %lu\n", (unsigned long)written, (unsigned long)failed);

  [pool release];
  return failed > 0 ? 1 : 0;
}
