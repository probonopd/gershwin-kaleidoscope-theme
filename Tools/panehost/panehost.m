/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

/* panehost - shows one preference pane in a window of its own.
 *
 * System Preferences is a single-instance application, so it cannot be used to
 * look at a pane while another copy of it is already running. This loads a
 * .prefPane bundle directly, which is also the quickest way to see a change to
 * a pane without restarting anything. */

#import <AppKit/AppKit.h>
#import <PreferencePanes/PreferencePanes.h>

@interface PaneHost : NSObject
{
  NSString *_path;
}
- (id)initWithPanePath:(NSString *)path;
@end

@implementation PaneHost

- (id)initWithPanePath:(NSString *)path
{
  if ((self = [super init]) != nil)
    _path = [path copy];
  return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
  NSBundle *bundle = [NSBundle bundleWithPath: _path];
  Class paneClass;
  NSPreferencePane *pane;
  NSView *content;
  NSWindow *window;

  if (bundle == nil || ![bundle load])
    {
      NSLog(@"panehost: cannot load %@", _path);
      [NSApp terminate: nil];
      return;
    }
  paneClass = [bundle principalClass];
  if (paneClass == Nil)
    {
      NSLog(@"panehost: %@ has no principal class", _path);
      [NSApp terminate: nil];
      return;
    }
  pane = [[paneClass alloc] initWithBundle: bundle];
  content = [pane loadMainView];
  if (content == nil)
    {
      NSLog(@"panehost: %@ produced no view", _path);
      [NSApp terminate: nil];
      return;
    }

  window = [[NSWindow alloc]
    initWithContentRect: [content frame]
              styleMask: NSTitledWindowMask | NSClosableWindowMask
                         | NSMiniaturizableWindowMask | NSResizableWindowMask
                backing: NSBackingStoreBuffered
                  defer: NO];
  [window setTitle: [[_path lastPathComponent] stringByDeletingPathExtension]];
  [window setContentView: content];
  [pane didSelect];
  [window center];
  [window makeKeyAndOrderFront: nil];
}

@end

int main(int argc, const char **argv)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  PaneHost *host;

  if (argc < 2)
    {
      fprintf(stderr, "usage: panehost <something.prefPane>\n");
      return 1;
    }
  [NSApplication sharedApplication];
  host = [[PaneHost alloc]
    initWithPanePath: [NSString stringWithUTF8String: argv[1]]];
  [NSApp setDelegate: host];
  // Not NSApplicationMain: it takes the pane path on the command line for a
  // file to open, fails, and puts up an empty alert in front of the pane.
  {
    NSMenu *menu = AUTORELEASE([[NSMenu alloc] initWithTitle: @"panehost"]);

    [menu addItemWithTitle: @"Quit"
                    action: @selector(terminate:)
             keyEquivalent: @"q"];
    [NSApp setMainMenu: menu];
  }
  [pool release];
  [NSApp run];
  return 0;
}
