/* t_KGarden.m - what the Mac Themes Garden client accepts as an address, and
 * which hosts it is willing to fetch from.
 *
 * Deliberately offline: every case here is refused before a request is made,
 * so the suite does not depend on the network or put load on someone else's
 * server. The fetching itself is exercised by hand with kscdump --recent,
 * --download and --preview.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>
#import "Testing.h"
#import "KGarden.h"

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  KGarden *garden;

  [NSApplication sharedApplication];
  garden = [KGarden sharedGarden];

  PASS(garden != nil, "there is a shared garden");
  PASS(garden == [KGarden sharedGarden], "and it is shared");

  /* --- addresses that are refused without asking the network --- */
  {
    NSError *error = nil;

    PASS([garden downloadArchiveForSchemePage: @"" error: &error] == nil
         && error != nil,
         "an empty address is refused, with a reason");
    error = nil;
    PASS([garden downloadArchiveForSchemePage: nil error: &error] == nil,
         "a nil address is refused");
    error = nil;
    /* A scheme page is read for a download link, so the page itself has to be
     * on the site: anything else would make this a general purpose fetcher
     * pointed by whatever wrote the defaults. */
    PASS([garden downloadArchiveForSchemePage: @"https://example.com/themes/x"
                                        error: &error] == nil
         && error != nil,
         "a page on another site is refused");
    error = nil;
    PASS([garden downloadArchiveForSchemePage:
           @"https://macthemes.garden.evil.example/themes/x" error: &error] == nil,
         "a host that merely starts with the site's name is refused");
    error = nil;
    PASS([garden downloadArchiveForSchemePage: @"http://macthemes.garden/themes/x"
                                        error: &error] == nil,
         "plain http is refused even on the right host");
    PASS_RUNS([garden downloadArchiveForSchemePage: @"" error: NULL],
              "a caller that does not want the error is not required to take one");
  }

  /* --- preview pictures come only from the site's own hosts --- */
  {
    PASS([garden previewDataForURL: @"https://example.com/x.png"] == nil,
         "a picture on another host is not fetched");
    PASS([garden previewDataForURL: @"http://macthemes.garden/x.png"] == nil,
         "a picture over plain http is not fetched");
    PASS([garden previewDataForURL: @"not a url at all"] == nil,
         "something that is not an address is not fetched");
    PASS([garden previewDataForURL: @""] == nil, "nor is an empty one");
    PASS([garden previewDataForURL: nil] == nil, "nor nil");
    PASS([garden previewDataForURL:
           @"https://cdn.macthemes.garden.evil.example/x.png"] == nil,
         "nor a host that merely starts with the cdn's name");
  }

  /* --- a listing entry carries what the pane needs --- */
  {
    KGardenScheme *scheme = AUTORELEASE([[KGardenScheme alloc] init]);

    [scheme setTitle: @"Persephone's Torch"];
    [scheme setPageURL: @"https://macthemes.garden/themes/abc-Persephones-Torch"];
    [scheme setThumbnailURL: @"https://cdn.macthemes.garden/themes/attachments/x.png"];
    PASS_EQUAL([scheme title], @"Persephone's Torch",
               "a listing entry keeps its title, apostrophe and all");
    PASS_EQUAL([scheme pageURL],
               @"https://macthemes.garden/themes/abc-Persephones-Torch",
               "and its page address");
    PASS_EQUAL([scheme thumbnailURL],
               @"https://cdn.macthemes.garden/themes/attachments/x.png",
               "and the picture to show for it");
  }

  [arp release];
  return 0;
}
