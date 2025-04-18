#import <CoreFoundation/CoreFoundation.h>
#include <objc/message.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <objc/runtime.h>  // For associated objects
#import <mach/mach.h>

extern void *WindowTitlebarKey;
static void *TitlebarObserverKey = &TitlebarObserverKey;

@interface TitlebarObserver : NSObject
@property (nonatomic, assign) NSWindow    *window;
@property (nonatomic, assign) NSTextField *titleLabel;
@end

@implementation TitlebarObserver

- (instancetype)initWithWindow:(NSWindow *)window
                   titleLabel:(NSTextField *)label
{
    if ((self = [super init])) {
        _window     = window;
        _titleLabel = label;
        // Set initial title
        _titleLabel.stringValue = window.title ?: @"";
        // Observe future changes
        [window addObserver:self
                 forKeyPath:@"title"
                    options:NSKeyValueObservingOptionNew
                    context:NULL];
    }
    return self;
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context
{
    if (object == self.window && [keyPath isEqualToString:@"title"]) {
        NSString *newTitle = change[NSKeyValueChangeNewKey];
        // KVO sometimes delivers NSNull
        if ((id)newTitle == [NSNull null]) newTitle = @"";
        self.titleLabel.stringValue = newTitle;
    } else {
        [super observeValueForKeyPath:keyPath
                             ofObject:object
                               change:change
                              context:context];
    }
}

- (void)dealloc {
    [self.window removeObserver:self forKeyPath:@"title"];
}

@end

NSView *FindTitlebarDecorationView(NSView *view) {
    if ([[view className] isEqualToString:@"_NSTitlebarDecorationView"]) {
        return view;
    }

    for (NSView *subview in view.subviews) {
        NSView *result = FindTitlebarDecorationView(subview);
        if (result) return result;
    }

    return nil;
}

NSView *GetTitlebarDecorationViewFromWindow(NSWindow *window) {
    return FindTitlebarDecorationView(window.contentView.superview);
}

NSImage *CreateColorSwatchFromARGB(uint32_t argb) {
    CGFloat width = 4.0;
    CGFloat height = 4.0;

    // Extract components from 0xAARRGGBB
    CGFloat alpha = ((argb >> 24) & 0xFF) / 255.0;
    CGFloat red   = ((argb >> 16) & 0xFF) / 255.0;
    CGFloat green = ((argb >> 8)  & 0xFF) / 255.0;
    CGFloat blue  = (argb & 0xFF) / 255.0;

    NSColor *color = [NSColor colorWithCalibratedRed:red green:green blue:blue alpha:alpha];
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(width, height)];

    [image lockFocus];
    [color setFill];
    NSRectFill(NSMakeRect(0, 0, width, height));
    [image unlockFocus];

    return image;
}

void MakeTitlebar(
    NSWindow **outWindow,
    NSWindow *mainWindow,
    bool button_position,
    bool title_or_icon,
    int height,
    NSImage * _Nullable backgroundImage
) {
    // Calculate frame for the titlebar window
    NSRect mainFrame = mainWindow.frame;
    NSRect titlebarFrame = NSMakeRect(
        mainFrame.origin.x,
        NSMaxY(mainFrame),
        mainFrame.size.width,
        height
    );
    
    // Initialize borderless window
    *outWindow = [[NSWindow alloc] initWithContentRect:titlebarFrame
                                            styleMask:NSWindowStyleMaskBorderless
                                              backing:NSBackingStoreBuffered
                                                defer:NO];
    [*outWindow setLevel:[mainWindow level]];
    [*outWindow setOpaque:NO];
    [*outWindow setIgnoresMouseEvents:NO];
    [GetTitlebarDecorationViewFromWindow(mainWindow) removeFromSuperview];

    NSView *contentView = [*outWindow contentView];
    contentView.wantsLayer = YES;

    // Background view or color
    if (backgroundImage) {
        NSImageView *bgView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        bgView.translatesAutoresizingMaskIntoConstraints = NO;
        bgView.image = backgroundImage;
        bgView.imageScaling = NSImageScaleAxesIndependently;
        [contentView addSubview:bgView];
        [NSLayoutConstraint activateConstraints:@[
            [bgView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
            [bgView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
            [bgView.topAnchor constraintEqualToAnchor:contentView.topAnchor],
            [bgView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor]
        ]];
    } else {
        contentView.layer.backgroundColor = [NSColor systemBlueColor].CGColor;
    }

    NSArray<NSDictionary*> *buttonSpecs = @[
        @{ @"symbolName": @"xmark.circle.fill",     @"action": @"performClose:" },
        @{ @"symbolName": @"minus.circle.fill",     @"action": @"performMiniaturize:" },
        @{ @"symbolName": @"arrow.up.left.and.arrow.down.right.circle.fill", @"action": @"performZoom:" }
    ];

    CGFloat btnSize = 14.0;
    CGFloat buttonPadding = 6.0;
    CGFloat edgePadding = 10.0;

    // Determine layout direction
    BOOL alignRight = !button_position;
    NSArray *orderedSpecs = alignRight ? [[buttonSpecs reverseObjectEnumerator] allObjects] : buttonSpecs;

    __block NSButton *adjacentBtn = nil;

    for (NSDictionary *spec in orderedSpecs) {
        NSImage *img = [NSImage imageWithSystemSymbolName:spec[@"symbolName"] accessibilityDescription:nil];
        img.template = YES;

        NSButton *btn = [NSButton buttonWithImage:img
                                        target:mainWindow
                                        action:NSSelectorFromString(spec[@"action"])];
        btn.bezelStyle = NSBezelStyleRegularSquare;
        btn.translatesAutoresizingMaskIntoConstraints = NO;
        btn.bordered = NO;
        [contentView addSubview:btn];

        NSMutableArray<NSLayoutConstraint *> *constraints = [@[
            [btn.widthAnchor constraintEqualToConstant:btnSize],
            [btn.heightAnchor constraintEqualToConstant:btnSize],
            [btn.centerYAnchor constraintEqualToAnchor:contentView.centerYAnchor]
        ] mutableCopy];

        if (adjacentBtn) {
            [constraints addObject:alignRight
                ? [btn.trailingAnchor constraintEqualToAnchor:adjacentBtn.leadingAnchor constant:-buttonPadding]
                : [btn.leadingAnchor constraintEqualToAnchor:adjacentBtn.trailingAnchor constant:buttonPadding]];
        } else {
            [constraints addObject:alignRight
                ? [btn.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-edgePadding]
                : [btn.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:edgePadding]];
        }

        [NSLayoutConstraint activateConstraints:constraints];
        adjacentBtn = btn;
    }

    // Title OR app‑icon
    if (title_or_icon) {
        NSTextField *titleLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.stringValue = @"";
        titleLabel.bezeled = NO;
        titleLabel.drawsBackground = NO;
        titleLabel.editable = NO;
        titleLabel.selectable = NO;
        titleLabel.textColor = [NSColor whiteColor];
        titleLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
        [contentView addSubview:titleLabel];
        [NSLayoutConstraint activateConstraints:@[
            [titleLabel.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],
            [titleLabel.centerYAnchor constraintEqualToAnchor:contentView.centerYAnchor]
        ]];

        TitlebarObserver *observer =
            [[TitlebarObserver alloc] initWithWindow:mainWindow
                                          titleLabel:titleLabel];
        objc_setAssociatedObject(
            mainWindow,
            TitlebarObserverKey,
            observer,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    } else {
        // — App‑bundle icon only (non‑clickable) —
        NSImage *bundleIcon = [NSApp applicationIconImage];
        NSImageView *iconView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        iconView.translatesAutoresizingMaskIntoConstraints = NO;
        iconView.image = bundleIcon;
        iconView.imageScaling = NSImageScaleProportionallyUpOrDown;
        iconView.canDrawSubviewsIntoLayer = YES;  // ensure proper layer-backed drawing
        [contentView addSubview:iconView];

        CGFloat padding = 8.0;
        [NSLayoutConstraint activateConstraints:@[
            [iconView.centerYAnchor   constraintEqualToAnchor:contentView.centerYAnchor],
            (button_position == 0
                ? [iconView.leadingAnchor  constraintEqualToAnchor:contentView.leadingAnchor  constant:padding]
                : [iconView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-padding]),
            // constrain a reasonable size
            [iconView.widthAnchor     constraintEqualToConstant:20.0],
            [iconView.heightAnchor    constraintEqualToConstant:20.0]
        ]];
    }

    // Attach as child window
    [mainWindow addChildWindow:*outWindow ordered:NSWindowAbove];

    // Associate for lifetime management
    objc_setAssociatedObject(
        mainWindow,
        WindowTitlebarKey,
        *outWindow,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
}

