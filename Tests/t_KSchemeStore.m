/* t_KSchemeStore.m - the scheme library: what it accepts as a name, what it
 * refuses, and which defaults domain a selection is written to.
 * Headless, no network.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>
#import "Testing.h"
#import "KSchemeStore.h"
#import "KScheme.h"
#import "KTestFixtures.h"

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  KSchemeStore *store;
  NSFileManager *fm = [NSFileManager defaultManager];

  [NSApplication sharedApplication];
  store = [KSchemeStore sharedStore];

  /* --- the library lives in the user's own directory --- */
  {
    NSString *dir = [store schemeDirectory];

    PASS(store != nil, "there is a shared store");
    PASS(store == [KSchemeStore sharedStore], "and it is shared");
    PASS([dir hasPrefix: NSHomeDirectory()],
         "the library is inside the user's home, so installing a scheme needs"
         " no privileges");
    PASS([[dir lastPathComponent] isEqualToString: @"Schemes"],
         "it is the Schemes directory");
    PASS([fm fileExistsAtPath: dir],
         "asking for it creates it");
  }

  /* --- a name from the defaults is never allowed to be a path --- */
  {
    /* The value comes from the defaults, which any process can write, so a
     * name that walks out of the library has to be refused rather than
     * followed. */
    PASS([store schemeWithFileName: @"../../../etc/passwd"] == nil,
         "a name that climbs out of the library is refused");
    PASS([store schemeWithFileName: @"/etc/passwd"] == nil,
         "an absolute path is refused");
    PASS([store schemeWithFileName: @"sub/dir.rsrc"] == nil,
         "a name with a directory in it is refused");
    PASS([store schemeWithFileName: @""] == nil, "an empty name is refused");
    PASS([store schemeWithFileName: nil] == nil, "a nil name is refused");
    PASS([store schemeWithFileName: @"no such scheme.rsrc"] == nil,
         "a name that is simply not there reads as nil");
  }

  /* --- and neither is a name to remove --- */
  {
    NSError *error = nil;

    PASS(![store removeSchemeWithFileName: @"../Schemes" error: &error]
         && error != nil,
         "removing by a path is refused, with a reason");
    error = nil;
    PASS(![store removeSchemeWithFileName: @"/etc/passwd" error: &error],
         "removing an absolute path is refused");
    error = nil;
    PASS(![store removeSchemeWithFileName: @"" error: &error],
         "removing an empty name is refused");
  }

  /* --- archives that are not archives --- */
  {
    NSError *error = nil;
    NSString *notAnArchive = [NSTemporaryDirectory()
      stringByAppendingPathComponent:
        [NSString stringWithFormat: @"k-junk-%d.sit", (int)getpid()]];

    PASS([store installSchemesFromArchive: @"/nonexistent/x.sit"
                                    error: &error] == nil
         && error != nil,
         "an archive that is not there fails with a reason");
    [@"this is not a StuffIt archive" writeToFile: notAnArchive
                                       atomically: YES
                                         encoding: NSUTF8StringEncoding
                                            error: NULL];
    error = nil;
    PASS([store installSchemesFromArchive: notAnArchive error: &error] == nil
         && error != nil,
         "a file that is not an archive fails with a reason");
    PASS_RUNS([store installSchemesFromArchive: notAnArchive error: NULL],
              "a caller that does not want the error is not required to take one");
    [fm removeItemAtPath: notAnArchive error: NULL];
  }

  /* --- archives that hold an installer instead of a scheme --- */
  {
    NSData *code = KMakeFork(@{ @"CODE": @{ @0: [@"installer"
      dataUsingEncoding: NSASCIIStringEncoding] } });
    NSString *archive = [NSTemporaryDirectory()
      stringByAppendingPathComponent:
        [NSString stringWithFormat: @"k-installer-%d.bin", (int)getpid()]];
    NSArray *before = [store installedSchemeFileNames];
    NSError *error = nil;

    [KMakeMacBinary(code, "Scheme Installer", "APPL", "VIS3")
      writeToFile: archive atomically: YES];
    PASS([store installSchemesFromArchive: archive error: &error] == nil
         && [error code] == 7
         && [[error localizedDescription] rangeOfString: @"Installer VISE"]
              .location != NSNotFound,
         "an Installer VISE package is named as such, not reported as empty");
    PASS_EQUAL([store installedSchemeFileNames], before,
               "and nothing is added to the library");

    [KMakeMacBinary(code, "Scheme Installer", "APPL", "SIT!")
      writeToFile: archive atomically: YES];
    error = nil;
    PASS([store installSchemesFromArchive: archive error: &error] == nil
         && [error code] == 7
         && [[error localizedDescription] rangeOfString: @"Installer VISE"]
              .location == NSNotFound,
         "any other installer application is reported as an installer");

    [KMakeMacBinary(code, "Read Me", "TEXT", "ttxt")
      writeToFile: archive atomically: YES];
    error = nil;
    PASS([store installSchemesFromArchive: archive error: &error] == nil
         && [error code] == 5,
         "an archive with neither a scheme nor an installer holds no scheme");
    [fm removeItemAtPath: archive error: NULL];
  }

  /* --- a set downloaded from one entry uses that entry's scheme --- */
  {
    NSArray *planets = @[@"Planets - Mars.rsrc", @"Planets - Venus.rsrc",
                         @"Planets - Saturn.rsrc"];
    NSArray *moons = @[@" BeMoon.rsrc", @" Moon.rsrc"];

    PASS_EQUAL([store fileNameForSchemeTitled: @"Venus"
                               amongFileNames: planets],
               @"Planets - Venus.rsrc",
               "the entry clicked picks its scheme out of the set, not the"
               " first one unpacked");
    PASS_EQUAL([store fileNameForSchemeTitled: @"saturn"
                               amongFileNames: planets],
               @"Planets - Saturn.rsrc", "case does not matter");
    PASS_EQUAL([store fileNameForSchemeTitled: @"Moon"
                               amongFileNames: moons],
               @" Moon.rsrc",
               "a title matches whole words, so Moon is not BeMoon");
    PASS_EQUAL([store fileNameForSchemeTitled: @"Sleek Grey"
                               amongFileNames: @[@"Sleek Gray 1.0.rsrc"]],
               @"Sleek Gray 1.0.rsrc",
               "a lone scheme is the answer whatever its file is called");
    PASS([store fileNameForSchemeTitled: @"Pluto"
                         amongFileNames: planets] == nil,
         "a title that names none of the set gives nil rather than a guess");
    PASS([store fileNameForSchemeTitled: @"Planets"
                         amongFileNames: planets] == nil,
         "and so does one that names all of them");
    PASS([store fileNameForSchemeTitled: @"Mars" amongFileNames: @[]] == nil,
         "an empty set has no answer");
  }

  /* --- the installed library reads back consistently --- */
  {
    NSArray *names = [store installedSchemeFileNames];
    NSArray *schemes = [store installedSchemes];
    NSEnumerator *e = [names objectEnumerator];
    NSString *name;
    BOOL everyNameIsBare = YES;

    while ((name = [e nextObject]) != nil)
      if (![[name lastPathComponent] isEqualToString: name])
        everyNameIsBare = NO;
    PASS(names != nil, "the library lists its file names");
    PASS(everyNameIsBare, "every one is a bare file name, not a path");
    PASS([schemes count] <= [names count],
         "a name that will not load is left out of the loaded list");
  }

  /* --- a selection goes to the global domain, not this application's own --- *
   *
   * This is the bug the fix is for: -setObject:forKey: writes the running
   * application's domain, which is searched first, so the scheme would change
   * in whichever application hosted the preference pane and nowhere else. The
   * real value is saved and put back, so running the tests does not change
   * which scheme the desktop is using.
   */
  {
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    NSString *before = [store selectedSchemeFileName];
    NSString *sentinel = @"t-KSchemeStore-sentinel.rsrc";
    NSDictionary *global;
    NSString *inGlobal;
    id inApplication;

    [store selectSchemeWithFileName: sentinel];
    global = [defs persistentDomainForName: NSGlobalDomain];
    inGlobal = [global objectForKey: KSelectedSchemeDefault];
    /* -objectForKey: would find it wherever it is; the application domain is
     * checked on its own to prove nothing was left there to shadow it. */
    inApplication = [[defs persistentDomainForName:
      [[NSProcessInfo processInfo] processName]]
      objectForKey: KSelectedSchemeDefault];

    PASS_EQUAL(inGlobal, sentinel,
               "a selection is written to the global domain");
    PASS(inApplication == nil,
         "and nothing is left in this application's own domain to shadow it");
    PASS_EQUAL([store selectedSchemeFileName], sentinel,
               "the store reads back what it wrote");
    PASS([store selectedScheme] == nil,
         "a selected scheme that is not installed loads as nil");

    [store selectSchemeWithFileName: nil];
    PASS([store selectedSchemeFileName] == nil,
         "selecting nothing clears the setting");

    /* Put the user's own selection back exactly as it was. */
    if (before != nil)
      [store selectSchemeWithFileName: before];
    PASS_EQUAL([store selectedSchemeFileName], before,
               "the previous selection is restored");
  }

  /* --- the names other code keys on --- */
  {
    PASS_EQUAL(KSelectedSchemeDefault, @"KaleidoscopeScheme",
               "the default key is the one the theme watches");
    PASS([KSchemeLibraryDidChangeNotification length] > 0,
         "the library change notification has a name");
  }

  [arp release];
  return 0;
}
