/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

/* Decoders for the QuickDraw resources a Kaleidoscope scheme draws itself
 * with. Only 'cicn' is read: it is the colour icon, it carries its own colour
 * table and its own mask, and every scheme that draws in colour ships one per
 * part. The 'ics8' and 'ics4' families are the same parts at lower depths,
 * against the system palette, and add nothing we need.
 *
 * Every decoder returns nil for input it cannot read rather than guessing at
 * it: these resources come out of a file downloaded from the internet. */

@interface KIconDecoder : NSObject

/* A colour icon, mask included, as an image whose size is the icon's own
 * pixel size. Nil when the resource is malformed. */
+ (NSImage *)imageFromCicn:(NSData *)cicn;

/* A 'clut' colour table, as an array of NSColor indexed by pixel value.
 * Entries the table does not define come back as black. */
+ (NSArray *)colorsFromClut:(NSData *)clut;

@end

/* The icon families are a separate business from 'cicn': no header, no
 * colour table of their own, and the mask lives in a different resource. */
@interface KIconDecoder (IconFamilies)

/* A member of an icon family: 'ics8' and 'icl8' at 8 bits, 'ics4'/'icl4' at 4,
 * or the icon half of an 'ics#'/'ICN#' at 1. These carry no header at all -
 * just pixels, square, sized by the length of the resource - and they index
 * the Macintosh system palette rather than a table of their own.
 *
 * mask is the matching 'ics#'/'ICN#', whose second half is the mask; pass nil
 * for a fully opaque icon. Nil when the lengths do not add up. */
+ (NSImage *)imageFromIconFamilyMember:(NSData *)icon
                                 depth:(NSInteger)depth
                                  mask:(NSData *)mask;

/* The Macintosh system palette for indexed icons: 256 entries at depth 8, 16
 * at depth 4, 2 at depth 1. Exposed because the part of a scheme that carries
 * a colour is sometimes an icon, so callers sample these too. */
+ (NSArray *)systemPaletteOfDepth:(NSInteger)depth;

@end
