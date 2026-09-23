/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

/* Resource forks and colour icons built byte by byte in the tests.
 *
 * No scheme is bundled with these tests: the schemes on Mac Themes Garden
 * belong to their authors, and a test that needs one of them to run is a test
 * that cannot run on a fresh checkout. Everything here is synthetic, which also
 * means each test says exactly which bytes it is about. */

#import <Foundation/Foundation.h>

/* Appends big-endian integers, the way a resource fork stores them. */
static inline void KAppend16(NSMutableData *d, uint16_t v)
{
  uint8_t b[2] = { (uint8_t)(v >> 8), (uint8_t)v };

  [d appendBytes: b length: 2];
}

static inline void KAppend32(NSMutableData *d, uint32_t v)
{
  uint8_t b[4] = { (uint8_t)(v >> 24), (uint8_t)(v >> 16),
                   (uint8_t)(v >> 8), (uint8_t)v };

  [d appendBytes: b length: 4];
}

/* A 2x2 one-bit 'cicn': pixel 0 is the first colour table entry, pixel 1 the
 * second, and the mask hides the bottom right pixel. */
static inline NSData *KMakeCicn(uint8_t r0, uint8_t g0, uint8_t b0,
                                uint8_t r1, uint8_t g1, uint8_t b1)
{
  NSMutableData *d = [NSMutableData data];
  NSUInteger i;

  /* IconPMap: a PixMap record. rowBytes carries the 0x8000 PixMap marker. */
  KAppend32(d, 0);                     /* baseAddr */
  KAppend16(d, 0x8000 | 2);            /* rowBytes */
  KAppend16(d, 0); KAppend16(d, 0);    /* bounds top, left */
  KAppend16(d, 2); KAppend16(d, 2);    /* bounds bottom, right */
  KAppend16(d, 0);                     /* pmVersion */
  KAppend16(d, 0);                     /* packType */
  KAppend32(d, 0);                     /* packSize */
  KAppend32(d, 72 << 16);              /* hRes */
  KAppend32(d, 72 << 16);              /* vRes */
  KAppend16(d, 0);                     /* pixelType */
  KAppend16(d, 1);                     /* pixelSize: one bit */
  KAppend16(d, 1);                     /* cmpCount */
  KAppend16(d, 1);                     /* cmpSize */
  KAppend32(d, 0);                     /* planeBytes */
  KAppend32(d, 0);                     /* pmTable */
  KAppend32(d, 0);                     /* pmReserved */

  /* iconMask, then iconBMap: two BitMap records of the same 2x2 bounds. */
  for (i = 0; i < 2; i++)
    {
      KAppend32(d, 0);                 /* baseAddr */
      KAppend16(d, 2);                 /* rowBytes */
      KAppend16(d, 0); KAppend16(d, 0);
      KAppend16(d, 2); KAppend16(d, 2);
    }
  KAppend32(d, 0);                     /* the iconData handle is not stored */

  /* Mask bits: top row both pixels opaque, bottom row only the left one. */
  {
    uint8_t mask[4] = { 0xC0, 0x00, 0x80, 0x00 };

    [d appendBytes: mask length: 4];
  }
  /* The one-bit icon, which the decoder skips over. */
  {
    uint8_t bits[4] = { 0x00, 0x00, 0x00, 0x00 };

    [d appendBytes: bits length: 4];
  }

  /* ColorTable: seed, flags, then one less than the number of entries. */
  KAppend32(d, 0);                     /* ctSeed */
  KAppend16(d, 0);                     /* ctFlags */
  KAppend16(d, 1);                     /* ctSize: two entries */
  KAppend16(d, 0);                                                  /* value 0 */
  KAppend16(d, r0 << 8 | r0); KAppend16(d, g0 << 8 | g0); KAppend16(d, b0 << 8 | b0);
  KAppend16(d, 1);                                                  /* value 1 */
  KAppend16(d, r1 << 8 | r1); KAppend16(d, g1 << 8 | g1); KAppend16(d, b1 << 8 | b1);

  /* Pixels: 0,1 on the top row and 1,0 on the bottom. */
  {
    uint8_t pixels[4] = { 0x40, 0x00, 0x80, 0x00 };

    [d appendBytes: pixels length: 4];
  }
  return d;
}

/* A resource fork holding the given resources: type -> (id number -> NSData).
 * Written in the same layout the reader expects, so a test can prove the reader
 * against a fork whose every field it chose. */
static inline NSData *KMakeFork(NSDictionary *resources)
{
  NSMutableData *data = [NSMutableData data];
  NSMutableData *body = [NSMutableData data];
  NSMutableData *map = [NSMutableData data];
  NSArray *types = [[resources allKeys]
    sortedArrayUsingSelector: @selector(compare:)];
  NSMutableArray *offsets = [NSMutableArray array];
  NSUInteger typeCount = [types count];
  NSUInteger refListSize = 0;
  NSEnumerator *e;
  NSString *type;
  NSUInteger typeIndex;

  /* Resource data: each entry is a length then its bytes. */
  e = [types objectEnumerator];
  while ((type = [e nextObject]) != nil)
    {
      NSDictionary *byId = [resources objectForKey: type];
      NSArray *ids = [[byId allKeys] sortedArrayUsingSelector: @selector(compare:)];
      NSEnumerator *ie = [ids objectEnumerator];
      NSNumber *n;

      refListSize += [ids count] * 12;
      while ((n = [ie nextObject]) != nil)
        {
          NSData *res = [byId objectForKey: n];

          [offsets addObject: [NSNumber numberWithUnsignedInteger: [body length]]];
          KAppend32(body, (uint32_t)[res length]);
          [body appendData: res];
        }
    }

  /* Resource map: 16 reserved bytes, next map, file ref, attributes, then the
   * offsets of the type list and the name list, both relative to the map. */
  [map appendBytes: "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0" length: 16];
  KAppend32(map, 0);
  KAppend16(map, 0);
  KAppend16(map, 0);
  KAppend16(map, 28);                                  /* type list offset */
  KAppend16(map, (uint16_t)(28 + 2 + typeCount * 8 + refListSize)); /* names */
  KAppend16(map, (uint16_t)(typeCount - 1));

  {
    NSUInteger refOffset = 2 + typeCount * 8;

    e = [types objectEnumerator];
    while ((type = [e nextObject]) != nil)
      {
        NSDictionary *byId = [resources objectForKey: type];
        const char *t = [type UTF8String];

        [map appendBytes: t length: 4];
        KAppend16(map, (uint16_t)([byId count] - 1));
        KAppend16(map, (uint16_t)refOffset);
        refOffset += [byId count] * 12;
      }
  }
  typeIndex = 0;
  e = [types objectEnumerator];
  while ((type = [e nextObject]) != nil)
    {
      NSDictionary *byId = [resources objectForKey: type];
      NSArray *ids = [[byId allKeys] sortedArrayUsingSelector: @selector(compare:)];
      NSEnumerator *ie = [ids objectEnumerator];
      NSNumber *n;

      while ((n = [ie nextObject]) != nil)
        {
          NSUInteger off = [[offsets objectAtIndex: typeIndex++] unsignedIntegerValue];

          KAppend16(map, (uint16_t)(int16_t)[n integerValue]);
          KAppend16(map, 0xFFFF);                      /* no name */
          KAppend32(map, (uint32_t)off);               /* attributes are zero */
          KAppend32(map, 0);                           /* handle placeholder */
        }
    }

  /* Header: where the data and the map are, and how long each is. */
  KAppend32(data, 256);
  KAppend32(data, (uint32_t)(256 + [body length]));
  KAppend32(data, (uint32_t)[body length]);
  KAppend32(data, (uint32_t)[map length]);
  [data increaseLengthBy: 256 - [data length]];
  [data appendData: body];
  [data appendData: map];
  return data;
}

/* Wraps a resource fork in an AppleDouble sidecar with the given Finder type,
 * which is what the unpacker hands us for a real scheme. */
static inline NSData *KMakeAppleDouble(NSData *fork, const char *type,
                                       const char *creator)
{
  NSMutableData *d = [NSMutableData data];
  NSUInteger finderOffset = 26 + 2 * 12;
  NSUInteger forkOffset = finderOffset + 32;

  KAppend32(d, 0x00051607);            /* AppleDouble magic */
  KAppend32(d, 0x00020000);            /* version 2 */
  [d increaseLengthBy: 16];            /* filler */
  KAppend16(d, 2);                     /* two entries */
  KAppend32(d, 9);                     /* Finder info */
  KAppend32(d, (uint32_t)finderOffset);
  KAppend32(d, 32);
  KAppend32(d, 2);                     /* resource fork */
  KAppend32(d, (uint32_t)forkOffset);
  KAppend32(d, (uint32_t)[fork length]);
  [d appendBytes: type length: 4];
  [d appendBytes: creator length: 4];
  [d increaseLengthBy: 24];            /* the rest of the Finder info */
  [d appendData: fork];
  return d;
}

/* Wraps a resource fork in a MacBinary II file with the given Finder type and
 * no data fork. unar takes it as an archive of one file, which is how a test
 * can hand the store an archive without building a StuffIt one. The header CRC
 * is filled in because unar will not recognise the format without it. */
static inline NSData *KMakeMacBinary(NSData *fork, const char *name,
                                     const char *type, const char *creator)
{
  NSMutableData *d = [NSMutableData dataWithLength: 128];
  uint8_t *h = [d mutableBytes];
  size_t nameLength = strlen(name);
  uint16_t crc = 0;
  NSUInteger i;
  int bit;

  h[1] = (uint8_t)nameLength;
  memcpy(h + 2, name, nameLength);
  memcpy(h + 65, type, 4);
  memcpy(h + 69, creator, 4);
  h[87] = (uint8_t)([fork length] >> 24);
  h[88] = (uint8_t)([fork length] >> 16);
  h[89] = (uint8_t)([fork length] >> 8);
  h[90] = (uint8_t)[fork length];
  h[122] = 129;                        /* written by MacBinary II */
  h[123] = 129;                        /* readable by MacBinary II */
  for (i = 0; i < 124; i++)            /* CRC-16/XMODEM */
    {
      crc ^= (uint16_t)(h[i] << 8);
      for (bit = 0; bit < 8; bit++)
        crc = (crc & 0x8000) ? (uint16_t)((crc << 1) ^ 0x1021)
                             : (uint16_t)(crc << 1);
    }
  h[124] = (uint8_t)(crc >> 8);
  h[125] = (uint8_t)crc;
  [d appendData: fork];
  [d increaseLengthBy: (128 - [fork length] % 128) % 128];
  return d;
}

/* A 16x16 'ics8': raw indices into the Macintosh system palette, no header.
 * Fills the whole icon with one index except the top left pixel, which takes
 * the second, so a test can tell the two apart. */
static inline NSData *KMakeIcs8(uint8_t index, uint8_t corner)
{
  NSMutableData *d = [NSMutableData dataWithLength: 256];
  uint8_t *p = (uint8_t *)[d mutableBytes];
  NSUInteger i;

  for (i = 0; i < 256; i++)
    p[i] = index;
  p[0] = corner;
  return d;
}

/* A 16x16 'ics#': the one-bit icon followed by its mask, 32 bytes each. The
 * mask keeps everything except the bottom right pixel. */
static inline NSData *KMakeIcsHash(void)
{
  NSMutableData *d = [NSMutableData dataWithLength: 64];
  uint8_t *p = (uint8_t *)[d mutableBytes];
  NSUInteger i;

  for (i = 0; i < 32; i++)
    p[i] = 0xFF;                       /* the icon itself, all set */
  for (i = 32; i < 64; i++)
    p[i] = 0xFF;                       /* the mask, all opaque */
  p[63] = 0xFE;                        /* except the last pixel of the last row */
  return d;
}
