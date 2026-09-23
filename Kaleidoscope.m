/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

/* The theme proper: every GSTheme hook that a Kaleidoscope scheme has art for
 * is answered with that art, and the rest is drawn in colours taken from the
 * scheme so that the whole interface still hangs together.
 *
 * Which parts a scheme ships varies enormously - the ones checked here are the
 * parts every scheme tested carries. A part a scheme does not have is drawn
 * from the derived colours instead; that is a documented derivation, not a
 * guess at missing artwork. */

#import "Kaleidoscope.h"
#import "KScheme.h"
#import "KSchemeStore.h"
#import "KaleidoscopeScrollerCells.h"
#import "AppearanceMetrics.h"

@interface Kaleidoscope (Private)
- (void)loadSelectedScheme;
- (void)deriveColors;
- (void)registerSchemeImages;
- (void)defaultsDidChange:(NSNotification *)note;
- (void)drawBevelInRect:(NSRect)rect flipped:(BOOL)flipped sunken:(BOOL)sunken;
@end

/* Draws image to fill rect: the middle is stretched and the two ends are kept
 * at their own size, which is how Kaleidoscope used these parts. inset is how
 * many pixels at each end are not to be stretched. */
static void KDrawStretched(NSImage *image, NSRect rect, BOOL vertical,
                           CGFloat inset)
{
  NSSize size = [image size];
  CGFloat length = vertical ? NSHeight(rect) : NSWidth(rect);
  CGFloat natural = vertical ? size.height : size.width;

  if (image == nil || size.width < 1 || size.height < 1)
    return;
  if (length <= natural || inset <= 0 || natural <= 2 * inset)
    {
      [image drawInRect: rect
               fromRect: NSZeroRect
              operation: NSCompositeSourceOver
               fraction: 1.0];
      return;
    }
  if (vertical)
    {
      NSRect top = NSMakeRect(NSMinX(rect), NSMaxY(rect) - inset,
                              NSWidth(rect), inset);
      NSRect bottom = NSMakeRect(NSMinX(rect), NSMinY(rect),
                                 NSWidth(rect), inset);
      NSRect middle = NSMakeRect(NSMinX(rect), NSMinY(rect) + inset,
                                 NSWidth(rect), length - 2 * inset);

      [image drawInRect: middle
              fromRect: NSMakeRect(0, inset, size.width, size.height - 2 * inset)
             operation: NSCompositeSourceOver fraction: 1.0];
      [image drawInRect: bottom
              fromRect: NSMakeRect(0, 0, size.width, inset)
             operation: NSCompositeSourceOver fraction: 1.0];
      [image drawInRect: top
              fromRect: NSMakeRect(0, size.height - inset, size.width, inset)
             operation: NSCompositeSourceOver fraction: 1.0];
    }
  else
    {
      NSRect left = NSMakeRect(NSMinX(rect), NSMinY(rect), inset, NSHeight(rect));
      NSRect right = NSMakeRect(NSMaxX(rect) - inset, NSMinY(rect), inset,
                                NSHeight(rect));
      NSRect middle = NSMakeRect(NSMinX(rect) + inset, NSMinY(rect),
                                 length - 2 * inset, NSHeight(rect));

      [image drawInRect: middle
              fromRect: NSMakeRect(inset, 0, size.width - 2 * inset, size.height)
             operation: NSCompositeSourceOver fraction: 1.0];
      [image drawInRect: left
              fromRect: NSMakeRect(0, 0, inset, size.height)
             operation: NSCompositeSourceOver fraction: 1.0];
      [image drawInRect: right
              fromRect: NSMakeRect(size.width - inset, 0, inset, size.height)
             operation: NSCompositeSourceOver fraction: 1.0];
    }
}

static NSBitmapImageRep *KBitmap(NSImage *image)
{
  NSBitmapImageRep *rep;

  if (image == nil || [[image representations] count] == 0)
    return nil;
  rep = (NSBitmapImageRep *)[[image representations] objectAtIndex: 0];
  return [rep isKindOfClass: [NSBitmapImageRep class]] ? rep : nil;
}

/* The colour that covers most of a part. Taking the body colour this way
 * rather than from a fixed pixel is what keeps it off the bevels: the middle
 * of a scroll bar track is a shadow line in plenty of schemes. */
static NSColor *KDominantColor(NSImage *image)
{
  NSBitmapImageRep *rep = KBitmap(image);
  NSMutableDictionary *counts;
  NSUInteger x, y, best = 0;
  NSColor *winner = nil;
  NSEnumerator *keys;
  NSString *key;

  if (rep == nil)
    return nil;
  counts = [NSMutableDictionary dictionary];
  for (y = 0; y < (NSUInteger)[rep pixelsHigh]; y++)
    for (x = 0; x < (NSUInteger)[rep pixelsWide]; x++)
      {
        NSColor *c = [[rep colorAtX: x y: y]
          colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
        NSString *k;

        if (c == nil || [c alphaComponent] < 0.5)
          continue;
        k = [NSString stringWithFormat: @"%.3f %.3f %.3f",
              [c redComponent], [c greenComponent], [c blueComponent]];
        [counts setObject: @[[NSNumber numberWithUnsignedInteger:
                               [[[counts objectForKey: k] objectAtIndex: 0]
                                 unsignedIntegerValue] + 1], c]
                   forKey: k];
      }
  keys = [counts keyEnumerator];
  while ((key = [keys nextObject]) != nil)
    {
      NSArray *entry = [counts objectForKey: key];
      NSUInteger n = [[entry objectAtIndex: 0] unsignedIntegerValue];

      if (n > best)
        {
          best = n;
          winner = [entry objectAtIndex: 1];
        }
    }
  return winner;
}

/* The lightest and darkest colours in a part, which is where a scheme's
 * highlight and shadow for that surface live. */
static void KExtremes(NSImage *image, NSColor **lightest, NSColor **darkest)
{
  NSBitmapImageRep *rep = KBitmap(image);
  CGFloat best = -1.0, worst = 2.0;
  NSUInteger x, y;

  *lightest = nil;
  *darkest = nil;
  if (rep == nil)
    return;
  for (y = 0; y < (NSUInteger)[rep pixelsHigh]; y++)
    for (x = 0; x < (NSUInteger)[rep pixelsWide]; x++)
      {
        NSColor *c = [[rep colorAtX: x y: y]
          colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
        CGFloat level;

        if (c == nil || [c alphaComponent] < 0.5)
          continue;
        level = ([c redComponent] + [c greenComponent] + [c blueComponent]) / 3.0;
        if (level > best)
          {
            best = level;
            *lightest = c;
          }
        if (level < worst)
          {
            worst = level;
            *darkest = c;
          }
      }
}

@implementation Kaleidoscope

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver: self];
  [_scheme release];
  [_loadedFileName release];
  [_faceColor release];
  [_windowColor release];
  [_textColor release];
  [_lightColor release];
  [_shadowColor release];
  [super dealloc];
}

- (KScheme *)scheme
{
  return _scheme;
}

- (void)activate
{
  [self loadSelectedScheme];
  [super activate];
  [self registerSchemeImages];
  // GSTheme itself only watches the GSTheme default. The scheme is a default
  // of our own, so the theme has to watch for that changing to make a scheme
  // switch take effect in an application that is already running.
  [[NSNotificationCenter defaultCenter] removeObserver: self
    name: NSUserDefaultsDidChangeNotification object: nil];
  [[NSNotificationCenter defaultCenter]
    addObserver: self
       selector: @selector(defaultsDidChange:)
           name: NSUserDefaultsDidChangeNotification
         object: nil];
}

- (void)deactivate
{
  [[NSNotificationCenter defaultCenter] removeObserver: self
    name: NSUserDefaultsDidChangeNotification object: nil];
  [super deactivate];
}

- (void)defaultsDidChange:(NSNotification *)note
{
  NSString *chosen = [[KSchemeStore sharedStore] selectedSchemeFileName];

  if (chosen == _loadedFileName || [chosen isEqualToString: _loadedFileName])
    return;
  // Re-activating is what reloads the colour list and the images and tells
  // every window to redraw, which is exactly what a new scheme needs.
  [self activate];
}

- (void)loadSelectedScheme
{
  KSchemeStore *store = [KSchemeStore sharedStore];
  NSString *chosen = [store selectedSchemeFileName];
  KScheme *scheme = [store selectedScheme];

  ASSIGN(_loadedFileName, chosen);
  ASSIGN(_scheme, scheme);
  if (scheme == nil && [chosen length] > 0)
    NSLog(@"Kaleidoscope: the scheme '%@' is missing or unreadable;"
          @" drawing in plain grays until another one is chosen", chosen);
  [self deriveColors];
}

/* The face, highlight and shadow greys are read off the scroll bar track and
 * thumb, which every scheme ships and which is where its body colour lives.
 * With no scheme loaded they fall back to the Platinum greys, so the interface
 * stays usable and obviously unthemed. */
- (void)deriveColors
{
  /* The body colour is not guessed at any more: a scheme states it in the
   * window colour table it ships, and that is what Kaleidoscope itself drew
   * windows with. Sampling the artwork instead gave the frame colour, which is
   * why a green scheme came out saturated green rather than pale mint.
   *
   * The bevel highlight and shadow do still come from the artwork, because
   * that is where they live: they are the lit and shaded edges the author drew
   * onto the push button, and no table names them. */
  NSImage *buttonArt = [_scheme imageForPart: KPartButton];
  NSColor *body = [_scheme bodyColor];
  NSColor *text = [_scheme textColor];
  NSColor *light = nil, *shadow = nil;

  KExtremes(buttonArt, &light, &shadow);

  if (body == nil)
    {
      // No table to go on. The push button is the largest flat control a
      // scheme draws, so its dominant colour is the closest thing to a body
      // colour that the artwork can offer.
      body = KDominantColor(buttonArt);
      if (body != nil)
        NSLog(@"Kaleidoscope: '%@' ships no window colour table;"
              @" taking the control colour from its button artwork",
              [_scheme name]);
    }
  ASSIGN(_windowColor, body != nil ? body
    : [NSColor colorWithCalibratedWhite: 0xDD / 255.0 alpha: 1.0]);
  // Controls sit on the window, so they share its colour unless the scheme
  // says otherwise; only the bevels differ.
  ASSIGN(_faceColor, _windowColor);
  ASSIGN(_textColor, text != nil ? text : [NSColor blackColor]);
  ASSIGN(_lightColor, light != nil ? light
    : [NSColor colorWithCalibratedWhite: 1.0 alpha: 1.0]);
  ASSIGN(_shadowColor, shadow != nil ? shadow
    : [NSColor colorWithCalibratedWhite: 0x88 / 255.0 alpha: 1.0]);
}

/* Check boxes and radio buttons are drawn by AppKit from named images, so the
 * scheme's art is registered under the names AppKit looks up. */
- (void)registerSchemeImages
{
  /* AppKit draws check boxes, radio buttons and the small arrows from named
   * images, so the scheme's own art is registered under the names it looks up.
   * These all live in the small icon families, not in 'cicn'. */
  NSDictionary *map = @{
    @"common_SwitchOff": [NSNumber numberWithInteger: KPartCheckBox],
    @"common_SwitchOn": [NSNumber numberWithInteger: KPartCheckBoxOn],
    @"common_RadioOff": [NSNumber numberWithInteger: KPartRadio],
    @"common_RadioOn": [NSNumber numberWithInteger: KPartRadioOn],
    @"common_3DArrowUp": [NSNumber numberWithInteger: KPartArrowUp],
    @"common_3DArrowDown": [NSNumber numberWithInteger: KPartArrowDown],
    @"common_3DArrowLeft": [NSNumber numberWithInteger: KPartArrowLeft],
    @"common_3DArrowRight": [NSNumber numberWithInteger: KPartArrowRight]
  };
  NSEnumerator *names = [map keyEnumerator];
  NSString *name;

  if (_scheme == nil)
    return;
  while ((name = [names nextObject]) != nil)
    {
      NSImage *art = [_scheme imageForPart:
        (KSchemePart)[[map objectForKey: name] integerValue]];
      NSImage *old = [NSImage imageNamed: name];
      NSString *registered;
      NSImage *copy;

      if (art == nil)
        continue;
      // Several names resolve to one registered image, so the name the image
      // is really under is the one to re-register; copied, because
      // unregistering the old image is what releases the string.
      registered = AUTORELEASE([([old name] ? [old name] : name) copy]);
      copy = AUTORELEASE([art copy]);
      [old setName: nil];
      [copy setName: registered];
    }
}

- (NSColorList *)colors
{
  NSColorList *base = [super colors];
  NSColorList *list = AUTORELEASE([[NSColorList alloc] initWithName: @"System"]);
  NSEnumerator *keys = [[base allKeys] objectEnumerator];
  NSString *key;
  NSDictionary *overrides;

  while ((key = [keys nextObject]) != nil)
    [list setColor: [base colorWithKey: key] forKey: key];

  overrides = @{
    @"windowBackgroundColor": _windowColor,
    @"controlBackgroundColor": _faceColor,
    @"controlColor": _faceColor,
    @"controlHighlightColor": _lightColor,
    @"controlLightHighlightColor": _lightColor,
    @"controlShadowColor": _shadowColor,
    @"scrollBarColor": _faceColor,
    @"knobColor": _faceColor
  };
  keys = [overrides keyEnumerator];
  while ((key = [keys nextObject]) != nil)
    [list setColor: [overrides objectForKey: key] forKey: key];
  return list;
}

#pragma mark - Bevels for the parts a scheme has no art for

- (void)drawBevelInRect:(NSRect)rect flipped:(BOOL)flipped sunken:(BOOL)sunken
{
  NSRect r = NSIntegralRect(rect);
  NSColor *top = sunken ? _shadowColor : _lightColor;
  NSColor *bottom = sunken ? _lightColor : _shadowColor;

  if (NSWidth(r) < 3 || NSHeight(r) < 3)
    return;
  [_faceColor set];
  NSRectFill(r);
  [top set];
  NSRectFill(NSMakeRect(NSMinX(r), flipped ? NSMinY(r) : NSMaxY(r) - 1,
                        NSWidth(r), 1));
  NSRectFill(NSMakeRect(NSMinX(r), NSMinY(r), 1, NSHeight(r)));
  [bottom set];
  NSRectFill(NSMakeRect(NSMinX(r), flipped ? NSMaxY(r) - 1 : NSMinY(r),
                        NSWidth(r), 1));
  NSRectFill(NSMakeRect(NSMaxX(r) - 1, NSMinY(r), 1, NSHeight(r)));
}

- (void)drawButton:(NSRect)frame
                in:(NSCell *)cell
              view:(NSView *)view
             style:(int)style
             state:(GSThemeControlState)state
{
  BOOL pressed = (state == GSThemeHighlightedState
                  || state == GSThemeHighlightedFirstResponderState
                  || state == GSThemeSelectedState
                  || state == GSThemeSelectedFirstResponderState);
  BOOL enabled = (state != GSThemeDisabledState);
  KSchemePart part = pressed ? KPartButtonPressed
    : (enabled ? KPartButton : KPartButtonDisabled);
  NSImage *art = [_scheme imageForPart: part];

  if (art == nil)
    {
      [self drawBevelInRect: frame flipped: [view isFlipped] sunken: pressed];
      return;
    }
  // A scheme draws one small button and expects the middle to be stretched to
  // whatever width the button needs.
  KDrawStretched(art, frame, NO, 4.0);

  /* Platinum rings the default button rather than restyling it. */
  if (enabled && [[view window] defaultButtonCell] == (NSButtonCell *)cell)
    {
      NSImage *ring = [_scheme imageForPart: KPartDefaultRing];

      if (ring != nil)
        KDrawStretched(ring, frame, NO, 4.0);
    }
}

- (void)drawWindowBackground:(NSRect)frame view:(NSView *)view
{
  [_windowColor set];
  NSRectFill(frame);
}

- (void)drawBorderType:(NSBorderType)aType
                 frame:(NSRect)frame
                  view:(NSView *)view
{
  if (aType == NSNoBorder)
    return;
  [self drawBevelInRect: frame flipped: [view isFlipped] sunken: YES];
}

- (NSSize)sizeForBorderType:(NSBorderType)aType
{
  return aType == NSNoBorder ? NSZeroSize : NSMakeSize(2, 2);
}

#pragma mark - Scroll bars

- (float)defaultScrollerWidth
{
  NSImage *arrow = [_scheme imageForPart: KPartArrowUp];

  // The scroll bar is as wide as the scheme's own arrow art, which is what
  // sets the scale of the whole scroll bar in a Kaleidoscope scheme.
  if (arrow != nil && [arrow size].width >= 8)
    return [arrow size].width;
  return 16.0;
}

- (BOOL)scrollerArrowsSameEndForScroller:(NSScroller *)scroller
{
  return NO;
}

- (NSButtonCell *)cellForScrollerArrow:(NSScrollerArrow)arrow
                            horizontal:(BOOL)horizontal
{
  KaleidoscopeScrollerCell *cell
    = [[KaleidoscopeScrollerCell alloc] init];
  NSString *name;

  if (horizontal)
    {
      BOOL back = (arrow == NSScrollerDecrementArrow);

      [cell setPart: back ? KPartArrowLeft : KPartArrowRight];
      [cell setPressedPart: back ? KPartArrowLeftPressed
                                 : KPartArrowRightPressed];
      [cell setDisabledPart: back ? KPartArrowLeftDisabled
                                  : KPartArrowRightDisabled];
      name = back ? GSScrollerLeftArrow : GSScrollerRightArrow;
    }
  else
    {
      BOOL back = (arrow == NSScrollerDecrementArrow);

      [cell setPart: back ? KPartArrowUp : KPartArrowDown];
      [cell setPressedPart: back ? KPartArrowUpPressed : KPartArrowDownPressed];
      [cell setDisabledPart: back ? KPartArrowUpDisabled
                                  : KPartArrowDownDisabled];
      name = back ? GSScrollerUpArrow : GSScrollerDownArrow;
    }
  [cell setHorizontal: horizontal];
  [cell setStretch: NO];
  [cell setImagePosition: NSImageOnly];
  [self setName: name forElement: cell temporary: YES];
  RELEASE(cell);
  return cell;
}

- (NSCell *)cellForScrollerKnob:(BOOL)horizontal
{
  KaleidoscopeScrollerCell *cell
    = [[KaleidoscopeScrollerCell alloc] init];

  [cell setPart: horizontal ? KPartScrollThumbH : KPartScrollThumbV];
  [cell setPressedPart: horizontal ? KPartScrollThumbHPressed
                                   : KPartScrollThumbVPressed];
  [cell setDisabledPart: horizontal ? KPartScrollThumbHGhost
                                    : KPartScrollThumbVGhost];
  [cell setHorizontal: horizontal];
  [cell setStretch: YES];
  [self setName: (horizontal ? GSScrollerHorizontalKnob : GSScrollerVerticalKnob)
     forElement: cell
      temporary: YES];
  RELEASE(cell);
  return cell;
}

- (NSCell *)cellForScrollerKnobSlot:(BOOL)horizontal
{
  KaleidoscopeScrollerCell *cell
    = [[KaleidoscopeScrollerCell alloc] init];

  [cell setPart: horizontal ? KPartScrollTrackH : KPartScrollTrackV];
  [cell setPressedPart: horizontal ? KPartScrollTrackHPressed
                                   : KPartScrollTrackVPressed];
  [cell setDisabledPart: horizontal ? KPartScrollTrackHDisabled
                                    : KPartScrollTrackVDisabled];
  [cell setHorizontal: horizontal];
  [cell setStretch: YES];
  [cell setBordered: NO];
  [self setName: (horizontal ? GSScrollerHorizontalSlot : GSScrollerVerticalSlot)
     forElement: cell
      temporary: YES];
  RELEASE(cell);
  return cell;
}

/* Called by the scroller cells above. */
- (void)drawPart:(KSchemePart)part
          inRect:(NSRect)rect
         stretch:(BOOL)stretch
      horizontal:(BOOL)horizontal
          sunken:(BOOL)sunken
{
  NSImage *art = [_scheme imageForPart: part];

  if (art == nil)
    {
      [self drawBevelInRect: rect flipped: NO sunken: sunken];
      return;
    }
  if (stretch)
    KDrawStretched(art, rect, !horizontal, 2.0);
  else
    {
      // An arrow is drawn at its own size, centred in the space the scroller
      // gave it; stretching a glyph would distort it.
      NSSize size = [art size];
      NSRect at = NSMakeRect(round(NSMidX(rect) - size.width / 2.0),
                             round(NSMidY(rect) - size.height / 2.0),
                             size.width, size.height);

      [art drawInRect: at
             fromRect: NSZeroRect
            operation: NSCompositeSourceOver
             fraction: 1.0];
    }
}

#pragma mark - Progress indicators

- (void)drawProgressIndicator:(NSProgressIndicator *)progress
                   withBounds:(NSRect)bounds
                     withClip:(NSRect)rect
                      atCount:(int)count
                     forValue:(double)val
{
  NSImage *trough = [_scheme imageForPart: KPartProgressEmpty];
  NSImage *fill = [_scheme imageForPart: KPartProgressFilled];
  BOOL vertical = [progress isVertical];
  CGFloat length = vertical ? NSHeight(bounds) : NSWidth(bounds);
  CGFloat inset;
  NSRect shown;

  // Spinners and schemes without bar art have nothing of the scheme to show.
  if ([progress style] == NSProgressIndicatorSpinningStyle
      || trough == nil || fill == nil)
    {
      [super drawProgressIndicator: progress
                        withBounds: bounds
                          withClip: rect
                           atCount: count
                          forValue: val];
      return;
    }

  // The art is one short bar whose rounded ends must not be stretched.
  inset = floor((vertical ? [trough size].height : [trough size].width) / 3.0);
  KDrawStretched(trough, bounds, vertical, inset);

  shown = bounds;
  if ([progress isIndeterminate])
    {
      // No part in the format is a barber pole, so a quarter-length run of the
      // fill travels along the trough to show that work is going on. It starts
      // at the leading end, so a bar whose owner blocks the animation timer
      // still shows some fill rather than an empty trough.
      CGFloat run = floor(length / 4.0);
      CGFloat offset = fmod(count * run / 8.0, length);

      if (vertical)
        {
          shown.origin.y += offset;
          shown.size.height = run;
        }
      else
        {
          shown.origin.x += offset;
          shown.size.width = run;
        }
    }
  else if (vertical)
    {
      shown.size.height = round(length * val);
      if ([progress isFlipped])
        shown.origin.y = NSMaxY(bounds) - NSHeight(shown);
    }
  else
    shown.size.width = round(length * val);

  // The fill is drawn over the whole bar and clipped, so that a partial fill
  // keeps the art's own leading end instead of a squeezed copy of it.
  shown = NSIntersectionRect(NSIntersectionRect(shown, bounds), rect);
  if (NSIsEmptyRect(shown))
    return;
  [NSGraphicsContext saveGraphicsState];
  NSRectClip(shown);
  KDrawStretched(fill, bounds, vertical, inset);
  [NSGraphicsContext restoreGraphicsState];
}

#pragma mark - Pop-up buttons

- (void)drawPopUpButtonCellInteriorWithFrame:(NSRect)cellFrame
                                    withCell:(NSCell *)cell
                                      inView:(NSView *)controlView
{
  // A scheme draws the whole pop-up button, arrow included, as one piece.
  NSImage *art = [_scheme imageForPart:
    ([cell isHighlighted] ? KPartPopUpButtonPressed : KPartPopUpButton)];

  if (art == nil)
    return;
  KDrawStretched(art, cellFrame, NO, 4.0);
}

#pragma mark - Window decorations

- (NSImage *)imageForWidget:(KWidget)widget pressed:(BOOL)pressed
{
  switch (widget)
    {
      case KWidgetClose:
        return [_scheme imageForPart:
          pressed ? KPartCloseBoxPressed : KPartCloseBox];
      case KWidgetZoom:
        return [_scheme imageForPart:
          pressed ? KPartZoomBoxPressed : KPartZoomBox];
      case KWidgetCollapse:
        // Mac OS called this WindowShade, which is why looking for a
        // "collapse box" in the format found nothing.
        return [_scheme imageForPart:
          pressed ? KPartShadeBoxPressed : KPartShadeBox];
    }
  return nil;
}

- (float)titlebarHeight
{
  NSImage *texture = [_scheme imageForPart: KPartDocumentTitleBar];

  if (texture != nil && [texture size].height >= 12)
    return [texture size].height;
  return METRICS_TITLEBAR_HEIGHT;
}

- (BOOL)drawsTitlebarButtons
{
  return [_scheme imageForPart: KPartCloseBox] != nil;
}

- (NSRect)titlebarButtonRectForButton:(NSInteger)button
                        titlebarWidth:(CGFloat)width
                            styleMask:(NSUInteger)styleMask
{
  NSImage *art = [self imageForWidget: (KWidget)button pressed: NO];
  NSSize size;
  CGFloat y;
  static const NSUInteger required[] = {
    [KWidgetClose] = NSClosableWindowMask,
    [KWidgetCollapse] = NSMiniaturizableWindowMask,
    [KWidgetZoom] = NSResizableWindowMask
  };

  if (button < KWidgetClose || button > KWidgetZoom)
    return NSZeroRect;
  if (!(styleMask & required[button]) || art == nil)
    return NSZeroRect;
  size = [art size];
  y = round(([self titlebarHeight] - size.height) / 2.0);
  if (button == KWidgetClose)
    return NSMakeRect(4, y, size.width, size.height);
  return NSMakeRect(round(width - 4 - size.width), y, size.width, size.height);
}

- (void)drawtitleRect:(NSRect)rect
         forStyleMask:(unsigned int)styleMask
                state:(int)inputState
             andTitle:(NSString *)title
{
  NSImage *texture = [_scheme imageForPart: KPartDocumentTitleBar];
  BOOL active = (inputState == 0);
  KWidget widget;

  if (texture != nil)
    KDrawStretched(texture, rect, NO, 2.0);
  else
    {
      [_faceColor set];
      NSRectFill(rect);
    }

  for (widget = KWidgetClose; widget <= KWidgetZoom; widget++)
    {
      NSRect slot = [self titlebarButtonRectForButton: widget
                                        titlebarWidth: NSWidth(rect)
                                            styleMask: styleMask];
      NSImage *art = [self imageForWidget: widget pressed: NO];

      if (NSIsEmptyRect(slot) || art == nil || !active)
        continue;
      slot.origin.x += NSMinX(rect);
      slot.origin.y += NSMinY(rect);
      [art drawInRect: slot
             fromRect: NSZeroRect
            operation: NSCompositeSourceOver
             fraction: 1.0];
    }

  if ((styleMask & NSTitledWindowMask) && [title length] > 0)
    {
      NSDictionary *attributes = @{
        NSFontAttributeName: [NSFont titleBarFontOfSize: 0],
        NSForegroundColorAttributeName:
          (active ? [NSColor blackColor] : [NSColor darkGrayColor])
      };
      NSSize size = [title sizeWithAttributes: attributes];
      NSPoint at = NSMakePoint(round(NSMidX(rect) - size.width / 2.0),
                               round(NSMidY(rect) - size.height / 2.0));

      // The title sits on the scheme's own body colour so the texture does
      // not run through the letters.
      [_faceColor set];
      NSRectFill(NSMakeRect(at.x - 4, NSMinY(rect) + 2,
                            size.width + 8, NSHeight(rect) - 4));
      [title drawAtPoint: at withAttributes: attributes];
    }
}

- (void)drawCloseButtonInRect:(NSRect)rect
                        state:(GSThemeControlState)state
                       active:(BOOL)active
{
  NSImage *art = [self imageForWidget: KWidgetClose pressed: NO];

  if (art != nil && (active || state != GSThemeNormalState))
    [art drawInRect: rect fromRect: NSZeroRect
          operation: NSCompositeSourceOver fraction: 1.0];
}

- (void)drawMaximizeButtonInRect:(NSRect)rect
                           state:(GSThemeControlState)state
                          active:(BOOL)active
{
  NSImage *art = [self imageForWidget: KWidgetZoom
                              pressed: (state != GSThemeNormalState)];

  if (art != nil && (active || state != GSThemeNormalState))
    [art drawInRect: rect fromRect: NSZeroRect
          operation: NSCompositeSourceOver fraction: 1.0];
}

- (void)drawMinimizeButtonInRect:(NSRect)rect
                           state:(GSThemeControlState)state
                          active:(BOOL)active
{
  NSImage *art = [self imageForWidget: KWidgetCollapse
                              pressed: (state != GSThemeNormalState)];

  if (art != nil && (active || state != GSThemeNormalState))
    [art drawInRect: rect fromRect: NSZeroRect
          operation: NSCompositeSourceOver fraction: 1.0];
}

- (CGFloat)windowFrameBorderWidth
{
  // A scheme's window frame art is not among the parts this theme reads, so
  // there is no border to draw rather than a made up one.
  return 0.0;
}

- (NSColor *)windowFrameBorderColorAtDepth:(NSInteger)depth
                                      edge:(NSInteger)edge
                                    active:(BOOL)active
{
  return _faceColor;
}

@end
