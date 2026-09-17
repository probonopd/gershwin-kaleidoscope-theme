/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>
#import "KScheme.h"

/* NSScroller draws every piece of itself through a cell it asks the theme for:
 * the two arrows, the thumb and the track. One class covers all four, because
 * they differ only in which scheme part they stand for and whether the middle
 * of that part may be stretched - an arrow must not be, a track must.
 *
 * Each cell carries the part for all three states, since a scheme ships
 * separate artwork for normal, pressed and disabled. */
@interface KaleidoscopeScrollerCell : NSButtonCell
{
  KSchemePart _part;
  KSchemePart _pressedPart;
  KSchemePart _disabledPart;
  BOOL _horizontal;
  BOOL _stretch;
}

@property (nonatomic, assign) KSchemePart part;
@property (nonatomic, assign) KSchemePart pressedPart;
@property (nonatomic, assign) KSchemePart disabledPart;
@property (nonatomic, assign) BOOL horizontal;
@property (nonatomic, assign) BOOL stretch;

@end
