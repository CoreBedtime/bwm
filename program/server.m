#include <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Carbon/Carbon.h> 
#import <mach/mach.h>

#import "shared.h"

// Forward declarations
extern
bool bwm_resize_command(mach_port_t remote_port, 
                        uint32_t wid, 
                        CGFloat x, CGFloat y, 
                        CGFloat width, CGFloat height, 
                        int animate,
                        bool shadow,
                        bool button_position,
                        bool title_or_icon);

extern NSArray<NSDictionary *> *FilteredWindowList(unsigned long long current_sapce);
NSArray * LoadKeyBindings();
extern bool LoadVisualSettings();

// Types
typedef NS_ENUM(NSInteger, TilingMode) {
    TilingModeHorizontal,
    TilingModeVertical,
    TilingModeMasterStack
};

// Globals
TilingMode gCurrentTilingMode = TilingModeHorizontal;
CFMachPortRef gEventTap = NULL;
CFRunLoopSourceRef gRunLoopSource = NULL;
NSArray<NSValue *> *gKeyBindings = nil;
int gConnection = 0;
CGFloat gMasterPaneRatio = 0.6;
int gWindowShift = 0;

int gAnimationStyle = 2; 
CGFloat gWindowGap = 50.0;
bool gDisableShadows = true;
bool gTitleOrIcon = false;
bool gButtonPos = false;


NSDictionary<NSString *, NSNumber *> *GetKeycodeMap() {
    static NSDictionary<NSString *, NSNumber *> *map = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        map = @{
            @"a": @(kVK_ANSI_A), @"b": @(kVK_ANSI_B), @"c": @(kVK_ANSI_C),
            @"d": @(kVK_ANSI_D), @"e": @(kVK_ANSI_E), @"f": @(kVK_ANSI_F),
            @"g": @(kVK_ANSI_G), @"h": @(kVK_ANSI_H), @"i": @(kVK_ANSI_I),
            @"j": @(kVK_ANSI_J), @"k": @(kVK_ANSI_K), @"l": @(kVK_ANSI_L),
            @"m": @(kVK_ANSI_M), @"n": @(kVK_ANSI_N), @"o": @(kVK_ANSI_O),
            @"p": @(kVK_ANSI_P), @"q": @(kVK_ANSI_Q), @"r": @(kVK_ANSI_R),
            @"s": @(kVK_ANSI_S), @"t": @(kVK_ANSI_T), @"u": @(kVK_ANSI_U),
            @"v": @(kVK_ANSI_V), @"w": @(kVK_ANSI_W), @"x": @(kVK_ANSI_X),
            @"y": @(kVK_ANSI_Y), @"z": @(kVK_ANSI_Z),
            @"0": @(kVK_ANSI_0), @"1": @(kVK_ANSI_1), @"2": @(kVK_ANSI_2),
            @"3": @(kVK_ANSI_3), @"4": @(kVK_ANSI_4), @"5": @(kVK_ANSI_5),
            @"6": @(kVK_ANSI_6), @"7": @(kVK_ANSI_7), @"8": @(kVK_ANSI_8),
            @"9": @(kVK_ANSI_9),
            @"`": @(kVK_ANSI_Grave), @"-": @(kVK_ANSI_Minus), @"=": @(kVK_ANSI_Equal),
            @"[": @(kVK_ANSI_LeftBracket), @"]": @(kVK_ANSI_RightBracket),
            @"\\": @(kVK_ANSI_Backslash), @";": @(kVK_ANSI_Semicolon),
            @"'": @(kVK_ANSI_Quote), @",": @(kVK_ANSI_Comma), @".": @(kVK_ANSI_Period),
            @"/": @(kVK_ANSI_Slash),
            // Add other keys if needed (e.g., Space, Tab, Enter)
            @"space": @(kVK_Space),
            @"tab": @(kVK_Tab),
            @"enter": @(kVK_Return), // Or kVK_ANSI_KeypadEnter
            @"escape": @(kVK_Escape),
        };
    });
    return map;
}

int ApplyTiling() {
    @autoreleasepool {
        NSArray<NSScreen *> *allScreens = [NSScreen screens];

        if (!allScreens || [allScreens count] == 0) {
            NSLog(@"[!] Error: Could not get screen information or no screens found.");
            return 1;
        }

        for (NSScreen *screen in allScreens) {
            CGPoint pointOnScreen = screen.visibleFrame.origin;
            NSLog(@"[+] Processing screen: %@ (using point: %@)", [screen localizedName] ?: @"Unknown Screen", NSStringFromPoint(pointOnScreen));

            NSArray<NSDictionary *> *tileableWindows = FilteredWindowList((unsigned long long)[screen _currentSpace]);

            if (!tileableWindows) {
                NSLog(@"[!] Warning: FilteredWindowListAtPoint returned nil for screen %@. Skipping.", [screen localizedName] ?: @"Unknown Screen");
                continue;
            }

            CFIndex tileableWindowCount = [tileableWindows count];
            if (tileableWindowCount == 0) {
                NSLog(@"[+] No tileable windows found on screen: %@", [screen localizedName] ?: @"Unknown Screen");
                continue;
            }

            NSLog(@"[+] Found %ld tileable window(s) on screen: %@", tileableWindowCount, [screen localizedName] ?: @"Unknown Screen");

            NSRect screenFrame = NSInsetRect([screen visibleFrame], gWindowGap, gWindowGap);

            CGFloat totalWidth = MAX(0, screenFrame.size.width);
            CGFloat totalHeight = MAX(0, screenFrame.size.height);
            CGFloat startX = screenFrame.origin.x;
            CGFloat startY = screenFrame.origin.y;

            for (CFIndex i = 0; i < tileableWindowCount; ++i) {
                NSDictionary *tileInfo = tileableWindows[i];
                pid_t pid = [tileInfo[@"pid"] intValue];
                uint32_t window_number = [tileInfo[@"wid"] unsignedIntValue];

                NSString *expectedPortName = [NSString stringWithFormat:@"com.bwmport.%d", pid];
                mach_port_t nativePort = MACH_PORT_NULL;
                NSPort *remoteServicePort = [[NSMachBootstrapServer sharedInstance] portForName:expectedPortName];

                if (remoteServicePort && [remoteServicePort isKindOfClass:[NSMachPort class]]) {
                    nativePort = [(NSMachPort *)remoteServicePort machPort];
                }

                if (nativePort == MACH_PORT_NULL || nativePort == MACH_PORT_DEAD) {
                    NSLog(@"[!] Warning: Could not find or Mach port for PID %@ (WID %u) on screen %@ is invalid/dead using name '%@'. Skipping.", @(pid), window_number, [screen localizedName] ?: @"Unknown Screen", expectedPortName);
                    continue;
                }

                CGFloat currentX = startX;
                CGFloat currentY = startY;
                CGFloat currentWidth = totalWidth;
                CGFloat currentHeight = totalHeight;

                CGFloat totalHorizontalGap = (tileableWindowCount > 1) ? (tileableWindowCount - 1) * gWindowGap : 0;
                CGFloat totalVerticalGap = (tileableWindowCount > 1) ? (tileableWindowCount - 1) * gWindowGap : 0;

                switch (gCurrentTilingMode) {
                    case TilingModeVertical: {
                        currentWidth = totalWidth;
                        CGFloat availableHeight = totalHeight - totalVerticalGap;
                        currentHeight = (tileableWindowCount > 0) ? (availableHeight / tileableWindowCount) : 0;
                        currentY = startY + (i * (currentHeight + gWindowGap));
                        break;
                    }

                    case TilingModeMasterStack: {
                        if (tileableWindowCount == 1) {
                            currentX = startX;
                            currentY = startY;
                            currentWidth = totalWidth;
                            currentHeight = totalHeight;
                        } else {
                            CGFloat masterStackGap = gWindowGap;
                            CGFloat effectiveWidth = totalWidth - masterStackGap;
                            CGFloat masterWidth = effectiveWidth * gMasterPaneRatio;
                            CGFloat stackWidth = effectiveWidth - masterWidth;

                            CFIndex stackWindowCount = tileableWindowCount - 1;
                            CGFloat totalStackInternalGap = (stackWindowCount > 1) ? (stackWindowCount - 1) * gWindowGap : 0;
                            CGFloat availableStackHeight = totalHeight - totalStackInternalGap;
                            CGFloat stackHeight = (stackWindowCount > 0) ? (availableStackHeight / stackWindowCount) : 0;

                            if (i == 0) {
                                currentX = startX;
                                currentY = startY;
                                currentWidth = masterWidth;
                                currentHeight = totalHeight;
                            } else {
                                CFIndex stackIndex = i - 1;
                                currentX = startX + masterWidth + masterStackGap;
                                currentY = startY + (stackIndex * (stackHeight + gWindowGap));
                                currentWidth = stackWidth;
                                currentHeight = stackHeight;
                            }
                        }
                        break;
                    }

                    case TilingModeHorizontal:
                    default: {
                        currentHeight = totalHeight;
                        CGFloat availableWidth = totalWidth - totalHorizontalGap;
                        currentWidth = (tileableWindowCount > 0) ? (availableWidth / tileableWindowCount) : 0;
                        currentX = startX + (i * (currentWidth + gWindowGap));
                        break;
                    }
                }

                currentWidth = MAX(0, currentWidth);
                currentHeight = MAX(0, currentHeight);

                bwm_resize_command(
                    nativePort,
                    window_number,
                    currentX, currentY,
                    currentWidth, currentHeight,
                    gAnimationStyle, // animate -- add config
                    gDisableShadows,
                    gButtonPos,
                    gTitleOrIcon);
            }
        }
    }
    return 0;
}

void PerformActionString(NSString * action, bool * modeChanged, TilingMode * targetMode) {
    if ([action isEqualToString:@"reload"]) {
        // Get the path to the current executable
        NSString *executablePath = [[NSBundle mainBundle] executablePath];
        const char *path = [executablePath fileSystemRepresentation];

        // Get current arguments
        int argc = [[NSProcessInfo processInfo] arguments].count;
        NSArray<NSString *> *args = [[NSProcessInfo processInfo] arguments];
        
        // Build argv for execv
        char **argv = calloc(argc + 1, sizeof(char *));
        for (int i = 0; i < argc; i++) {
            argv[i] = strdup([args[i] UTF8String]);
        }
        argv[argc] = NULL;

        // Execute the same binary with the same arguments
        execv(path, argv); 
        perror("execv");
        exit(EXIT_FAILURE);
        
    } else if ([action isEqualToString:@"set_horizontal"]) {
        if (gCurrentTilingMode != TilingModeHorizontal) {
            *targetMode = TilingModeHorizontal;
            *modeChanged = true;
        }
        
    } else if ([action isEqualToString:@"set_vertical"]) {
        if (gCurrentTilingMode != TilingModeVertical) {
            *targetMode = TilingModeVertical;
            *modeChanged = true;
        }
        
    } else if ([action isEqualToString:@"set_master_stack"]) {
        if (gCurrentTilingMode != TilingModeMasterStack) {
            *targetMode = TilingModeMasterStack;
            *modeChanged = true;
        }

    } else if ([action isEqualToString:@"inc_master_pane"]) {
        if (gMasterPaneRatio < 0.9) gMasterPaneRatio += 0.1;

    } else if ([action isEqualToString:@"dec_master_pane"]) {
        if (gMasterPaneRatio > 0.1) gMasterPaneRatio -= 0.1;

    } else if ([action isEqualToString:@"forward_shift"]) {
        gWindowShift += 1;

    } else if ([action isEqualToString:@"backward_shift"]) {
        gWindowShift -= 1;

    } else {
        NSLog(@"Warning: executing with sh. dangerous!");

        NSString *command = action;
        if (command.length > 0) {
            NSTask *task = [[NSTask alloc] init];
            [task setLaunchPath:@"/bin/sh"];
            [task setArguments:@[@"-c", command]];

            @try {
                [task launch];
            } @catch (NSException *exception) {
                NSLog(@"Failed to execute command: %@", exception);
            }
        } else {
            NSLog(@"Empty command, nothing to execute.");
        }
    }
}

CGEventRef EventTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *userInfo) {
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        NSLog(@"[!] Event Tap Disabled (type %d). Re-enabling...", type);
        if (gEventTap != NULL) {
            CGEventTapEnable(gEventTap, true);
            NSLog(@"[+] Event Tap Re-enabled.");
        }
        return event; // Pass the event along
    }

    // We are only interested in key down events for triggering actions
    if (type != kCGEventKeyDown) {
        return event; // Pass the event along
    }

    CGKeyCode keyCode = (CGKeyCode)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
    // Get flags *without* device-dependent bits, which can vary (like caps lock state)
    CGEventFlags flags = CGEventGetFlags(event) & NSDeviceIndependentModifierFlagsMask;

    bool consumeEvent = false;

    NSLog(@"kb val %@", gKeyBindings);

    for (NSValue *bindingValue in gKeyBindings) {
        KeyBinding binding;
        [bindingValue getValue:&binding];

        if (keyCode == binding.keyCode) {
            if ((flags & binding.requiredFlags) == binding.requiredFlags) {
                NSLog(@"[+] Matched binding for action: %@", binding.action);
                TilingMode targetMode = gCurrentTilingMode; // Default to current
                bool modeChanged = false;

                // Determine action based on the binding's action string
                PerformActionString(binding.action, &modeChanged, &targetMode);

                if(modeChanged) {
                    // Dispatch the tiling action to the main thread
                    dispatch_async(dispatch_get_main_queue(), ^{
                        gCurrentTilingMode = targetMode;
                        ApplyTiling();
                    });
                }
                consumeEvent = true;
                break;
            }
        }
    } 
    
    return consumeEvent ? NULL : event;
}

bool SetupEventTap() { 
    // Define which events we want to tap (only key down needed for bindings)
    // Add kCGEventFlagsChanged if you need to react to modifier key presses alone.
    CGEventMask eventMask = CGEventMaskBit(kCGEventKeyDown); // | CGEventMaskBit(kCGEventFlagsChanged);

    // Create the event tap
    gEventTap = CGEventTapCreate(kCGHIDEventTap,           // Tap HID system events
                                 kCGHeadInsertEventTap,    // Insert before other taps
                                 kCGEventTapOptionDefault, // Default behavior (listen-only is kCGEventTapOptionListenOnly)
                                 eventMask,                // Mask of events to tap
                                 EventTapCallback,         // Callback function
                                 NULL);                    // User info pointer (not used here)

    if (!gEventTap) {
        NSLog(@"[!] FATAL: Failed to create event tap. Check permissions and system integrity.");
        // This could be due to permissions issues not caught by AXIsProcessTrusted,
        // or other system-level problems.
        return false;
    }

    // Create a run loop source for the event tap
    gRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, gEventTap, 0);
    if (!gRunLoopSource) {
        NSLog(@"[!] FATAL: Failed to create run loop source for event tap.");
        CFRelease(gEventTap);
        gEventTap = NULL;
        return false;
    }

    // Add the source to the current run loop (main thread's run loop)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), gRunLoopSource, kCFRunLoopCommonModes);

    // Enable the event tap
    CGEventTapEnable(gEventTap, true);
    NSLog(@"[+] Event Tap enabled successfully.");

    return true;
}

// --- Main Application Logic ---

extern int SLSMainConnectionID(void);

__attribute__((constructor))
static int setup() {
    @autoreleasepool {
            
        gConnection = SLSMainConnectionID();
        NSProcessInfo *processInfo = [NSProcessInfo processInfo];
        if ([[processInfo processName] isEqual:@"Dock"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSLog(@"[+] Application Starting...");

                LoadVisualSettings();
                // Load keybindings from JSON configuration file
                gKeyBindings = LoadKeyBindings();

                // Setup the event tap to listen for key presses
                if (!SetupEventTap()) {
                    NSLog(@"[!] Failed to setup event tap. Application will exit.");
                    //return; // Exit if event tap setup fails (???)
                }

                __block dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
                if (timer) {
                    NSLog(@"[+] Starting periodic re-tiling timer.");
                    dispatch_source_set_timer(timer,
                                            dispatch_time(DISPATCH_TIME_NOW, 0.01 * NSEC_PER_SEC), // Start after 5 seconds
                                            0.025 * NSEC_PER_SEC, // Repeat every 10 seconds
                                            1.0 * NSEC_PER_SEC); // Leeway of 1 second
                    dispatch_source_set_event_handler(timer, ^{
                        ApplyTiling();
                    });
                    dispatch_resume(timer);
                } else {
                    NSLog(@"[!] Warning: Failed to create periodic timer.");
                }
            });
        }
    }
    return 0;
}
