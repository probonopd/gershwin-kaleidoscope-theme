/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "KSchemeStore.h"
#import "KScheme.h"

NSString * const KSelectedSchemeDefault = @"KaleidoscopeScheme";
NSString * const KSchemeLibraryDidChangeNotification
  = @"KSchemeLibraryDidChangeNotification";

/* The Unarchiver's command line tool, which is what reads StuffIt. Schemes
 * are StuffIt archives from the 1990s and nothing else on the system opens
 * them. */
static NSString * const KUnarPath = @"/System/Library/Tools/unar";

static NSError *KError(NSInteger code, NSString *message)
{
  return [NSError errorWithDomain: @"KSchemeStore"
                             code: code
                         userInfo: @{NSLocalizedDescriptionKey: message}];
}

@implementation KSchemeStore

+ (instancetype)sharedStore
{
  static KSchemeStore *store = nil;

  if (store == nil)
    store = [[self alloc] init];
  return store;
}

- (NSString *)schemeDirectory
{
  NSString *dir = [[NSHomeDirectory()
    stringByAppendingPathComponent: @"Library/Kaleidoscope"]
    stringByAppendingPathComponent: @"Schemes"];
  NSFileManager *fm = [NSFileManager defaultManager];

  if (![fm fileExistsAtPath: dir])
    [fm createDirectoryAtPath: dir
  withIntermediateDirectories: YES
                   attributes: nil
                        error: NULL];
  return dir;
}

- (NSArray *)installedSchemeFileNames
{
  NSString *dir = [self schemeDirectory];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSEnumerator *e = [[fm contentsOfDirectoryAtPath: dir error: NULL]
                      objectEnumerator];
  NSMutableArray *names = [NSMutableArray array];
  NSString *name;

  while ((name = [e nextObject]) != nil)
    {
      if ([name hasPrefix: @"."])
        continue;
      if ([KScheme isSchemeAtPath: [dir stringByAppendingPathComponent: name]])
        [names addObject: name];
    }
  return [names sortedArrayUsingSelector: @selector(caseInsensitiveCompare:)];
}

- (KScheme *)schemeWithFileName:(NSString *)fileName
{
  if ([fileName length] == 0)
    return nil;
  // Only ever a name inside the library, never a path: the value comes from
  // the defaults, which any process can write.
  if (![[fileName lastPathComponent] isEqualToString: fileName])
    return nil;
  return [KScheme schemeWithContentsOfFile:
    [[self schemeDirectory] stringByAppendingPathComponent: fileName]];
}

- (NSArray *)installedSchemes
{
  NSEnumerator *e = [[self installedSchemeFileNames] objectEnumerator];
  NSMutableArray *schemes = [NSMutableArray array];
  NSString *name;

  while ((name = [e nextObject]) != nil)
    {
      KScheme *scheme = [self schemeWithFileName: name];

      if (scheme != nil)
        [schemes addObject: scheme];
    }
  return [schemes sortedArrayUsingComparator: ^(id a, id b) {
    return [[a name] caseInsensitiveCompare: [b name]];
  }];
}

- (NSArray *)installSchemesFromArchive:(NSString *)archivePath
                                 error:(NSError **)error
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *temp = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat: @"kaleidoscope-%d-%lu", (int)getpid(),
      (unsigned long)[[NSDate date] timeIntervalSince1970]]];
  NSTask *task;
  NSMutableArray *installed = [NSMutableArray array];
  NSDirectoryEnumerator *walk;
  NSString *relative;

  if (![fm fileExistsAtPath: KUnarPath])
    {
      if (error != NULL)
        *error = KError(1, @"The Unarchiver's unar tool is not installed,"
                        @" so StuffIt archives cannot be opened.");
      return nil;
    }
  if (![fm createDirectoryAtPath: temp withIntermediateDirectories: YES
                     attributes: nil error: NULL])
    {
      if (error != NULL)
        *error = KError(2, @"Could not create a directory to unpack into.");
      return nil;
    }

  /* -forks visible writes each resource fork out as its own AppleDouble file,
   * which is the only part of a scheme that carries anything. */
  task = [[[NSTask alloc] init] autorelease];
  [task setLaunchPath: KUnarPath];
  [task setArguments: @[@"-force-overwrite", @"-quiet",
                        @"-forks", @"visible",
                        @"-output-directory", temp, archivePath]];
  [task setStandardOutput: [NSFileHandle fileHandleWithNullDevice]];
  [task setStandardError: [NSFileHandle fileHandleWithNullDevice]];
  NS_DURING
    [task launch];
    [task waitUntilExit];
  NS_HANDLER
    [fm removeItemAtPath: temp error: NULL];
    if (error != NULL)
      *error = KError(3, @"Could not run unar to unpack the archive.");
    return nil;
  NS_ENDHANDLER
  if ([task terminationStatus] != 0)
    {
      [fm removeItemAtPath: temp error: NULL];
      if (error != NULL)
        *error = KError(4, @"The archive could not be unpacked.");
      return nil;
    }

  walk = [fm enumeratorAtPath: temp];
  while ((relative = [walk nextObject]) != nil)
    {
      NSString *full = [temp stringByAppendingPathComponent: relative];
      NSString *destination;

      if (![KScheme isSchemeAtPath: full])
        continue;
      destination = [[self schemeDirectory]
        stringByAppendingPathComponent: [relative lastPathComponent]];
      // A scheme of that name is replaced: re-downloading a scheme should
      // refresh it rather than pile up copies.
      if ([fm fileExistsAtPath: destination])
        [fm removeItemAtPath: destination error: NULL];
      if ([fm copyItemAtPath: full toPath: destination error: NULL])
        [installed addObject: [relative lastPathComponent]];
    }
  [fm removeItemAtPath: temp error: NULL];

  if ([installed count] == 0)
    {
      if (error != NULL)
        *error = KError(5, @"The archive holds no Kaleidoscope scheme.");
      return nil;
    }
  [[NSNotificationCenter defaultCenter]
    postNotificationName: KSchemeLibraryDidChangeNotification object: self];
  return installed;
}

- (BOOL)removeSchemeWithFileName:(NSString *)fileName error:(NSError **)error
{
  NSString *path;

  if ([fileName length] == 0
      || ![[fileName lastPathComponent] isEqualToString: fileName])
    {
      if (error != NULL)
        *error = KError(6, @"That is not a scheme in the library.");
      return NO;
    }
  path = [[self schemeDirectory] stringByAppendingPathComponent: fileName];
  if (![[NSFileManager defaultManager] removeItemAtPath: path error: error])
    return NO;
  [[NSNotificationCenter defaultCenter]
    postNotificationName: KSchemeLibraryDidChangeNotification object: self];
  return YES;
}

- (NSString *)selectedSchemeFileName
{
  return [[NSUserDefaults standardUserDefaults]
    stringForKey: KSelectedSchemeDefault];
}

- (void)selectSchemeWithFileName:(NSString *)fileName
{
  NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
  NSMutableDictionary *global = [[[defs persistentDomainForName: NSGlobalDomain]
    mutableCopy] autorelease];

  /* The global domain is written explicitly, not through -setObject:forKey:.
   * That method writes the running application's OWN domain, which is searched
   * before the global one, so the scheme would change in whichever application
   * happened to host the preference pane and in no other: the pane would
   * re-skin itself and the rest of the desktop would carry on unchanged. */
  if (global == nil)
    global = [NSMutableDictionary dictionary];
  if ([fileName length] == 0)
    [global removeObjectForKey: KSelectedSchemeDefault];
  else
    [global setObject: fileName forKey: KSelectedSchemeDefault];
  [defs setPersistentDomain: global forName: NSGlobalDomain];

  /* Anything an earlier version left in the application domain would shadow
   * what every other application reads, so it goes. */
  if ([defs objectForKey: KSelectedSchemeDefault] != nil)
    [defs removeObjectForKey: KSelectedSchemeDefault];

  // Written through so the other applications' defaults watchers fire.
  [defs synchronize];
}

- (KScheme *)selectedScheme
{
  return [self schemeWithFileName: [self selectedSchemeFileName]];
}

@end
