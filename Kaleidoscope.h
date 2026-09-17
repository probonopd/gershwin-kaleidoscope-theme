/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSTheme.h>

@class KScheme;

/* Title bar widgets, in the order the window manager numbers them. */
typedef NS_ENUM(NSInteger, KWidget) {
    KWidgetClose = 0,
    KWidgetCollapse,
    KWidgetZoom
};

/* A GNUstep theme that draws itself out of a Kaleidoscope colour scheme.
 *
 * The theme holds no artwork of its own. It reads the scheme named by the
 * KaleidoscopeScheme default out of the user's library and draws the parts
 * that scheme ships; the scheme can be changed while applications are
 * running, and every one of them follows. */
@interface Kaleidoscope : GSTheme
{
  KScheme *_scheme;
  NSString *_loadedFileName;
  NSColor *_faceColor;
  NSColor *_windowColor;
  NSColor *_textColor;
  NSColor *_lightColor;
  NSColor *_shadowColor;
}

/* The scheme currently being drawn with, or nil when the chosen scheme is
 * missing or unreadable - in which case the theme draws in plain grays and
 * says so once, rather than pretending a scheme is loaded. */
- (KScheme *)scheme;

/* Art for a title bar widget at the size the window manager asked for. */
- (NSImage *)imageForWidget:(KWidget)widget pressed:(BOOL)pressed;

/* The window manager asks every theme for these two before it draws a window
 * frame, so they are answered even though the parts a Kaleidoscope scheme is
 * read for here carry no frame art: the answer is that there is no border. */
- (CGFloat)windowFrameBorderWidth;
- (NSColor *)windowFrameBorderColorAtDepth:(NSInteger)depth
                                      edge:(NSInteger)edge
                                    active:(BOOL)active;

@end
