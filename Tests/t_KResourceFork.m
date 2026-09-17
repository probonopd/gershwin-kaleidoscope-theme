/* t_KResourceFork.m - the resource fork reader, against forks built here.
 * Headless.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "KResourceFork.h"
#import "KTestFixtures.h"

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSData *hello = [@"hello" dataUsingEncoding: NSASCIIStringEncoding];
  NSData *world = [@"world!" dataUsingEncoding: NSASCIIStringEncoding];
  NSDictionary *contents = @{
    @"Colr": @{ @128: hello, @129: world },
    @"vers": @{ @1: world }
  };
  NSData *bare = KMakeFork(contents);

  /* --- a bare fork --- */
  {
    KResourceFork *fork = [KResourceFork forkWithData: bare];
    NSArray *want = @[@"Colr", @"vers"];

    PASS(fork != nil, "a bare resource fork is read");
    PASS([[fork resourceTypes] isEqual: want], "every resource type is found");
    PASS_EQUAL([fork resourceOfType: @"Colr" id: 128], hello,
               "a resource comes back byte for byte");
    PASS_EQUAL([fork resourceOfType: @"Colr" id: 129], world,
               "so does the second resource of a type");
    PASS([[fork resourceIdsOfType: @"Colr"] count] == 2,
         "both ids of a type are listed");
    PASS([fork resourceOfType: @"Colr" id: 999] == nil,
         "an id the fork does not have reads as nil");
    PASS([fork resourceOfType: @"nope" id: 128] == nil,
         "a type the fork does not have reads as nil");
  }

  /* --- ids are signed: schemes keep everything at negative ids --- */
  {
    NSData *negative = KMakeFork(@{ @"cicn": @{ @-14305: hello, @-8288: world } });
    KResourceFork *fork = [KResourceFork forkWithData: negative];
    NSArray *ids = [fork resourceIdsOfType: @"cicn"];

    PASS(fork != nil, "a fork of negative ids is read");
    PASS_EQUAL([fork resourceOfType: @"cicn" id: -14305], hello,
               "a resource at a negative id is found");
    PASS([[ids objectAtIndex: 0] integerValue] == -14305
         && [[ids lastObject] integerValue] == -8288,
         "negative ids sort as numbers, not as unsigned words");
  }

  /* --- the AppleDouble sidecar the unpacker produces --- */
  {
    NSData *sidecar = KMakeAppleDouble(bare, "Colr", "Acid");
    KResourceFork *fork = [KResourceFork forkWithData: sidecar];

    PASS(fork != nil, "an AppleDouble sidecar is recognised");
    PASS([fork fileType] == 0x436F6C72, "the Finder type is read from it");
    PASS([fork fileCreator] == 0x41636964, "so is the creator");
    PASS_EQUAL([fork resourceOfType: @"Colr" id: 128], hello,
               "the resources inside the sidecar are readable");
    PASS_EQUAL(KStringFromOSType([fork fileType]), @"Colr",
               "a type prints as its four characters");
  }

  /* --- a fork with no wrapper has no Finder type --- */
  {
    KResourceFork *fork = [KResourceFork forkWithData: bare];

    PASS([fork fileType] == 0, "a bare fork reports no Finder type");
  }

  /* --- malformed input is refused, never read past the end --- */
  {
    NSMutableData *truncated = [[bare mutableCopy] autorelease];
    NSMutableData *lying = [[bare mutableCopy] autorelease];
    uint8_t huge[4] = { 0x7F, 0xFF, 0xFF, 0xFF };

    PASS([KResourceFork forkWithData: [NSData data]] == nil,
         "empty data is refused");
    PASS([KResourceFork forkWithData:
           [@"not a fork at all" dataUsingEncoding: NSASCIIStringEncoding]] == nil,
         "data that is not a fork is refused");
    [truncated setLength: 20];
    PASS([KResourceFork forkWithData: truncated] == nil,
         "a fork cut off after its header is refused");
    /* A map offset past the end of the data must not be followed. */
    [lying replaceBytesInRange: NSMakeRange(4, 4) withBytes: huge length: 4];
    PASS([KResourceFork forkWithData: lying] == nil,
         "a map offset pointing past the end is refused");
    PASS_RUNS([KResourceFork forkWithData: lying],
              "a malformed fork is refused without raising");
  }

  /* --- a missing file --- */
  {
    PASS([KResourceFork forkWithContentsOfFile:
           @"/nonexistent/scheme.rsrc"] == nil,
         "a file that is not there reads as nil");
  }

  [arp release];
  return 0;
}
