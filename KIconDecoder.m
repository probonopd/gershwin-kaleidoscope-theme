/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "KIconDecoder.h"

/* A 'cicn' is laid out as a PixMap record, the mask's BitMap record, the
 * one-bit icon's BitMap record, a handle placeholder, then the mask bits, the
 * one-bit icon bits, the colour table and finally the colour pixels. Nothing
 * in it is length-prefixed, so the records have to be walked in order and
 * every step checked against what is left. */

#define K_PIXMAP_SIZE   50
#define K_BITMAP_SIZE   14

typedef struct
{
  NSUInteger rowBytes;
  NSInteger left, top, right, bottom;
} KPixelRecord;

static BOOL KReadU16At(const uint8_t *p, NSUInteger len, NSUInteger off,
                       uint16_t *out)
{
  if (off + 2 > len)
    return NO;
  *out = (uint16_t)((p[off] << 8) | p[off + 1]);
  return YES;
}

static BOOL KReadS16At(const uint8_t *p, NSUInteger len, NSUInteger off,
                       int16_t *out)
{
  uint16_t u;

  if (!KReadU16At(p, len, off, &u))
    return NO;
  *out = (int16_t)u;
  return YES;
}

/* rowBytes and the bounding rectangle, which both a PixMap and a BitMap start
 * with at the same offsets. */
static BOOL KReadPixelRecord(const uint8_t *p, NSUInteger len, NSUInteger off,
                             KPixelRecord *out)
{
  uint16_t rowBytes;
  int16_t top, left, bottom, right;

  if (!KReadU16At(p, len, off + 4, &rowBytes)
      || !KReadS16At(p, len, off + 6, &top)
      || !KReadS16At(p, len, off + 8, &left)
      || !KReadS16At(p, len, off + 10, &bottom)
      || !KReadS16At(p, len, off + 12, &right))
    return NO;
  // The top bit of rowBytes only marks the record as a PixMap.
  out->rowBytes = rowBytes & 0x3FFF;
  out->top = top;
  out->left = left;
  out->bottom = bottom;
  out->right = right;
  if (right <= left || bottom <= top)
    return NO;
  // A part of a scheme is a widget, never a poster; this keeps a corrupt
  // header from asking for an enormous allocation.
  if (right - left > 1024 || bottom - top > 1024)
    return NO;
  return YES;
}

@implementation KIconDecoder

+ (NSImage *)imageFromCicn:(NSData *)cicn
{
  const uint8_t *p = (const uint8_t *)[cicn bytes];
  NSUInteger len = [cicn length];
  KPixelRecord pix, mask, bitmap;
  NSUInteger off, width, height, maskHeight, bitmapHeight;
  uint16_t depth;
  int16_t colorCount;
  NSUInteger paletteSize, i, x, y;
  uint8_t *palette;                    /* rgb triples, indexed by pixel value */
  const uint8_t *maskBits;
  const uint8_t *pixels;
  NSBitmapImageRep *rep;
  uint8_t *out;
  NSImage *image;

  if (len < K_PIXMAP_SIZE + 2 * K_BITMAP_SIZE + 4)
    return nil;
  if (!KReadPixelRecord(p, len, 0, &pix))
    return nil;
  if (!KReadU16At(p, len, 32, &depth))
    return nil;
  if (depth != 1 && depth != 2 && depth != 4 && depth != 8)
    return nil;

  off = K_PIXMAP_SIZE;
  if (!KReadPixelRecord(p, len, off, &mask))
    return nil;
  off += K_BITMAP_SIZE;
  if (!KReadPixelRecord(p, len, off, &bitmap))
    return nil;
  off += K_BITMAP_SIZE + 4;            /* the iconData handle is not stored */

  width = pix.right - pix.left;
  height = pix.bottom - pix.top;
  maskHeight = mask.bottom - mask.top;
  bitmapHeight = bitmap.bottom - bitmap.top;

  if (pix.rowBytes * 8 < width * depth || mask.rowBytes * 8 < (NSUInteger)(mask.right - mask.left))
    return nil;

  if (off + mask.rowBytes * maskHeight > len)
    return nil;
  maskBits = p + off;
  off += mask.rowBytes * maskHeight;

  // The one-bit icon is skipped: the colour pixels below are what we draw.
  if (off + bitmap.rowBytes * bitmapHeight > len)
    return nil;
  off += bitmap.rowBytes * bitmapHeight;

  /* ColorTable: seed, flags, then one less than the number of entries. */
  if (!KReadS16At(p, len, off + 6, &colorCount))
    return nil;
  off += 8;
  if (colorCount < 0 || colorCount > 255)
    return nil;

  paletteSize = (NSUInteger)1 << depth;
  palette = calloc(paletteSize, 3);
  if (palette == NULL)
    return nil;

  /* Each entry says which pixel value it is for. Some scheme editors wrote
   * that field as a plain running index instead, so if indexing by value does
   * not fill the entries we were promised, the table is read positionally. */
  {
    NSUInteger placed = 0;

    for (i = 0; i <= (NSUInteger)colorCount; i++)
      {
        NSUInteger e = off + i * 8;
        uint16_t value, r, g, b;

        if (!KReadU16At(p, len, e, &value) || !KReadU16At(p, len, e + 2, &r)
            || !KReadU16At(p, len, e + 4, &g) || !KReadU16At(p, len, e + 6, &b))
          {
            free(palette);
            return nil;
          }
        if (value < paletteSize)
          {
            palette[value * 3 + 0] = r >> 8;
            palette[value * 3 + 1] = g >> 8;
            palette[value * 3 + 2] = b >> 8;
            placed++;
          }
      }
    if (placed <= (NSUInteger)colorCount)
      {
        for (i = 0; i <= (NSUInteger)colorCount && i < paletteSize; i++)
          {
            NSUInteger e = off + i * 8;
            uint16_t r, g, b;

            KReadU16At(p, len, e + 2, &r);
            KReadU16At(p, len, e + 4, &g);
            KReadU16At(p, len, e + 6, &b);
            palette[i * 3 + 0] = r >> 8;
            palette[i * 3 + 1] = g >> 8;
            palette[i * 3 + 2] = b >> 8;
          }
      }
  }
  off += ((NSUInteger)colorCount + 1) * 8;

  if (off + pix.rowBytes * height > len)
    {
      free(palette);
      return nil;
    }
  pixels = p + off;

  rep = [[[NSBitmapImageRep alloc]
    initWithBitmapDataPlanes: NULL
                  pixelsWide: width
                  pixelsHigh: height
               bitsPerSample: 8
             samplesPerPixel: 4
                    hasAlpha: YES
                    isPlanar: NO
              colorSpaceName: NSCalibratedRGBColorSpace
                 bytesPerRow: width * 4
                bitsPerPixel: 32] autorelease];
  if (rep == nil)
    {
      free(palette);
      return nil;
    }
  out = [rep bitmapData];

  for (y = 0; y < height; y++)
    {
      const uint8_t *row = pixels + y * pix.rowBytes;
      const uint8_t *maskRow = maskBits + y * mask.rowBytes;

      for (x = 0; x < width; x++)
        {
          NSUInteger bit = x * depth;
          uint8_t index = (row[bit / 8] >> (8 - depth - (bit % 8)))
            & ((1 << depth) - 1);
          uint8_t *dst = out + (y * width + x) * 4;
          BOOL opaque = YES;

          if (y < maskHeight)
            opaque = (maskRow[x / 8] >> (7 - (x % 8))) & 1;
          dst[0] = palette[index * 3 + 0];
          dst[1] = palette[index * 3 + 1];
          dst[2] = palette[index * 3 + 2];
          dst[3] = opaque ? 255 : 0;
        }
    }
  free(palette);

  image = [[[NSImage alloc] initWithSize: NSMakeSize(width, height)] autorelease];
  [image addRepresentation: rep];
  return image;
}

+ (NSArray *)colorsFromClut:(NSData *)clut
{
  const uint8_t *p = (const uint8_t *)[clut bytes];
  NSUInteger len = [clut length];
  NSMutableArray *colors;
  int16_t count;
  NSUInteger i;

  if (!KReadS16At(p, len, 6, &count) || count < 0 || count > 255)
    return nil;
  colors = [NSMutableArray arrayWithCapacity: count + 1];
  for (i = 0; i <= (NSUInteger)count; i++)
    [colors addObject: [NSColor blackColor]];
  for (i = 0; i <= (NSUInteger)count; i++)
    {
      NSUInteger e = 8 + i * 8;
      uint16_t value, r, g, b;

      if (!KReadU16At(p, len, e, &value) || !KReadU16At(p, len, e + 2, &r)
          || !KReadU16At(p, len, e + 4, &g) || !KReadU16At(p, len, e + 6, &b))
        return nil;
      if (value <= (NSUInteger)count)
        [colors replaceObjectAtIndex: value
                          withObject: [NSColor colorWithCalibratedRed: r / 65535.0
                                                               green: g / 65535.0
                                                                blue: b / 65535.0
                                                               alpha: 1.0]];
    }
  return colors;
}

@end

/* --- The Macintosh system palette ------------------------------------------
 *
 * An icon family member is raw indexed pixels with no colour table of its own;
 * the indices are into the system palette, which is fixed and has to be
 * reproduced here.
 *
 * The 8 bit palette (the classic 'clut' 8) is built, not tabulated, because it
 * is defined by a construction: entries 0 to 214 are a 6x6x6 RGB cube in
 * reverse order, so entry 0 is white; entries 215 to 254 are ten-step ramps of
 * red, then green, then blue, then grey, using the values 0 to 15 with the
 * multiples of 3 left out; and black is moved to entry 255. The cube's own
 * black, which would land at 215, is the entry that gets displaced.
 */

static void KSystemPalette8(uint8_t *rgb)
{
  static const uint8_t ramp[10] = { 238, 221, 187, 170, 136, 119, 85, 68, 34, 17 };
  NSUInteger i;

  for (i = 0; i < 215; i++)
    {
      rgb[i * 3 + 0] = (uint8_t)((5 - (i / 36)) * 51);
      rgb[i * 3 + 1] = (uint8_t)((5 - ((i / 6) % 6)) * 51);
      rgb[i * 3 + 2] = (uint8_t)((5 - (i % 6)) * 51);
    }
  for (i = 0; i < 10; i++)
    {
      rgb[(215 + i) * 3 + 0] = ramp[i];                              /* red */
      rgb[(215 + i) * 3 + 1] = 0;
      rgb[(215 + i) * 3 + 2] = 0;
      rgb[(225 + i) * 3 + 0] = 0;                                  /* green */
      rgb[(225 + i) * 3 + 1] = ramp[i];
      rgb[(225 + i) * 3 + 2] = 0;
      rgb[(235 + i) * 3 + 0] = 0;                                   /* blue */
      rgb[(235 + i) * 3 + 1] = 0;
      rgb[(235 + i) * 3 + 2] = ramp[i];
      rgb[(245 + i) * 3 + 0] = ramp[i];                             /* grey */
      rgb[(245 + i) * 3 + 1] = ramp[i];
      rgb[(245 + i) * 3 + 2] = ramp[i];
    }
  rgb[255 * 3 + 0] = 0;
  rgb[255 * 3 + 1] = 0;
  rgb[255 * 3 + 2] = 0;
}

/* The 4 bit palette is an arbitrary set of sixteen named colours, so unlike
 * the 8 bit one it has to be written out. */
static const uint8_t KSystemPalette4[16][3] = {
  { 0xFF, 0xFF, 0xFF },                /* white */
  { 0xFC, 0xF3, 0x05 },                /* yellow */
  { 0xFF, 0x64, 0x03 },                /* orange */
  { 0xDD, 0x09, 0x07 },                /* red */
  { 0xF2, 0x08, 0x84 },                /* magenta */
  { 0x47, 0x00, 0xA5 },                /* purple */
  { 0x00, 0x00, 0xD3 },                /* blue */
  { 0x02, 0xAB, 0xEA },                /* cyan */
  { 0x1F, 0xB7, 0x14 },                /* green */
  { 0x00, 0x64, 0x12 },                /* dark green */
  { 0x56, 0x2C, 0x05 },                /* brown */
  { 0x90, 0x71, 0x3A },                /* tan */
  { 0xC0, 0xC0, 0xC0 },                /* light grey */
  { 0x80, 0x80, 0x80 },                /* medium grey */
  { 0x40, 0x40, 0x40 },                /* dark grey */
  { 0x00, 0x00, 0x00 }                 /* black */
};

@implementation KIconDecoder (IconFamilies)

+ (NSArray *)systemPaletteOfDepth:(NSInteger)depth
{
  NSMutableArray *colors;
  NSUInteger count, i;
  uint8_t *rgb = NULL;

  if (depth != 1 && depth != 4 && depth != 8)
    return nil;
  count = (NSUInteger)1 << depth;
  colors = [NSMutableArray arrayWithCapacity: count];
  if (depth == 8)
    {
      rgb = calloc(256, 3);
      if (rgb == NULL)
        return nil;
      KSystemPalette8(rgb);
    }
  for (i = 0; i < count; i++)
    {
      const uint8_t *e;

      if (depth == 8)
        e = rgb + i * 3;
      else if (depth == 4)
        e = KSystemPalette4[i];
      else
        e = KSystemPalette4[i == 0 ? 0 : 15];   /* one bit: white and black */
      [colors addObject: [NSColor colorWithCalibratedRed: e[0] / 255.0
                                                   green: e[1] / 255.0
                                                    blue: e[2] / 255.0
                                                   alpha: 1.0]];
    }
  if (rgb != NULL)
    free(rgb);
  return colors;
}

+ (NSImage *)imageFromIconFamilyMember:(NSData *)icon
                                 depth:(NSInteger)depth
                                  mask:(NSData *)mask
{
  const uint8_t *pixels = (const uint8_t *)[icon bytes];
  NSUInteger length = [icon length];
  NSUInteger side, maskRowBytes = 0, x, y;
  const uint8_t *maskBits = NULL;
  uint8_t *palette;
  NSBitmapImageRep *rep;
  uint8_t *out;
  NSImage *image;

  if (depth != 1 && depth != 4 && depth != 8)
    return nil;
  /* Square, and sized entirely by how many bytes there are: 256 bytes at
   * depth 8 is the 16x16 'ics8', 1024 the 32x32 'icl8'. */
  {
    NSUInteger pixelCount = length * 8 / (NSUInteger)depth;

    side = (NSUInteger)(sqrt((double)pixelCount) + 0.5);
    if (side == 0 || side * side != pixelCount || side > 512)
      return nil;
    if ((side * (NSUInteger)depth) % 8 != 0)
      return nil;
  }

  /* An 'ics#' is the one-bit icon followed by its mask, so the mask is the
   * second half. A family member of another depth takes its mask from there. */
  if (mask != nil)
    {
      NSUInteger half = [mask length] / 2;
      NSUInteger rowBytes = (side + 7) / 8;

      if (half == rowBytes * side)
        {
          maskBits = (const uint8_t *)[mask bytes] + half;
          maskRowBytes = rowBytes;
        }
    }

  palette = calloc((NSUInteger)1 << depth, 3);
  if (palette == NULL)
    return nil;
  if (depth == 8)
    KSystemPalette8(palette);
  else
    {
      NSUInteger i, count = (NSUInteger)1 << depth;

      for (i = 0; i < count; i++)
        {
          const uint8_t *e = (depth == 4)
            ? KSystemPalette4[i] : KSystemPalette4[i == 0 ? 0 : 15];

          palette[i * 3 + 0] = e[0];
          palette[i * 3 + 1] = e[1];
          palette[i * 3 + 2] = e[2];
        }
    }

  rep = [[[NSBitmapImageRep alloc]
    initWithBitmapDataPlanes: NULL
                  pixelsWide: side
                  pixelsHigh: side
               bitsPerSample: 8
             samplesPerPixel: 4
                    hasAlpha: YES
                    isPlanar: NO
              colorSpaceName: NSCalibratedRGBColorSpace
                 bytesPerRow: side * 4
                bitsPerPixel: 32] autorelease];
  if (rep == nil)
    {
      free(palette);
      return nil;
    }
  out = [rep bitmapData];

  for (y = 0; y < side; y++)
    {
      NSUInteger rowBits = side * (NSUInteger)depth;

      for (x = 0; x < side; x++)
        {
          NSUInteger bit = y * rowBits + x * (NSUInteger)depth;
          uint8_t index = (pixels[bit / 8] >> (8 - depth - (bit % 8)))
            & ((1 << depth) - 1);
          uint8_t *dst = out + (y * side + x) * 4;
          BOOL opaque = YES;

          if (maskBits != NULL)
            opaque = (maskBits[y * maskRowBytes + x / 8] >> (7 - (x % 8))) & 1;
          dst[0] = palette[index * 3 + 0];
          dst[1] = palette[index * 3 + 1];
          dst[2] = palette[index * 3 + 2];
          dst[3] = opaque ? 255 : 0;
        }
    }
  free(palette);

  image = [[[NSImage alloc] initWithSize: NSMakeSize(side, side)] autorelease];
  [image addRepresentation: rep];
  return image;
}

@end
