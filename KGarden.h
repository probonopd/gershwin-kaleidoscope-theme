/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

/* Fetching schemes from Mac Themes Garden (https://macthemes.garden), which
 * archives the Kaleidoscope schemes with their authors' names and links each
 * one's original .sit archive.
 *
 * The site has no API. What it does have is an RSS feed of what was added
 * recently and one page per theme carrying the download link and an MD5 beside
 * it, so that is what is used: the feed for browsing, the theme page for the
 * archive. Nothing is scraped in bulk - one page is fetched when the user asks
 * for one theme. */

/* One theme as the listing knows it, before anything is downloaded. */
@interface KGardenScheme : NSObject
{
  NSString *_title;
  NSString *_pageURL;
  NSString *_thumbnailURL;
}
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *pageURL;
@property (nonatomic, copy) NSString *thumbnailURL;
@end

@interface KGarden : NSObject

+ (instancetype)sharedGarden;

/* The recently added themes, from the site's feed. Blocks; call it off the
 * main thread or accept the wait. Nil with error set when the site cannot be
 * reached. */
- (NSArray *)recentSchemesWithError:(NSError **)error;

/* A preview image from the site, fetched only from the site's own hosts.
 * Returns the bytes; the caller makes the NSImage, because that has to
 * happen on the main thread. */
- (NSData *)previewDataForURL:(NSString *)urlString;

/* Called as an archive arrives, with how much of it is in so far: 0 to 1, or
 * -1 while the size is not yet known. Called on the thread that started the
 * download, between runs of its run loop, so a handler may redraw. */
typedef void (^KProgressHandler)(double fraction);

/* Accepts a theme page URL or a bare slug, reads the page for its .sit link
 * and MD5, downloads the archive to a temporary file and checks it against
 * that MD5. Returns the path to the downloaded archive, which the caller
 * hands to KSchemeStore and then deletes. */
- (NSString *)downloadArchiveForSchemePage:(NSString *)pageURLOrSlug
                                    error:(NSError **)error;

/* The same, reporting how far the archive has got. The run loop is run while
 * the download is in flight, so the caller's window keeps drawing. */
- (NSString *)downloadArchiveForSchemePage:(NSString *)pageURLOrSlug
                                  progress:(KProgressHandler)progress
                                     error:(NSError **)error;

@end
