/* t_KIconDecoder.m - the colour icon decoder, against a cicn built here.
 * Needs AppKit for NSBitmapImageRep but no display.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>
#import "Testing.h"
#import "KIconDecoder.h"
#import "KTestFixtures.h"

static BOOL ColorIs(NSColor *color, CGFloat r, CGFloat g, CGFloat b)
{
  NSColor *c = [color colorUsingColorSpaceName: NSCalibratedRGBColorSpace];

  return fabs([c redComponent] - r) < 0.01 && fabs([c greenComponent] - g) < 0.01
    && fabs([c blueComponent] - b) < 0.01;
}

static BOOL PixelIs(NSImage *image, NSInteger x, NSInteger y,
                    CGFloat r, CGFloat g, CGFloat b, CGFloat a)
{
  NSBitmapImageRep *rep = (NSBitmapImageRep *)
    [[image representations] objectAtIndex: 0];
  NSColor *c = [[rep colorAtX: x y: y]
    colorUsingColorSpaceName: NSCalibratedRGBColorSpace];

  return fabs([c redComponent] - r) < 0.01 && fabs([c greenComponent] - g) < 0.01
    && fabs([c blueComponent] - b) < 0.01 && fabs([c alphaComponent] - a) < 0.01;
}

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  [NSApplication sharedApplication];

  /* --- a two colour icon decodes to the colours its table names --- */
  {
    NSData *cicn = KMakeCicn(0xFF, 0x00, 0x00, 0x00, 0x00, 0xFF);
    NSImage *image = [KIconDecoder imageFromCicn: cicn];

    PASS(image != nil, "a well formed cicn decodes");
    PASS([image size].width == 2 && [image size].height == 2,
         "the image is the size the PixMap bounds give");
    PASS([[image representations] count] == 1,
         "it carries exactly one representation");
    /* Pixels were laid out 0,1 on the top row and 1,0 on the bottom, and
     * NSBitmapImageRep counts y downwards from the top. */
    PASS(PixelIs(image, 0, 0, 1.0, 0.0, 0.0, 1.0),
         "pixel value 0 takes the first colour table entry");
    PASS(PixelIs(image, 1, 0, 0.0, 0.0, 1.0, 1.0),
         "pixel value 1 takes the second entry");
    PASS(PixelIs(image, 0, 1, 0.0, 0.0, 1.0, 1.0),
         "the bottom left pixel decodes too");
  }

  /* --- the mask becomes the alpha channel --- */
  {
    NSData *cicn = KMakeCicn(0xFF, 0x00, 0x00, 0x00, 0x00, 0xFF);
    NSImage *image = [KIconDecoder imageFromCicn: cicn];

    PASS(PixelIs(image, 0, 0, 1.0, 0.0, 0.0, 1.0),
         "a pixel the mask keeps is opaque");
    /* The fixture's mask clears the bottom right pixel. */
    {
      NSBitmapImageRep *rep = (NSBitmapImageRep *)
        [[image representations] objectAtIndex: 0];
      NSColor *c = [rep colorAtX: 1 y: 1];

      PASS([c alphaComponent] < 0.01,
           "a pixel the mask clears is fully transparent");
    }
  }

  /* --- the colours really come from the table, not from anywhere else --- */
  {
    NSData *green = KMakeCicn(0x00, 0xFF, 0x00, 0xFF, 0xFF, 0xFF);
    NSImage *image = [KIconDecoder imageFromCicn: green];

    PASS(PixelIs(image, 0, 0, 0.0, 1.0, 0.0, 1.0),
         "a different colour table gives different pixels");
    PASS(PixelIs(image, 1, 0, 1.0, 1.0, 1.0, 1.0),
         "white decodes as white");
  }

  /* --- malformed icons are refused --- */
  {
    NSData *good = KMakeCicn(0xFF, 0x00, 0x00, 0x00, 0x00, 0xFF);
    NSMutableData *shortened;
    NSMutableData *silly;
    uint8_t enormous[8] = { 0, 0, 0x7F, 0xFF, 0x7F, 0xFF, 0x7F, 0xFF };

    PASS([KIconDecoder imageFromCicn: [NSData data]] == nil,
         "an empty cicn is refused");
    PASS([KIconDecoder imageFromCicn:
           [@"nonsense" dataUsingEncoding: NSASCIIStringEncoding]] == nil,
         "a cicn shorter than its own records is refused");
    shortened = [[good mutableCopy] autorelease];
    [shortened setLength: [good length] - 3];
    PASS([KIconDecoder imageFromCicn: shortened] == nil,
         "a cicn whose pixels are cut short is refused");
    /* Bounds claiming a gigantic icon must not be believed. */
    silly = [[good mutableCopy] autorelease];
    [silly replaceBytesInRange: NSMakeRange(6, 8) withBytes: enormous length: 8];
    PASS([KIconDecoder imageFromCicn: silly] == nil,
         "a cicn claiming an enormous size is refused");
    PASS_RUNS([KIconDecoder imageFromCicn: silly],
              "a malformed cicn is refused without raising");
  }

  /* --- colour tables --- */
  {
    NSMutableData *clut = [NSMutableData data];
    NSArray *colors;

    KAppend32(clut, 0);                /* ctSeed */
    KAppend16(clut, 0);                /* ctFlags */
    KAppend16(clut, 1);                /* two entries */
    KAppend16(clut, 0);
    KAppend16(clut, 0xFFFF); KAppend16(clut, 0); KAppend16(clut, 0);
    KAppend16(clut, 1);
    KAppend16(clut, 0); KAppend16(clut, 0xFFFF); KAppend16(clut, 0);
    colors = [KIconDecoder colorsFromClut: clut];

    PASS([colors count] == 2, "a clut yields one colour per entry");
    PASS(fabs([[[colors objectAtIndex: 0]
                 colorUsingColorSpaceName: NSCalibratedRGBColorSpace]
                redComponent] - 1.0) < 0.01,
         "entry 0 is the colour the table gives it");
    PASS(fabs([[[colors objectAtIndex: 1]
                 colorUsingColorSpaceName: NSCalibratedRGBColorSpace]
                greenComponent] - 1.0) < 0.01,
         "entry 1 is indexed by its value field, not its position");
    PASS([KIconDecoder colorsFromClut: [NSData data]] == nil,
         "an empty clut is refused");
  }

  /* --- the Macintosh system palette the icon families index --- */
  {
    NSArray *p8 = [KIconDecoder systemPaletteOfDepth: 8];
    NSArray *p4 = [KIconDecoder systemPaletteOfDepth: 4];

    PASS([p8 count] == 256, "the 8 bit palette has 256 entries");
    PASS([p4 count] == 16, "the 4 bit palette has 16");
    PASS([KIconDecoder systemPaletteOfDepth: 3] == nil,
         "a depth the format does not have is refused");
    /* The construction: entry 0 is white, entry 255 is black, and the 6x6x6
     * cube runs in reverse so the greys land on multiples of 51. */
    PASS(ColorIs([p8 objectAtIndex: 0], 1.0, 1.0, 1.0),
         "entry 0 of the 8 bit palette is white");
    PASS(ColorIs([p8 objectAtIndex: 255], 0.0, 0.0, 0.0),
         "entry 255 is black, moved there out of the cube");
    PASS(ColorIs([p8 objectAtIndex: 215], 238 / 255.0, 0.0, 0.0),
         "the red ramp starts where the cube ends");
    PASS(ColorIs([p8 objectAtIndex: 245], 238 / 255.0, 238 / 255.0, 238 / 255.0),
         "the grey ramp is the last of the four");
    PASS(ColorIs([p8 objectAtIndex: 5], 1.0, 1.0, 0.0),
         "the cube's blue axis runs fastest and downwards");
    PASS(ColorIs([p4 objectAtIndex: 0], 1.0, 1.0, 1.0)
         && ColorIs([p4 objectAtIndex: 15], 0.0, 0.0, 0.0),
         "the 4 bit palette runs white to black");
  }

  /* --- an icon family member --- */
  {
    /* Index 255 is black, index 215 the brightest red. */
    NSData *icon = KMakeIcs8(255, 215);
    NSImage *image = [KIconDecoder imageFromIconFamilyMember: icon
                                                       depth: 8
                                                        mask: nil];

    PASS(image != nil, "a 256 byte ics8 decodes");
    PASS([image size].width == 16 && [image size].height == 16,
         "its size comes from the length of the resource, not a header");
    PASS(PixelIs(image, 1, 0, 0.0, 0.0, 0.0, 1.0),
         "a pixel takes the system palette entry its index names");
    PASS(PixelIs(image, 0, 0, 238 / 255.0, 0.0, 0.0, 1.0),
         "and a different index gives a different colour");
    PASS(PixelIs(image, 15, 15, 0.0, 0.0, 0.0, 1.0),
         "with no mask every pixel is opaque");
  }

  /* --- the mask comes from the ics# at the same id --- */
  {
    NSData *icon = KMakeIcs8(255, 215);
    NSImage *image = [KIconDecoder imageFromIconFamilyMember: icon
                                                       depth: 8
                                                        mask: KMakeIcsHash()];
    NSBitmapImageRep *rep;

    PASS(image != nil, "an ics8 with a mask decodes");
    rep = (NSBitmapImageRep *)[[image representations] objectAtIndex: 0];
    PASS([[rep colorAtX: 15 y: 15] alphaComponent] < 0.01,
         "the pixel the ics# mask clears is transparent");
    PASS([[rep colorAtX: 0 y: 0] alphaComponent] > 0.99,
         "the pixels it keeps are opaque");
  }

  /* --- a 32x32 member of the large family --- */
  {
    NSMutableData *big = [NSMutableData dataWithLength: 1024];
    NSImage *image;

    memset([big mutableBytes], 255, 1024);
    image = [KIconDecoder imageFromIconFamilyMember: big depth: 8 mask: nil];
    PASS(image != nil && [image size].width == 32,
         "a 1024 byte icl8 decodes as 32 pixels square");
  }

  /* --- lengths that are not a square, and other refusals --- */
  {
    PASS([KIconDecoder imageFromIconFamilyMember: [NSData data]
                                           depth: 8 mask: nil] == nil,
         "an empty icon is refused");
    PASS([KIconDecoder imageFromIconFamilyMember: [NSMutableData dataWithLength: 300]
                                           depth: 8 mask: nil] == nil,
         "a length that is not a square number is refused");
    PASS([KIconDecoder imageFromIconFamilyMember: KMakeIcs8(0, 0)
                                           depth: 3 mask: nil] == nil,
         "a depth the format does not have is refused");
    PASS_RUNS([KIconDecoder imageFromIconFamilyMember:
                 [NSMutableData dataWithLength: 7] depth: 4 mask: nil],
              "an odd length is refused without raising");
    /* A mask of the wrong size is ignored rather than read out of bounds. */
    PASS([KIconDecoder imageFromIconFamilyMember: KMakeIcs8(255, 215)
                                           depth: 8
                                            mask: [NSMutableData dataWithLength: 9]]
         != nil,
         "a mask of the wrong length is ignored, not trusted");
  }

  [arp release];
  return 0;
}
