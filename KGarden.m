/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "KGarden.h"

@interface KGarden (Private)
- (NSString *)md5OfData:(NSData *)data;
@end

static NSString * const KGardenBase = @"https://macthemes.garden";
static NSString * const KGardenFeed = @"https://macthemes.garden/feed.xml";

/* Where a scheme page links its archive. The site's own host comes first and
 * is preferred; the rest are the mirrors it lists, and some scheme pages offer
 * only those. A link to any other host is not followed. */
static NSString * const KGardenArchiveHosts[] = {
  @"files.macthemes.garden",
  @"macthemes.drac.at",
  @"macthemes.jkap.io",
  @"themes.lizard.tools"
};
static const NSUInteger KGardenArchiveHostCount
  = sizeof(KGardenArchiveHosts) / sizeof(KGardenArchiveHosts[0]);

static NSError *KGardenError(NSInteger code, NSString *message)
{
  return [NSError errorWithDomain: @"KGarden"
                             code: code
                         userInfo: @{NSLocalizedDescriptionKey: message}];
}

/* Every match of a very small subset of regular expression: a literal prefix,
 * then everything up to a terminator. Enough to pull links out of HTML without
 * bringing in a parser, and it cannot run away because both ends are literal. */
static NSArray *KMatches(NSString *text, NSString *prefix, NSString *terminator)
{
  NSMutableArray *found = [NSMutableArray array];
  NSRange search = NSMakeRange(0, [text length]);

  while (search.length > 0)
    {
      NSRange start = [text rangeOfString: prefix options: 0 range: search];
      NSRange rest, end;

      if (start.location == NSNotFound)
        break;
      rest = NSMakeRange(NSMaxRange(start),
                         [text length] - NSMaxRange(start));
      end = [text rangeOfString: terminator options: 0 range: rest];
      if (end.location == NSNotFound)
        break;
      [found addObject: [text substringWithRange:
        NSMakeRange(start.location,
                    end.location - start.location)]];
      search = NSMakeRange(NSMaxRange(end), [text length] - NSMaxRange(end));
    }
  return found;
}

/* The few XML entities the feed's titles carry. Without this a theme called
 * "Persephone's Torch" is listed as "Persephone&apos;s Torch". */
static NSString *KUnescape(NSString *text)
{
  NSMutableString *out = AUTORELEASE([text mutableCopy]);
  /* &amp; is last, or an escaped entity would be decoded twice. */
  NSArray *pairs = @[@"&lt;", @"<", @"&gt;", @">", @"&quot;", @"\"",
                     @"&apos;", @"'", @"&#39;", @"'", @"&#x27;", @"'",
                     @"&amp;", @"&"];
  NSUInteger i;

  for (i = 0; i + 1 < [pairs count]; i += 2)
    [out replaceOccurrencesOfString: [pairs objectAtIndex: i]
                        withString: [pairs objectAtIndex: i + 1]
                           options: 0
                             range: NSMakeRange(0, [out length])];
  return out;
}

/* The feed writes its image links with a doubled slash after the host. */
static NSString *KTidyURL(NSString *url)
{
  NSMutableString *out = AUTORELEASE([url mutableCopy]);

  [out replaceOccurrencesOfString: @"garden//" withString: @"garden/"
                         options: 0 range: NSMakeRange(0, [out length])];
  return out;
}

/* One https GET.
 *
 * Not +[NSData dataWithContentsOfURL:]: it hands back the body of the first
 * URL fetched for every URL asked for afterwards, so all hundred preview
 * pictures came back as a copy of the RSS feed. A request that ignores the
 * cache goes to the server each time, which is what we need here anyway. */
static NSData *KFetchData(NSString *urlString, NSError **error)
{
  NSURL *url = [NSURL URLWithString: urlString];
  NSMutableURLRequest *request;
  NSURLResponse *response = nil;
  NSError *failure = nil;
  NSData *data;

  if (url == nil || ![[url scheme] isEqualToString: @"https"])
    {
      if (error != NULL)
        *error = KGardenError(1, @"That is not an https address.");
      return nil;
    }
  request = [NSMutableURLRequest requestWithURL: url];
  [request setCachePolicy: NSURLRequestReloadIgnoringCacheData];
  [request setTimeoutInterval: 30.0];
  data = [NSURLConnection sendSynchronousRequest: request
                              returningResponse: &response
                                          error: &failure];
  if (data == nil)
    {
      if (error != NULL)
        *error = KGardenError(2, [NSString stringWithFormat:
          @"Could not reach %@%@.", [url host],
          failure != nil
            ? [@": " stringByAppendingString: [failure localizedDescription]]
            : @""]);
      return nil;
    }
  return data;
}

static NSString *KFetchString(NSString *urlString, NSError **error)
{
  NSData *data = KFetchData(urlString, error);

  if (data == nil)
    return nil;
  return AUTORELEASE([[NSString alloc] initWithData: data
                                          encoding: NSUTF8StringEncoding]);
}


/* An asynchronous fetch that can be watched while it runs.
 *
 * The synchronous request used everywhere else gives no sign of life until it
 * finishes, which is fine for a page of HTML and useless for an archive: the
 * pane would freeze with nothing to show. This collects the body through the
 * connection's delegate so the caller can run the run loop, redraw, and see
 * how far it has got. */
@interface KDownload : NSObject
{
  NSMutableData *_data;
  long long _expected;
  BOOL _finished;
  NSError *_error;
}
@property (nonatomic, readonly) BOOL finished;
@property (nonatomic, readonly) long long expected;
@property (nonatomic, readonly) NSError *error;
- (NSData *)data;
- (double)fraction;
@end

@implementation KDownload

@synthesize finished = _finished;
@synthesize expected = _expected;
@synthesize error = _error;

- (id)init
{
  if ((self = [super init]) != nil)
    {
      _data = [[NSMutableData alloc] init];
      _expected = -1;
    }
  return self;
}

- (void)dealloc
{
  [_data release];
  [_error release];
  [super dealloc];
}

- (NSData *)data
{
  return _data;
}

- (double)fraction
{
  if (_expected <= 0)
    return -1.0;                       /* the server did not say how big */
  return (double)[_data length] / (double)_expected;
}

- (void)connection:(NSURLConnection *)connection
  didReceiveResponse:(NSURLResponse *)response
{
  _expected = [response expectedContentLength];
  [_data setLength: 0];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
  [_data appendData: data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
  _finished = YES;
}

- (void)connection:(NSURLConnection *)connection
  didFailWithError:(NSError *)error
{
  ASSIGN(_error, error);
  _finished = YES;
}

@end


/* One https GET whose progress can be watched. Falls back to the plain
 * synchronous fetch when no handler wants to hear about it. */
static NSData *KFetchDataWatched(NSString *urlString, KProgressHandler progress,
                                 NSError **error)
{
  NSURL *url = [NSURL URLWithString: urlString];
  NSMutableURLRequest *request;
  KDownload *watcher;
  NSURLConnection *connection;
  NSDate *deadline;

  if (progress == nil)
    return KFetchData(urlString, error);
  if (url == nil || ![[url scheme] isEqualToString: @"https"])
    {
      if (error != NULL)
        *error = KGardenError(1, @"That is not an https address.");
      return nil;
    }
  request = [NSMutableURLRequest requestWithURL: url];
  [request setCachePolicy: NSURLRequestReloadIgnoringCacheData];
  [request setTimeoutInterval: 30.0];
  watcher = AUTORELEASE([[KDownload alloc] init]);
  connection = [[NSURLConnection alloc] initWithRequest: request
                                               delegate: watcher];
  if (connection == nil)
    {
      if (error != NULL)
        *error = KGardenError(2, @"Could not start the download.");
      return nil;
    }
  progress(-1.0);
  /* Runs the caller's run loop rather than blocking it, so the window that
   * asked for this keeps drawing while the bytes come in. */
  deadline = [NSDate dateWithTimeIntervalSinceNow: 120.0];
  while (![watcher finished] && [deadline timeIntervalSinceNow] > 0)
    {
      [[NSRunLoop currentRunLoop]
        runMode: NSDefaultRunLoopMode
        beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]];
      progress([watcher fraction]);
    }
  [connection release];
  if (![watcher finished])
    {
      if (error != NULL)
        *error = KGardenError(2, @"The download timed out.");
      return nil;
    }
  if ([watcher error] != nil || [[watcher data] length] == 0)
    {
      if (error != NULL)
        *error = KGardenError(2, [NSString stringWithFormat: @"Could not reach %@%@.",
          [url host], [watcher error] != nil
            ? [@": " stringByAppendingString:
                [[watcher error] localizedDescription]] : @""]);
      return nil;
    }
  progress(1.0);
  return [watcher data];
}

@implementation KGardenScheme
@synthesize title = _title;
@synthesize pageURL = _pageURL;
@synthesize thumbnailURL = _thumbnailURL;

- (void)dealloc
{
  [_title release];
  [_pageURL release];
  [_thumbnailURL release];
  [super dealloc];
}

@end

@implementation KGarden

+ (instancetype)sharedGarden
{
  static KGarden *garden = nil;

  if (garden == nil)
    garden = [[self alloc] init];
  return garden;
}

- (NSArray *)recentSchemesWithError:(NSError **)error
{
  NSString *feed = KFetchString(KGardenFeed, error);
  NSMutableArray *themes;
  NSEnumerator *items;
  NSString *item;

  if (feed == nil)
    return nil;
  themes = [NSMutableArray array];
  // The feed is one <item> per theme, each with a <title> and a <link>.
  items = [KMatches(feed, @"<item>", @"</item>") objectEnumerator];
  while ((item = [items nextObject]) != nil)
    {
      NSArray *titles = KMatches(item, @"<title>", @"</title>");
      NSArray *links = KMatches(item, @"<link>", @"</link>");
      NSArray *images = KMatches(item, @"src=&quot;", @"&quot;");
      KGardenScheme *theme;

      if ([titles count] == 0 || [links count] == 0)
        continue;
      theme = AUTORELEASE([[KGardenScheme alloc] init]);
      [theme setTitle: KUnescape([[titles objectAtIndex: 0]
                         substringFromIndex: [@"<title>" length]])];
      [theme setPageURL: [[links objectAtIndex: 0]
                           substringFromIndex: [@"<link>" length]]];
      {
        /* Each item carries a sampler, an about shot and a showcase shot. The
         * sampler is the one that shows the widgets, so it is the preview. */
        NSEnumerator *pictures = [images objectEnumerator];
        NSString *candidate, *chosen = nil;

        while ((candidate = [pictures nextObject]) != nil)
          {
            NSString *url = [candidate
              substringFromIndex: [@"src=&quot;" length]];

            if (chosen == nil)
              chosen = url;
            if ([url rangeOfString: @"ksa-sampler"].location != NSNotFound)
              {
                chosen = url;
                break;
              }
          }
        if (chosen != nil)
          [theme setThumbnailURL: KTidyURL(chosen)];
      }
      [themes addObject: theme];
    }
  if ([themes count] == 0)
    {
      if (error != NULL)
        *error = KGardenError(3, @"The feed held no themes.");
      return nil;
    }
  return themes;
}

- (NSData *)previewDataForURL:(NSString *)urlString
{
  NSURL *url = [NSURL URLWithString: urlString];
  NSString *host = [url host];

  if (url == nil || ![[url scheme] isEqualToString: @"https"])
    return nil;
  /* Only the site's own hosts: the addresses come out of a feed, and wanting
   * a preview is no reason to fetch from wherever the feed happens to name. */
  if (![host isEqualToString: @"macthemes.garden"]
      && ![host isEqualToString: @"cdn.macthemes.garden"])
    return nil;
  return KFetchData(urlString, NULL);
}

- (NSString *)downloadArchiveForSchemePage:(NSString *)pageURLOrSlug
                                    error:(NSError **)error
{
  return [self downloadArchiveForSchemePage: pageURLOrSlug
                                   progress: nil
                                      error: error];
}

- (NSString *)downloadArchiveForSchemePage:(NSString *)pageURLOrSlug
                                  progress:(KProgressHandler)progress
                                     error:(NSError **)error
{
  NSString *pageURL = pageURLOrSlug;
  NSString *page, *archiveURL = nil, *expectedMD5 = nil;
  NSArray *links;
  NSData *archive;
  NSString *destination;

  if ([pageURLOrSlug length] == 0)
    {
      if (error != NULL)
        *error = KGardenError(4, @"No theme was given.");
      return nil;
    }
  if (![pageURL hasPrefix: @"https://"])
    pageURL = [NSString stringWithFormat: @"%@/themes/%@", KGardenBase,
                pageURLOrSlug];
  if (![pageURL hasPrefix: [KGardenBase stringByAppendingString: @"/"]])
    {
      if (error != NULL)
        *error = KGardenError(5, @"That address is not on macthemes.garden.");
      return nil;
    }

  page = KFetchString(pageURL, error);
  if (page == nil)
    return nil;

  /* The page links the archive and, on the site's own host, an .md5 beside it.
   * The hosts are tried in order, so the site's own copy wins and a mirror is
   * only used for a scheme that is offered nowhere else. */
  {
    NSUInteger host;

    for (host = 0; host < KGardenArchiveHostCount && archiveURL == nil; host++)
      {
        NSEnumerator *e;
        NSString *link;

        links = KMatches(page, [NSString stringWithFormat: @"https://%@/",
                                 KGardenArchiveHosts[host]], @"\"");
        e = [links objectEnumerator];
        while ((link = [e nextObject]) != nil)
          {
            if ([link hasSuffix: @".sit"] && archiveURL == nil)
              archiveURL = link;
            else if ([link hasSuffix: @".sit.md5"] && expectedMD5 == nil)
              expectedMD5 = link;
          }
      }
  }
  if (archiveURL == nil)
    {
      if (error != NULL)
        *error = KGardenError(6, @"That scheme page offers no download, on the"
                              @" site or on any of its mirrors.");
      return nil;
    }

  archive = KFetchDataWatched(archiveURL, progress, NULL);
  if (archive == nil)
    {
      if (error != NULL)
        *error = KGardenError(7, @"The archive could not be downloaded.");
      return nil;
    }

  /* The site publishes an MD5 next to each archive. It is a check that the
   * download arrived intact, which is all MD5 is good for; it is not treated
   * as proof of where the file came from. */
  if (expectedMD5 != nil)
    {
      NSString *published = KFetchString(expectedMD5, NULL);
      NSString *actual = [self md5OfData: archive];

      if ([published length] >= 32 && actual != nil)
        {
          NSString *want = [[published substringToIndex: 32] lowercaseString];

          if (![want isEqualToString: actual])
            {
              if (error != NULL)
                *error = KGardenError(8, @"The download did not match the"
                                      @" checksum published for it.");
              return nil;
            }
        }
    }

  destination = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat: @"kaleidoscope-%d-%@", (int)getpid(),
      [archiveURL lastPathComponent]]];
  if (![archive writeToFile: destination atomically: YES])
    {
      if (error != NULL)
        *error = KGardenError(9, @"The download could not be saved.");
      return nil;
    }
  return destination;
}

/* md5 through the system tool: there is no digest in Foundation, and pulling
 * in a crypto library for an integrity check on a 1990s archive is not worth
 * the dependency. */
- (NSString *)md5OfData:(NSData *)data
{
  NSTask *task = AUTORELEASE([[NSTask alloc] init]);
  NSPipe *out = [NSPipe pipe];
  NSPipe *in = [NSPipe pipe];
  NSString *text;
  NSArray *fields;

  if (![[NSFileManager defaultManager] fileExistsAtPath: @"/usr/bin/md5sum"])
    return nil;
  [task setLaunchPath: @"/usr/bin/md5sum"];
  [task setArguments: @[@"-"]];
  [task setStandardInput: in];
  [task setStandardOutput: out];
  [task setStandardError: [NSFileHandle fileHandleWithNullDevice]];
  NS_DURING
    [task launch];
    [[in fileHandleForWriting] writeData: data];
    [[in fileHandleForWriting] closeFile];
    text = AUTORELEASE([[NSString alloc]
      initWithData: [[out fileHandleForReading] readDataToEndOfFile]
          encoding: NSASCIIStringEncoding]);
    [task waitUntilExit];
  NS_HANDLER
    return nil;
  NS_ENDHANDLER
  fields = [text componentsSeparatedByString: @" "];
  if ([fields count] == 0 || [[fields objectAtIndex: 0] length] != 32)
    return nil;
  return [[fields objectAtIndex: 0] lowercaseString];
}

@end
