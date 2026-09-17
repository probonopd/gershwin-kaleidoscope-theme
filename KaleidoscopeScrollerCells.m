/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "KaleidoscopeScrollerCells.h"
#import "Kaleidoscope.h"

@interface Kaleidoscope (Parts)
- (void)drawPart:(KSchemePart)part
          inRect:(NSRect)rect
         stretch:(BOOL)stretch
      horizontal:(BOOL)horizontal
          sunken:(BOOL)sunken;
@end

/* The scroll bar belongs to whichever theme handed out these cells, so a cell
 * that outlives its theme draws nothing rather than drawing with another
 * theme's scheme. */
static Kaleidoscope *KCurrentTheme(void)
{
  GSTheme *theme = [GSTheme theme];

  return [theme isKindOfClass: [Kaleidoscope class]]
    ? (Kaleidoscope *)theme : nil;
}

@implementation KaleidoscopeScrollerCell

@synthesize part = _part;
@synthesize pressedPart = _pressedPart;
@synthesize disabledPart = _disabledPart;
@synthesize horizontal = _horizontal;
@synthesize stretch = _stretch;

- (void)drawWithFrame:(NSRect)frame inView:(NSView *)view
{
  BOOL enabled = ![view respondsToSelector: @selector(isEnabled)]
    || [(NSControl *)view isEnabled];
  KSchemePart which;

  if (!enabled)
    which = _disabledPart;
  else if ([self isHighlighted])
    which = _pressedPart;
  else
    which = _part;
  [KCurrentTheme() drawPart: which
                     inRect: frame
                    stretch: _stretch
                 horizontal: _horizontal
                     sunken: [self isHighlighted]];
}

@end
