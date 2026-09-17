/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

@class KScheme;

/* The user's scheme library, and the one setting that says which scheme the
 * theme is currently drawing with.
 *
 * Schemes live in the user's own directory, so installing one needs no
 * privileges: downloading a scheme is not an act of system administration. */

/* Written to NSGlobalDomain. Every running application's copy of the theme
 * watches it, which is what makes a scheme change take effect everywhere at
 * once without logging out. */
extern NSString * const KSelectedSchemeDefault;

/* Posted after the library changes (a scheme was installed or removed). */
extern NSString * const KSchemeLibraryDidChangeNotification;

@interface KSchemeStore : NSObject

+ (instancetype)sharedStore;

/* ~/Library/Kaleidoscope/Schemes, created on first use. */
- (NSString *)schemeDirectory;

/* Every scheme in the library, loaded, sorted by name. */
- (NSArray *)installedSchemes;
/* The scheme file names in the library, which is what the default holds. */
- (NSArray *)installedSchemeFileNames;
- (KScheme *)schemeWithFileName:(NSString *)fileName;

/* Unpacks an archive downloaded from Mac Themes Garden and takes every
 * Kaleidoscope scheme out of it into the library. A single archive often
 * holds several schemes, alongside read-me files, icons and sometimes fonts,
 * all of which are left behind.
 *
 * Returns the file names installed, or nil with error set. */
- (NSArray *)installSchemesFromArchive:(NSString *)archivePath
                                 error:(NSError **)error;

- (BOOL)removeSchemeWithFileName:(NSString *)fileName error:(NSError **)error;

/* The chosen scheme's file name, or nil when none is chosen yet. */
- (NSString *)selectedSchemeFileName;
/* Choosing a scheme is a one-line change to the defaults; the theme picks it
 * up from there. */
- (void)selectSchemeWithFileName:(NSString *)fileName;
- (KScheme *)selectedScheme;

@end
