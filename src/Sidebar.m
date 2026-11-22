// Adds an Arc-style URL pill below the tab sidebar header, plus back/forward/
// reload buttons in the header row next to the traffic lights. Clicking the pill
// (or ⌘L) opens Dia's own URL editor (autocomplete, history, tabs, search)
// anchored over the pill instead of the top bar.
#import "Common.h"
#import <objc/runtime.h>

static NSString *const kHeaderClass = @"TabSidebar.SidebarHeaderView";
static const CGFloat kRowHeight = 40;   // pill 30 + 2 top + 8 bottom
static const CGFloat kPillHeight = 30;
static const CGFloat kSideInset = 6;    // same as the pinned tiles and tabs below it
static const void *kBarKey = &kBarKey;
static const void *kNavKey = &kNavKey;
static const void *kGapKey = &kGapKey;
static void noteVisibility(NSView *c);

static void (*origLayout)(id, SEL);
static NSHashTable<NSView *> *gContainers;

static NSColor *dyn(CGFloat darkWhite, CGFloat darkAlpha, CGFloat lightWhite, CGFloat lightAlpha) {
    return [NSColor colorWithName:nil dynamicProvider:^NSColor *(NSAppearance *a) {
        BOOL dark = [[a bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqualToString:NSAppearanceNameDarkAqua];
        return dark ? [NSColor colorWithWhite:darkWhite alpha:darkAlpha] : [NSColor colorWithWhite:lightWhite alpha:lightAlpha];
    }];
}

#pragma mark - URL pill

@interface TweakSidebarURLBar : NSView
@property (nonatomic, strong) NSView *pill;
@property (nonatomic, strong) NSImageView *icon;
@property (nonatomic, strong) NSTextField *label;
@property (nonatomic, copy) NSString *currentURL;
@property (nonatomic) BOOL hovering;
@end

@implementation TweakSidebarURLBar

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _pill = [[NSView alloc] initWithFrame:NSZeroRect];
    _pill.wantsLayer = YES;
    _pill.layer.cornerRadius = 9;
    _pill.layer.cornerCurve = kCACornerCurveContinuous;
    [self addSubview:_pill];

    _icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _icon.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:10 weight:NSFontWeightMedium];
    _icon.contentTintColor = NSColor.secondaryLabelColor;
    [_pill addSubview:_icon];

    _label = [NSTextField labelWithString:@""];
    _label.font = [NSFont systemFontOfSize:12.5 weight:NSFontWeightMedium];
    _label.textColor = NSColor.labelColor;
    _label.lineBreakMode = NSLineBreakByTruncatingTail;
    _label.placeholderString = @"Search or enter URL";
    [_pill addSubview:_label];

    [self updateAppearance];
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)layout {
    [super layout];
    NSRect b = self.bounds;
    self.pill.frame = NSMakeRect(kSideInset, 2, NSWidth(b) - kSideInset * 2, kPillHeight);
    self.icon.frame = NSMakeRect(9, (kPillHeight - 14) / 2, 14, 14);
    CGFloat fh = 17;
    self.label.frame = NSMakeRect(27, (kPillHeight - fh) / 2, NSWidth(self.pill.frame) - 27 - 8, fh);
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *t in self.trackingAreas) [self removeTrackingArea:t];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect owner:self userInfo:nil]];
}

- (void)mouseEntered:(NSEvent *)e { self.hovering = YES; [self updateAppearance]; }
- (void)mouseExited:(NSEvent *)e { self.hovering = NO; [self updateAppearance]; }
- (void)mouseDown:(NSEvent *)e { [self openEditor]; }
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; [self updateAppearance]; }

- (void)updateAppearance {
    NSColor *bg = self.hovering ? dyn(1, 0.12, 0, 0.08) : dyn(1, 0.08, 0, 0.055);
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        self.pill.layer.backgroundColor = bg.CGColor;
    }];
}

- (void)refresh {
    NSString *u = TweakURLForWindow(self.window);
    if ([u isEqualToString:self.currentURL] && self.label.stringValue.length) return;
    self.currentURL = u;
    NSString *text = @"";
    if (u.length && ![u isEqualToString:@"about:blank"]) {
        NSURL *url = [NSURL URLWithString:u];
        NSString *host = url.host;
        if (TweakSettings.sidebarShowsFullURL || !host.length) text = u;
        else text = [host hasPrefix:@"www."] ? [host substringFromIndex:4] : host;
        // Dev servers and local services differ only by port: "localhost:3000", not "localhost".
        if (!TweakSettings.sidebarShowsFullURL && host.length && url.port) text = [text stringByAppendingFormat:@":%@", url.port];
    }
    self.label.stringValue = text;
    NSString *symbol = !u.length ? @"magnifyingglass" : ([u hasPrefix:@"https://"] ? @"lock.fill" : @"globe");
    self.icon.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil];
}

- (void)forceRefresh { self.currentURL = nil; self.label.stringValue = @""; [self refresh]; }

- (BOOL)openEditor {
    if (TweakCommandBarCurrentStyle() == TweakCommandBarStyleNative) return TweakCommandBarShow(self.window, NO);
    NSRect anchor = [self.pill convertRect:self.pill.bounds toView:nil];
    return TweakNavBarOpenEditor(self.window, anchor);
}

@end

#pragma mark - Nav buttons

@interface TweakNavButtons : NSView
@end

@implementation TweakNavButtons

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    NSArray *symbols = @[@"chevron.left", @"chevron.right", @"arrow.clockwise"];
    NSArray *labels = @[@"Back", @"Forward", @"Reload"];
    for (NSUInteger i = 0; i < symbols.count; i++) {
        NSButton *b = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:symbols[i] accessibilityDescription:labels[i]]
                                         target:self action:@selector(tap:)];
        b.bordered = NO;
        b.tag = i;
        b.toolTip = labels[i];
        b.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:12 weight:NSFontWeightSemibold];
        b.contentTintColor = NSColor.secondaryLabelColor;
        [self addSubview:b];
    }
    return self;
}

- (void)layout {
    [super layout];
    CGFloat w = 26, x = 0;
    for (NSView *b in self.subviews) { b.frame = NSMakeRect(x, 0, w, NSHeight(self.bounds)); x += w; }
}

- (void)tap:(NSButton *)sender { TweakNavBarPerform(self.window, sender.tag); }

@end

#pragma mark - Title observation

@interface TweakTitleObserver : NSObject
@property (nonatomic, copy) void (^onChange)(void);
@property (nonatomic, strong) NSHashTable<NSWindow *> *watched;
- (void)watch:(NSWindow *)w;
@end

@implementation TweakTitleObserver
- (instancetype)init {
    if ((self = [super init])) _watched = [NSHashTable weakObjectsHashTable];
    return self;
}
- (void)watch:(NSWindow *)w {
    if (!w || [self.watched containsObject:w] || ![NSStringFromClass(w.class) isEqualToString:@"Window.PlatformWindow"]) return;
    [self.watched addObject:w];
    [w addObserver:self forKeyPath:@"title" options:0 context:NULL];
    __weak typeof(self) weakSelf = self;
    __weak NSWindow *weakWindow = w;
    __block id token = [NSNotificationCenter.defaultCenter addObserverForName:NSWindowWillCloseNotification object:w queue:nil usingBlock:^(__unused NSNotification *n) {
        [weakWindow removeObserver:weakSelf forKeyPath:@"title"];
        [weakSelf.watched removeObject:weakWindow];
        [NSNotificationCenter.defaultCenter removeObserver:token];
        token = nil;  // breaks the token -> block -> token cycle
    }];
}
- (void)observeValueForKeyPath:(NSString *)k ofObject:(id)o change:(NSDictionary *)c context:(void *)ctx {
    // Title often changes just before the URL settles; refresh now and once more shortly after.
    if (self.onChange) self.onChange();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if (self.onChange) self.onChange(); });
}
@end

static TweakTitleObserver *gTitleObserver;

#pragma mark - Downloads button

// Dia puts the downloads button at the right end of the header row, where our nav
// buttons go. Move it to the footer, right after the library (chat) button.
static NSString *const kFooterClass = @"TabSidebar.SidebarContainerFooterView";
static NSString *const kDownloadsClass = @"TabSurface.DownloadsButtonView";
static void (*origFooterLayout)(id, SEL);

static NSView *findDescendant(NSView *root, NSString *cls) {
    for (NSView *s in root.subviews) {
        if ([NSStringFromClass(s.class) isEqualToString:cls]) return s;
        NSView *d = findDescendant(s, cls);
        if (d) return d;
    }
    return nil;
}

// Dia's downloads glyph is a heavy filled circle, unlike the thin line icons around it
// (chat, overflow). We hide Dia's glyph (the buttons keep their hover state, click
// handling and progress bar) and draw a line-style arrow over it instead.
@interface TweakDownloadsGlyph : NSImageView
@end
@implementation TweakDownloadsGlyph
- (NSView *)hitTest:(NSPoint)p { return nil; }  // clicks go to Dia's button underneath
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *a in self.trackingAreas) [self removeTrackingArea:a];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect owner:self userInfo:nil]];
}
// No hover background: the icon just brightens.
- (void)mouseEntered:(NSEvent *)e { self.contentTintColor = NSColor.labelColor; }
- (void)mouseExited:(NSEvent *)e { self.contentTintColor = NSColor.secondaryLabelColor; }
@end

static const void *kGlyphKey = &kGlyphKey;

static void styleDownloads(NSView *footer, NSView *dl) {
    TweakDownloadsGlyph *g = objc_getAssociatedObject(footer, kGlyphKey);
    if (!g) {
        g = [[TweakDownloadsGlyph alloc] initWithFrame:NSZeroRect];
        NSImage *img = [NSImage imageWithSystemSymbolName:@"arrow.down.circle" accessibilityDescription:@"Downloads"];
        g.image = [img imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:13 weight:NSFontWeightRegular]];
        g.contentTintColor = NSColor.secondaryLabelColor;
        g.imageScaling = NSImageScaleNone;
        objc_setAssociatedObject(footer, kGlyphKey, g, OBJC_ASSOCIATION_RETAIN);
    }
    if (g.superview != footer) [footer addSubview:g positioned:NSWindowAbove relativeTo:dl];
    g.frame = dl.frame;
    g.hidden = dl.hidden;
    for (NSView *b in dl.subviews)
        if ([NSStringFromClass(b.class) isEqualToString:@"TabSurface.TabSurfaceButton"])
            for (NSView *i in b.subviews) {
                NSString *ic = NSStringFromClass(i.class);
                BOOL glyph = [i isKindOfClass:NSImageView.class], bg = [ic isEqualToString:@"TabUI.TabBackgroundView"];
                if ((glyph || bg) && i.alphaValue != 0) i.alphaValue = 0;  // bg = hover highlight
            }
}

static void placeDownloads(NSView *footer) {
    NSView *dl = findDescendant(footer, kDownloadsClass);
    if (!dl) {
        // Still in the header: take it from there.
        NSView *c = footer.superview;
        NSView *header = c ? TweakChildOfClass(c, kHeaderClass) : nil;
        dl = header ? findDescendant(header, kDownloadsClass) : nil;
        if (!dl) return;
        [dl removeFromSuperview];
        dl.translatesAutoresizingMaskIntoConstraints = YES;
        [footer addSubview:dl];
    }
    NSView *lib = TweakChildOfClass(footer, @"DiaLibrary.LibraryButtonView");
    NSView *spaces = TweakChildOfClass(footer, @"TabSidebar.SpaceSwitcherView");
    CGFloat x = (lib && !lib.hidden) ? NSMaxX(lib.frame) + 2 : 15;
    CGFloat s = 34;
    NSRect f = NSMakeRect(x, MAX(0, (NSHeight(footer.bounds) - s) / 2), s, s);
    if (!NSEqualRects(dl.frame, f)) dl.frame = f;
    styleDownloads(footer, dl);
    if (spaces && NSMinX(spaces.frame) < NSMaxX(f)) {
        NSRect sf = spaces.frame;
        CGFloat right = NSMaxX(sf);
        sf.origin.x = NSMaxX(f);
        sf.size.width = MAX(0, right - sf.origin.x);
        spaces.frame = sf;
    }
}

// Dia shows the chat library as an icon button, plus an icon + "Chats" cell. The cell
// can be left with a 0x0 frame whose subviews (laid out at negative offsets) still draw,
// so the icon and label appear a second time, clipped at the sidebar's left edge. While
// the button is on screen the cell is redundant: hide it.
static void dedupeLibrary(NSView *footer) {
    NSView *cell = TweakChildOfClass(footer, @"TabSidebar.LibraryCellView");
    NSView *button = TweakChildOfClass(footer, @"DiaLibrary.LibraryButtonView");
    if (!cell || !button) return;
    BOOL buttonShown = !button.hidden && button.alphaValue > 0 && NSWidth(button.frame) > 0;
    if (buttonShown && !cell.hidden) cell.hidden = YES;
}

static void hookedFooterLayout(NSView *self, SEL _cmd) {
    origFooterLayout(self, _cmd);
    dedupeLibrary(self);
    placeDownloads(self);
}

#pragma mark - Container layout

static TweakSidebarURLBar *barFor(NSView *container) { return objc_getAssociatedObject(container, kBarKey); }

static NSView *bodyFor(NSView *container, NSView *header) {
    for (NSView *s in container.subviews)
        if (s != header && s != barFor(container) && [NSStringFromClass(s.class) isEqualToString:@"ARCUI.FlippedView"]) return s;
    return nil;
}

static void applyContainer(NSView *c) {
    NSView *header = TweakChildOfClass(c, kHeaderClass);
    NSView *body = header ? bodyFor(c, header) : nil;
    if (!header || !body || !c.isFlipped) return;

    CGFloat headerBottom = NSMaxY(header.frame);
    CGFloat H = NSHeight(c.bounds);
    // Remember the gap Dia leaves below the body (captured while unshifted).
    if (NSMinY(body.frame) == headerBottom)
        objc_setAssociatedObject(c, kGapKey, @(H - NSMaxY(body.frame)), OBJC_ASSOCIATION_RETAIN);
    CGFloat gap = [objc_getAssociatedObject(c, kGapKey) doubleValue];

    // Attached even while the sidebar is collapsed, so the top bar stays hidden then.
    BOOL on = TweakSettings.urlBarMode == TweakURLBarModeSidebar;
    TweakSidebarURLBar *bar = barFor(c);
    if (on && !bar) {
        bar = [[TweakSidebarURLBar alloc] initWithFrame:NSZeroRect];
        objc_setAssociatedObject(c, kBarKey, bar, OBJC_ASSOCIATION_RETAIN);
    }
    if (on && bar.superview != c) [c addSubview:bar positioned:NSWindowAbove relativeTo:header];
    if (!on) [bar removeFromSuperview];

    CGFloat top = headerBottom + (on ? kRowHeight : 0);
    NSRect bf = NSMakeRect(NSMinX(body.frame), top, NSWidth(body.frame), MAX(0, H - top - gap));
    if (!NSEqualRects(bf, body.frame)) body.frame = bf;
    if (on) {
        bar.frame = NSMakeRect(0, headerBottom, NSWidth(c.bounds), kRowHeight);
        [bar refresh];
    }

    TweakNavButtons *nav = objc_getAssociatedObject(header, kNavKey);
    BOOL navOn = on && TweakSettings.sidebarShowsNavButtons;
    if (navOn && !nav) {
        nav = [[TweakNavButtons alloc] initWithFrame:NSZeroRect];
        objc_setAssociatedObject(header, kNavKey, nav, OBJC_ASSOCIATION_RETAIN);
    }
    if (navOn) {
        if (nav.superview != header) [header addSubview:nav];
        // Vertically centre on the traffic lights' stack.
        NSView *stack = header.subviews.firstObject;
        CGFloat mid = stack ? NSMidY(stack.frame) : NSHeight(header.bounds) / 2;
        CGFloat w = 78, h = 26;
        nav.frame = NSMakeRect(NSWidth(header.bounds) - w - 8, mid - h / 2, w, h);
    } else {
        [nav removeFromSuperview];
    }
}

// Adds or removes the bar; if that changed, the top bar re-evaluates its visibility
// (it depends on whether this window has a sidebar URL bar). Deferred: callers may be
// inside a layout pass.
static void reapplyContainer(NSView *c) {
    BOOL had = barFor(c).superview != nil;
    applyContainer(c);
    if (had != (barFor(c).superview != nil))
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:TweakSettingsDidChangeNotification object:nil];
        });
}

static void hookedLayout(NSView *self, SEL _cmd) {
    origLayout(self, _cmd);
    [gContainers addObject:self];
    reapplyContainer(self);
    noteVisibility(self);
}

static TweakSidebarURLBar *visibleBar(NSWindow *window) {
    for (NSView *c in gContainers.allObjects) {
        TweakSidebarURLBar *bar = barFor(c);
        if (c.window == window && bar.superview && !c.isHiddenOrHasHiddenAncestor && NSWidth(c.frame) > 40) return bar;
    }
    return nil;
}

// Whether the top bar should give way: true while the window's sidebar has the bar,
// also when the sidebar is collapsed (Arc-like: no top bar either way), unless the
// user wants Dia's bar back while the sidebar is hidden.
BOOL TweakSidebarHasURLBar(NSWindow *window) {
    if (TweakSettings.topBarWhenSidebarHidden) return visibleBar(window) != nil;
    for (NSView *c in gContainers.allObjects)
        if (c.window == window && barFor(c).superview) return YES;
    return NO;
}

// With the top bar shown while the sidebar is hidden, it follows the sidebar sliding
// in and out: re-evaluate whenever a container's visibility flips.
static const void *kShownKey = &kShownKey;
static void noteVisibility(NSView *c) {
    if (!TweakSettings.topBarWhenSidebarHidden) return;
    BOOL shown = !c.isHiddenOrHasHiddenAncestor && NSWidth(c.frame) > 40;
    NSNumber *was = objc_getAssociatedObject(c, kShownKey);
    objc_setAssociatedObject(c, kShownKey, @(shown), OBJC_ASSOCIATION_RETAIN);
    if (was && was.boolValue != shown)
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:TweakSettingsDidChangeNotification object:nil];
        });
}

BOOL TweakSidebarFocusURLBar(NSWindow *window) { return [visibleBar(window) openEditor]; }

void TweakSidebarInstall(void) {
    Class cls = TweakFindClass(@"_TtC10TabSidebar", @"SidebarContainerRootView");
    if (!cls) { NSLog(@"[daypatch] SidebarContainerRootView not found; sidebar URL bar inactive"); return; }
    gContainers = [NSHashTable weakObjectsHashTable];
    origLayout = (void *)TweakHook(cls, @selector(layout), (IMP)hookedLayout);
    Class footer = NSClassFromString(kFooterClass);
    if (footer) origFooterLayout = (void *)TweakHook(footer, @selector(layout), (IMP)hookedFooterLayout);
    // Refresh on navigation-ish events: Dia's window title follows the active tab's
    // page title, and switching windows/tabs changes it too. A slow timer covers
    // pages that change URL without changing title. Also attaches a bar the container's
    // layout couldn't (its header or body not there yet): nothing may lay it out again.
    // Add-only, so a transient hide never flips back to the top bar.
    void (^refreshAll)(void) = ^{
        for (NSView *c in gContainers.allObjects) {
            if (!barFor(c).superview) reapplyContainer(c);
            noteVisibility(c);
            [barFor(c) refresh];
        }
    };
    gTitleObserver = [TweakTitleObserver new];
    gTitleObserver.onChange = refreshAll;
    for (NSNotificationName n in @[NSWindowDidBecomeKeyNotification, NSWindowDidBecomeMainNotification, NSWindowDidUpdateNotification])
        [NSNotificationCenter.defaultCenter addObserverForName:n object:nil queue:nil usingBlock:^(NSNotification *note) {
            NSWindow *w = note.object;
            if (n == NSWindowDidUpdateNotification) { [gTitleObserver watch:w]; return; }
            refreshAll();
        }];
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:3 repeats:YES block:^(__unused NSTimer *t) { refreshAll(); }];
    timer.tolerance = 1;
    [NSNotificationCenter.defaultCenter addObserverForName:TweakSettingsDidChangeNotification object:nil queue:nil
                                                usingBlock:^(__unused NSNotification *n) {
        for (NSView *c in gContainers.allObjects) {
            applyContainer(c);
            [barFor(c) forceRefresh];
        }
    }];
}
