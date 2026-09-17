/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>
#import <PreferencePanes/PreferencePanes.h>

/* The schemes on Mac Themes Garden, shown as the site's own preview pictures.
 * Click one and it is downloaded and used.
 *
 * Using a scheme is a change to one default, which every running application's
 * copy of the theme is watching, so the whole desktop follows without logging
 * out. */
@interface KaleidoscopePrefPane : NSPreferencePane
{
  NSMatrix *_previews;
  NSScrollView *_scroll;
  NSTextField *_status;
  NSButton *_refreshButton;
  NSProgressIndicator *_progress;

  NSArray *_schemes;                   /* KGardenScheme, as listed by the site */
  NSTimer *_pictureTimer;
  NSMutableIndexSet *_tried;           /* pictures already fetched, or failed */
  BOOL _busy;
}
@end
