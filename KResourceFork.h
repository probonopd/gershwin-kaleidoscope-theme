/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

/* Reader for a classic Macintosh resource fork, which is where a Kaleidoscope
 * scheme keeps everything it draws.
 *
 * A scheme arrives as a file with no data fork at all, so what we are handed
 * is whatever the unpacker made of the fork: an AppleDouble sidecar, a
 * MacBinary wrapper, or the bare fork. All three are recognised from their
 * contents, because the file name tells us nothing reliable. */

@interface KResourceFork : NSObject
{
  NSData *_fork;
  NSMutableDictionary *_resources;   /* type -> (id number -> NSData) */
  NSMutableDictionary *_names;       /* type -> (id number -> NSString) */
  OSType _fileType;
  OSType _fileCreator;
}

/* Returns nil when the data holds no readable resource map. */
+ (instancetype)forkWithData:(NSData *)data;
+ (instancetype)forkWithContentsOfFile:(NSString *)path;

/* The four-character type and creator from the Finder info, when the wrapper
 * carried any; 0 otherwise. A Kaleidoscope scheme is type 'Colr'. */
@property (nonatomic, readonly) OSType fileType;
@property (nonatomic, readonly) OSType fileCreator;

/* Four-character resource types present, as NSStrings. */
- (NSArray *)resourceTypes;
/* The ids of one type, as NSNumbers, in ascending order. */
- (NSArray *)resourceIdsOfType:(NSString *)type;
- (NSData *)resourceOfType:(NSString *)type id:(NSInteger)resourceId;
/* The resource's name from the name list, or nil when it has none. */
- (NSString *)nameOfResourceOfType:(NSString *)type id:(NSInteger)resourceId;

@end

/* 'Colr' -> @"Colr", for logging and for the resource type strings. */
NSString *KStringFromOSType(OSType type);
