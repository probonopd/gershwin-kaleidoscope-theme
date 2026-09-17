/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "KaleidoscopePrefPane.h"
#import "KScheme.h"
#import "KSchemeStore.h"
#import "KGarden.h"
#import "AppearanceMetrics.h"

/* The pane area a preference pane is given. */
#define PANE_WIDTH  640.0
#define PANE_HEIGHT 440.0

/* The site's preview pictures are 780x508; shown three to a row at that
 * shape, with room under each for the scheme's name. */
#define PREVIEW_WIDTH   192.0
#define PREVIEW_HEIGHT  125.0
#define CELL_HEIGHT     (PREVIEW_HEIGHT + 20.0)
#define COLUMNS         3

@interface KaleidoscopePrefPane (Private)
- (NSView *)buildMainView;
- (void)refresh:(id)sender;
- (void)pickScheme:(id)sender;
- (void)finishDownload;
- (void)setStatus:(NSString *)text;
- (void)loadVisiblePictures;
- (void)loadNextPicture:(NSTimer *)timer;
- (NSRange)visibleSchemeRange;
- (void)visibleAreaChanged:(NSNotification *)note;
- (void)rebuildMatrixForCount:(NSUInteger)count;
@end

@implementation KaleidoscopePrefPane

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver: self];
  [_pictureTimer invalidate];
  [_schemes release];
  [_tried release];
  [super dealloc];
}

- (id)initWithBundle:(NSBundle *)bundle
{
  if ((self = [super initWithBundle: bundle]) != nil)
    {
      [self setMainView: [self buildMainView]];
      /* -loadMainView returns a view that is already set without going near a
       * nib, and only calls -mainViewDidLoad on the nib path - so a pane built
       * in code has to say so itself, or its opening status line never
       * appears. */
      [self mainViewDidLoad];
    }
  return self;
}

- (NSView *)buildMainView
{
  // Built in code rather than from a nib so the margins come straight from
  // AppearanceMetrics.
  NSView *view = AUTORELEASE([[NSView alloc]
    initWithFrame: NSMakeRect(0, 0, PANE_WIDTH, PANE_HEIGHT)]);
  CGFloat margin = METRICS_CONTENT_SIDE_MARGIN;
  CGFloat gap = METRICS_BUTTON_HORIZ_INTERSPACE;
  CGFloat buttonHeight = METRICS_BUTTON_HEIGHT;
  CGFloat bottom = margin + buttonHeight + gap;
  NSTextField *heading;
  NSButtonCell *prototype;

  heading = AUTORELEASE([[NSTextField alloc] initWithFrame:
    NSMakeRect(margin, PANE_HEIGHT - margin - 18,
               PANE_WIDTH - 2 * margin - 110.0 - gap, 18)]);
  [heading setStringValue: @"Click a scheme to download it and use it"];
  [heading setFont: [NSFont boldSystemFontOfSize: 0]];
  [heading setEditable: NO];
  [heading setSelectable: NO];
  [heading setBordered: NO];
  [heading setBezeled: NO];
  [heading setDrawsBackground: NO];
  [view addSubview: heading];

  _refreshButton = AUTORELEASE([[NSButton alloc] initWithFrame:
    NSMakeRect(PANE_WIDTH - margin - 110.0, PANE_HEIGHT - margin - 20,
               110.0, buttonHeight)]);
  [_refreshButton setTitle: @"Refresh"];
  [_refreshButton setTarget: self];
  [_refreshButton setAction: @selector(refresh:)];
  [view addSubview: _refreshButton];

  prototype = AUTORELEASE([[NSButtonCell alloc] init]);
  [prototype setButtonType: NSMomentaryPushInButton];
  [prototype setImagePosition: NSImageAbove];
  [prototype setBordered: YES];
  [prototype setFont: [NSFont systemFontOfSize: 10.0]];
  [prototype setTarget: self];
  [prototype setAction: @selector(pickScheme:)];

  _previews = AUTORELEASE([[NSMatrix alloc]
    initWithFrame: NSMakeRect(0, 0, COLUMNS * PREVIEW_WIDTH, CELL_HEIGHT)
             mode: NSListModeMatrix
        prototype: prototype
     numberOfRows: 0
  numberOfColumns: 0]);
  [_previews setCellSize: NSMakeSize(PREVIEW_WIDTH, CELL_HEIGHT)];
  [_previews setIntercellSpacing: NSMakeSize(2, 2)];
  [_previews setAutosizesCells: NO];

  _scroll = AUTORELEASE([[NSScrollView alloc] initWithFrame:
    NSMakeRect(margin, bottom + 20,
               PANE_WIDTH - 2 * margin,
               PANE_HEIGHT - margin - 24 - bottom - 20)]);
  [_scroll setHasVerticalScroller: YES];
  [_scroll setBorderType: NSBezelBorder];
  [_scroll setDocumentView: _previews];
  [view addSubview: _scroll];
  // Scrolling is what asks for more pictures, so the scroll view has to say
  // when it has moved.
  [[_scroll contentView] setPostsBoundsChangedNotifications: YES];
  [[NSNotificationCenter defaultCenter]
    addObserver: self
       selector: @selector(visibleAreaChanged:)
           name: NSViewBoundsDidChangeNotification
         object: [_scroll contentView]];

  _progress = AUTORELEASE([[NSProgressIndicator alloc] initWithFrame:
    NSMakeRect(PANE_WIDTH - margin - 160.0, margin, 160.0, 14.0)]);
  [_progress setStyle: NSProgressIndicatorBarStyle];
  [_progress setIndeterminate: NO];
  [_progress setMinValue: 0.0];
  [_progress setMaxValue: 1.0];
  // Hidden until there is something to report: an empty bar sitting there
  // permanently would say a download was stuck.
  [_progress setHidden: YES];
  [view addSubview: _progress];

  _status = AUTORELEASE([[NSTextField alloc] initWithFrame:
    NSMakeRect(margin, margin, PANE_WIDTH - 2 * margin - 170.0, 18)]);
  [_status setEditable: NO];
  [_status setSelectable: YES];
  [_status setBordered: NO];
  [_status setBezeled: NO];
  [_status setDrawsBackground: NO];
  [view addSubview: _status];

  return view;
}

- (void)mainViewDidLoad
{
  KScheme *current = [[KSchemeStore sharedStore] selectedScheme];

  if (current != nil)
    [self setStatus: [NSString stringWithFormat:
      @"Using %@. Press Refresh to see what Mac Themes Garden has.",
      [current name]]];
  else
    [self setStatus: @"Press Refresh to see what Mac Themes Garden has."];
}

#pragma mark - Listing what the site has

- (void)refresh:(id)sender
{
  NSError *error = nil;
  NSArray *schemes;

  if (_busy)
    return;
  _busy = YES;
  [_refreshButton setEnabled: NO];
  [self setStatus: @"Asking macthemes.garden..."];
  [[_refreshButton window] displayIfNeeded];

  schemes = [[KGarden sharedGarden] recentSchemesWithError: &error];
  _busy = NO;
  [_refreshButton setEnabled: YES];
  if (schemes == nil)
    {
      [self setStatus: [error localizedDescription]];
      return;
    }
  ASSIGN(_schemes, schemes);
  [self rebuildMatrixForCount: [schemes count]];
  [self setStatus: [NSString stringWithFormat:
    @"%lu schemes. Scroll for more.", (unsigned long)[schemes count]]];
  ASSIGN(_tried, [NSMutableIndexSet indexSet]);
  [_pictureTimer invalidate];
  _pictureTimer = nil;
  [self loadVisiblePictures];
}

- (void)rebuildMatrixForCount:(NSUInteger)count
{
  NSUInteger rows = (count + COLUMNS - 1) / COLUMNS;
  NSUInteger i;

  while ([_previews numberOfRows] > 0)
    [_previews removeRow: 0];
  for (i = 0; i < rows; i++)
    [_previews addRow];
  [_previews renewRows: rows columns: COLUMNS];
  [_previews setCellSize: NSMakeSize(PREVIEW_WIDTH, CELL_HEIGHT)];

  for (i = 0; i < count; i++)
    {
      NSButtonCell *cell = [_previews cellAtRow: i / COLUMNS
                                         column: i % COLUMNS];

      [cell setTitle: [[_schemes objectAtIndex: i] title]];
      [cell setEnabled: YES];
      [cell setTag: i];
    }
  // Any cell past the end of the list is left empty and not clickable.
  for (i = count; i < rows * COLUMNS; i++)
    {
      NSButtonCell *cell = [_previews cellAtRow: i / COLUMNS
                                         column: i % COLUMNS];

      [cell setTitle: @""];
      [cell setEnabled: NO];
      [cell setTag: -1];
    }
  [_previews setFrameSize: NSMakeSize(COLUMNS * (PREVIEW_WIDTH + 2),
                                      rows * (CELL_HEIGHT + 2))];
  [_previews sizeToCells];
  [_previews setNeedsDisplay: YES];
}

#pragma mark - Pictures

/* Pictures are fetched lazily: only for the schemes on screen, and only once
 * each.
 *
 * There are a hundred schemes in the listing and each picture is its own
 * request, so fetching them all up front means a hundred requests for the
 * three rows anyone actually looks at. Scrolling brings more into view and
 * asks for those.
 *
 * The fetching happens on the main thread, one per timer tick. Not on a
 * background thread: GNUstep's URL loading wants a run loop on the thread that
 * asks, and off the main thread it simply returned nothing, so every cell
 * stayed blank. */

/* The schemes whose cells lie in the scrolled-to area, plus one row either
 * side so that a small scroll does not wait for a fetch. */
- (NSRange)visibleSchemeRange
{
  NSRect visible = [_previews visibleRect];
  CGFloat rowHeight = CELL_HEIGHT + 2.0;
  NSInteger firstRow, lastRow;
  NSUInteger first, count;

  if ([_schemes count] == 0 || rowHeight <= 0)
    return NSMakeRange(0, 0);
  firstRow = (NSInteger)floor(NSMinY(visible) / rowHeight) - 1;
  lastRow = (NSInteger)ceil(NSMaxY(visible) / rowHeight) + 1;
  if (firstRow < 0)
    firstRow = 0;
  first = (NSUInteger)firstRow * COLUMNS;
  if (first >= [_schemes count])
    return NSMakeRange(0, 0);
  count = ((NSUInteger)lastRow + 1) * COLUMNS - first;
  if (first + count > [_schemes count])
    count = [_schemes count] - first;
  return NSMakeRange(first, count);
}

- (void)loadVisiblePictures
{
  if (_pictureTimer != nil || [_schemes count] == 0)
    return;
  // A timer rather than a loop: the pane keeps drawing and scrolling between
  // one fetch and the next.
  _pictureTimer = [NSTimer scheduledTimerWithTimeInterval: 0.02
                                                   target: self
                                                 selector: @selector(loadNextPicture:)
                                                 userInfo: nil
                                                  repeats: YES];
}

- (void)visibleAreaChanged:(NSNotification *)note
{
  [self loadVisiblePictures];
}

- (void)loadNextPicture:(NSTimer *)timer
{
  NSRange range = [self visibleSchemeRange];
  NSUInteger index = NSNotFound, i;
  KGardenScheme *scheme;
  NSString *url;
  NSData *data;
  NSImage *picture;

  for (i = range.location; i < NSMaxRange(range); i++)
    {
      if (![_tried containsIndex: i])
        {
          index = i;
          break;
        }
    }
  if (index == NSNotFound)
    {
      // Everything in view has been fetched; the timer starts again when the
      // pane is scrolled.
      [_pictureTimer invalidate];
      _pictureTimer = nil;
      [self setStatus: @"Click a scheme to download it and use it."];
      return;
    }
  [_tried addIndex: index];

  scheme = [_schemes objectAtIndex: index];
  url = [scheme thumbnailURL];
  data = url != nil ? [[KGarden sharedGarden] previewDataForURL: url] : nil;
  if (data == nil)
    return;
  picture = AUTORELEASE([[NSImage alloc] initWithData: data]);
  if (picture == nil)
    return;
  // Scaled down to the cell rather than shown at 780 pixels wide.
  [picture setScalesWhenResized: YES];
  [picture setSize: NSMakeSize(PREVIEW_WIDTH - 10, PREVIEW_HEIGHT - 10)];
  if (index < (NSUInteger)([_previews numberOfRows] * COLUMNS))
    {
      [[_previews cellAtRow: index / COLUMNS column: index % COLUMNS]
        setImage: picture];
      [_previews setNeedsDisplay: YES];
    }
}

#pragma mark - Using a scheme

- (void)pickScheme:(id)sender
{
  NSInteger tag = [[_previews selectedCell] tag];
  KGardenScheme *theme;
  NSError *error = nil;
  NSString *archive;
  NSArray *added;
  KScheme *scheme;

  if (_busy)
    return;
  if (tag < 0 || tag >= (NSInteger)[_schemes count])
    return;
  theme = [_schemes objectAtIndex: tag];

  _busy = YES;
  [self setStatus: [NSString stringWithFormat: @"Downloading %@...",
    [theme title]]];
  [_progress setDoubleValue: 0.0];
  [_progress setHidden: NO];
  [[_previews window] displayIfNeeded];

  archive = [[KGarden sharedGarden]
    downloadArchiveForSchemePage: [theme pageURL]
                        progress: ^(double fraction) {
      /* Called between runs of the run loop while the archive arrives, so the
       * bar moves instead of the pane sitting frozen. A server that does not
       * say how big the file is gives -1, which is what the indeterminate
       * barber pole is for. */
      if (fraction < 0.0)
        {
          if (![_progress isIndeterminate])
            {
              [_progress setIndeterminate: YES];
              [_progress startAnimation: self];
            }
        }
      else
        {
          if ([_progress isIndeterminate])
            {
              [_progress stopAnimation: self];
              [_progress setIndeterminate: NO];
            }
          [_progress setDoubleValue: fraction];
        }
      [_progress setNeedsDisplay: YES];
      [[_progress window] displayIfNeeded];
    }
                           error: &error];
  if (archive == nil)
    {
      [self finishDownload];
      [self setStatus: [error localizedDescription]];
      return;
    }

  /* Unpacking is quick but not instant, and the bar has nothing to say about
   * it, so it goes indeterminate rather than sitting at full. */
  [self setStatus: [NSString stringWithFormat: @"Unpacking %@...",
    [theme title]]];
  [_progress setIndeterminate: YES];
  [_progress startAnimation: self];
  [[_previews window] displayIfNeeded];

  added = [[KSchemeStore sharedStore] installSchemesFromArchive: archive
                                                          error: &error];
  [[NSFileManager defaultManager] removeItemAtPath: archive error: NULL];
  [self finishDownload];
  if (added == nil)
    {
      [self setStatus: [error localizedDescription]];
      return;
    }

  /* An archive can hold several schemes; the first one is the one used, and
   * the rest stay in the library. */
  [[KSchemeStore sharedStore]
    selectSchemeWithFileName: [added objectAtIndex: 0]];
  scheme = [[KSchemeStore sharedStore] selectedScheme];
  if (scheme == nil)
    {
      [self setStatus: [NSString stringWithFormat:
        @"%@ downloaded, but its scheme could not be read.", [theme title]]];
      return;
    }
  [self setStatus: [NSString stringWithFormat: @"Now using %@.%@",
    [scheme name],
    [added count] > 1
      ? [NSString stringWithFormat: @" %lu more schemes from this download are"
         @" in your library.", (unsigned long)[added count] - 1]
      : @""]];
}

/* Puts the bar away again, whichever way the download ended. */
- (void)finishDownload
{
  if ([_progress isIndeterminate])
    [_progress stopAnimation: self];
  [_progress setIndeterminate: NO];
  [_progress setDoubleValue: 0.0];
  [_progress setHidden: YES];
  _busy = NO;
}

- (void)setStatus:(NSString *)text
{
  [_status setStringValue: text ?: @""];
  [[_status window] displayIfNeeded];
}

@end
