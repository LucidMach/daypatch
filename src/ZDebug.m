// TEMPORARY probe (untracked): dumps windows when /tmp/daypatch_dump exists.
#import "Common.h"
static void dumpView(NSView *v, int d, NSMutableString *o) {
    NSRect f = v.frame;
    [o appendFormat:@"%*s%@ (%.0f,%.0f %.0fx%.0f)%@ a=%.1f\n", d*2, "", NSStringFromClass(v.class), f.origin.x, f.origin.y, f.size.width, f.size.height, v.hidden ? @" HIDDEN" : @"", v.alphaValue];
    if (d < 9) for (NSView *s in v.subviews) dumpView(s, d+1, o);
}
__attribute__((constructor)) static void zinit(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t) {
            if (![NSFileManager.defaultManager fileExistsAtPath:@"/tmp/daypatch_dump"]) return;
            [NSFileManager.defaultManager removeItemAtPath:@"/tmp/daypatch_dump" error:nil];
            NSMutableString *o = [NSMutableString string];
            for (NSWindow *w in NSApp.windows) {
                NSRect f = w.frame;
                [o appendFormat:@"=== %@ full=%d (%.0f,%.0f %.0fx%.0f)\n", NSStringFromClass(w.class), !!(w.styleMask & NSWindowStyleMaskFullScreen), f.origin.x, f.origin.y, f.size.width, f.size.height];
                if (w.isVisible) dumpView(w.contentView.superview ?: w.contentView, 1, o);
            }
            [o writeToFile:@"/tmp/daypatch_views.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }];
    });
}
