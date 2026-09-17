/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

/* Everything here reads a file that came off the internet, so every offset is
 * checked against the length before it is used and anything that does not add
 * up makes the whole fork unreadable. A scheme we cannot parse is refused, not
 * guessed at. */

#import "KResourceFork.h"

@interface KResourceFork (Parsing)
- (BOOL)parseWrapper:(NSData *)data;
- (BOOL)parseResourceMap;
@end

NSString *KStringFromOSType(OSType type)
{
  unichar c[4];
  NSUInteger i;

  for (i = 0; i < 4; i++)
    {
      unichar ch = (type >> (8 * (3 - i))) & 0xFF;

      c[i] = (ch >= 32 && ch < 127) ? ch : '?';
    }
  return [NSString stringWithCharacters: c length: 4];
}

/* Bounds-checked big-endian reads. Each returns NO when the range asked for
 * does not lie inside the data. */

static BOOL KReadU8(NSData *d, NSUInteger off, uint8_t *out)
{
  if (off >= [d length])
    return NO;
  [d getBytes: out range: NSMakeRange(off, 1)];
  return YES;
}

static BOOL KReadU16(NSData *d, NSUInteger off, uint16_t *out)
{
  uint8_t b[2];

  if (off + 2 > [d length])
    return NO;
  [d getBytes: b range: NSMakeRange(off, 2)];
  *out = (uint16_t)((b[0] << 8) | b[1]);
  return YES;
}

static BOOL KReadS16(NSData *d, NSUInteger off, int16_t *out)
{
  uint16_t u;

  if (!KReadU16(d, off, &u))
    return NO;
  *out = (int16_t)u;
  return YES;
}

static BOOL KReadU32(NSData *d, NSUInteger off, uint32_t *out)
{
  uint8_t b[4];

  if (off + 4 > [d length])
    return NO;
  [d getBytes: b range: NSMakeRange(off, 4)];
  *out = ((uint32_t)b[0] << 24) | ((uint32_t)b[1] << 16)
    | ((uint32_t)b[2] << 8) | (uint32_t)b[3];
  return YES;
}

@implementation KResourceFork

@synthesize fileType = _fileType;
@synthesize fileCreator = _fileCreator;

+ (instancetype)forkWithData:(NSData *)data
{
  KResourceFork *fork = [[[self alloc] init] autorelease];

  if (![fork parseWrapper: data])
    return nil;
  if (![fork parseResourceMap])
    return nil;
  return fork;
}

+ (instancetype)forkWithContentsOfFile:(NSString *)path
{
  NSData *data = [NSData dataWithContentsOfFile: path];

  return data != nil ? [self forkWithData: data] : nil;
}

- (id)init
{
  if ((self = [super init]) != nil)
    {
      _resources = [[NSMutableDictionary alloc] init];
      _names = [[NSMutableDictionary alloc] init];
    }
  return self;
}

- (void)dealloc
{
  [_fork release];
  [_resources release];
  [_names release];
  [super dealloc];
}

/* Finds the resource fork inside whatever wrapper the unpacker produced. */
- (BOOL)parseWrapper:(NSData *)data
{
  uint32_t magic;

  if (data == nil || ![data length])
    return NO;
  if (!KReadU32(data, 0, &magic))
    return NO;

  // AppleDouble sidecar or AppleSingle: a table of numbered entries, of which
  // entry 2 is the resource fork and entry 9 the Finder info.
  if (magic == 0x00051607 || magic == 0x00051600)
    {
      uint16_t entries;
      NSUInteger i;

      if (!KReadU16(data, 24, &entries))
        return NO;
      for (i = 0; i < entries; i++)
        {
          uint32_t entryId, off, len;
          NSUInteger base = 26 + i * 12;

          if (!KReadU32(data, base, &entryId)
              || !KReadU32(data, base + 4, &off)
              || !KReadU32(data, base + 8, &len))
            return NO;
          if ((NSUInteger)off + len > [data length])
            return NO;
          if (entryId == 2)
            ASSIGN(_fork, [data subdataWithRange: NSMakeRange(off, len)]);
          else if (entryId == 9 && len >= 8)
            {
              KReadU32(data, off, &_fileType);
              KReadU32(data, off + 4, &_fileCreator);
            }
        }
      return _fork != nil;
    }

  // MacBinary: a 128 byte header, then the data fork padded to 128 bytes,
  // then the resource fork. Recognised by the fields that must be zero and a
  // plausible name length, since it carries no magic of its own.
  {
    uint8_t zero, nameLen, zero74, zero82;
    uint32_t dataLen, rsrcLen;

    if (KReadU8(data, 0, &zero) && zero == 0
        && KReadU8(data, 1, &nameLen) && nameLen >= 1 && nameLen <= 63
        && KReadU8(data, 74, &zero74) && zero74 == 0
        && KReadU8(data, 82, &zero82) && zero82 == 0
        && KReadU32(data, 83, &dataLen) && KReadU32(data, 87, &rsrcLen)
        && rsrcLen > 0)
      {
        NSUInteger start = 128 + ((dataLen + 127) / 128) * 128;

        if (start + rsrcLen <= [data length])
          {
            KReadU32(data, 65, &_fileType);
            KReadU32(data, 69, &_fileCreator);
            ASSIGN(_fork, [data subdataWithRange: NSMakeRange(start, rsrcLen)]);
            return YES;
          }
      }
  }

  // Otherwise the bare fork, which starts with its own offsets.
  ASSIGN(_fork, data);
  return YES;
}

- (BOOL)parseResourceMap
{
  uint32_t dataOff, mapOff, dataLen, mapLen;
  uint16_t typeListOff, nameListOff, typeCount;
  NSUInteger i;

  if (!KReadU32(_fork, 0, &dataOff) || !KReadU32(_fork, 4, &mapOff)
      || !KReadU32(_fork, 8, &dataLen) || !KReadU32(_fork, 12, &mapLen))
    return NO;
  if ((NSUInteger)mapOff + mapLen > [_fork length]
      || (NSUInteger)dataOff + dataLen > [_fork length]
      || mapLen < 30)
    return NO;

  // Offsets inside the map are relative to the map, so it is sliced out and
  // read on its own; that way one bounds check covers the whole map.
  {
    NSData *map = [_fork subdataWithRange: NSMakeRange(mapOff, mapLen)];

    if (!KReadU16(map, 24, &typeListOff) || !KReadU16(map, 26, &nameListOff))
      return NO;
    if (!KReadU16(map, typeListOff, &typeCount))
      return NO;
    typeCount += 1;                     /* stored as one less than the count */

    for (i = 0; i < typeCount; i++)
      {
        NSUInteger p = (NSUInteger)typeListOff + 2 + i * 8;
        uint32_t type;
        uint16_t count, refOff;
        NSString *typeName;
        NSMutableDictionary *byId, *namesById;
        NSUInteger j;

        if (!KReadU32(map, p, &type) || !KReadU16(map, p + 4, &count)
            || !KReadU16(map, p + 6, &refOff))
          return NO;
        count += 1;
        typeName = KStringFromOSType(type);
        byId = [NSMutableDictionary dictionaryWithCapacity: count];
        namesById = [NSMutableDictionary dictionary];

        for (j = 0; j < count; j++)
          {
            NSUInteger q = (NSUInteger)typeListOff + refOff + j * 12;
            int16_t resourceId, nameOff;
            uint32_t attrsAndOffset, length;
            NSUInteger dataStart;

            if (!KReadS16(map, q, &resourceId)
                || !KReadS16(map, q + 2, &nameOff)
                || !KReadU32(map, q + 4, &attrsAndOffset))
              return NO;
            dataStart = (NSUInteger)dataOff + (attrsAndOffset & 0x00FFFFFF);
            if (!KReadU32(_fork, dataStart, &length))
              return NO;
            if (dataStart + 4 + length > [_fork length])
              return NO;
            [byId setObject: [_fork subdataWithRange:
                               NSMakeRange(dataStart + 4, length)]
                     forKey: [NSNumber numberWithInteger: resourceId]];
            if (nameOff >= 0)
              {
                NSUInteger np = (NSUInteger)nameListOff + nameOff;
                uint8_t nameLength;

                if (KReadU8(map, np, &nameLength)
                    && np + 1 + nameLength <= [map length])
                  {
                    NSString *name = [[[NSString alloc]
                      initWithData: [map subdataWithRange:
                                      NSMakeRange(np + 1, nameLength)]
                          encoding: NSMacOSRomanStringEncoding] autorelease];

                    if (name != nil)
                      [namesById setObject: name
                                    forKey: [NSNumber numberWithInteger: resourceId]];
                  }
              }
          }
        [_resources setObject: byId forKey: typeName];
        if ([namesById count] > 0)
          [_names setObject: namesById forKey: typeName];
      }
  }
  return [_resources count] > 0;
}

- (NSArray *)resourceTypes
{
  return [[_resources allKeys]
    sortedArrayUsingSelector: @selector(compare:)];
}

- (NSArray *)resourceIdsOfType:(NSString *)type
{
  return [[[_resources objectForKey: type] allKeys]
    sortedArrayUsingSelector: @selector(compare:)];
}

- (NSData *)resourceOfType:(NSString *)type id:(NSInteger)resourceId
{
  return [[_resources objectForKey: type]
    objectForKey: [NSNumber numberWithInteger: resourceId]];
}

- (NSString *)nameOfResourceOfType:(NSString *)type id:(NSInteger)resourceId
{
  return [[_names objectForKey: type]
    objectForKey: [NSNumber numberWithInteger: resourceId]];
}

@end
