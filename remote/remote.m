#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#include <stdbool.h>
#import <mach/mach.h> 
#import <AppKit/AppKit.h>
#import <objc/runtime.h> // For associated objects

#import "../bwm.h"
#import "animstate.h"

#include <stdint.h>

extern 
void MakeTitlebar(
    NSWindow **outWindow,
    NSWindow *mainWindow,
    bool button_position,
    bool title_or_icon,
    int height,
    NSImage * _Nullable backgroundImage
);

extern
NSImage *CreateColorSwatchFromARGB(uint32_t argb);

void *WindowTitlebarKey = &WindowTitlebarKey;
static void *WindowAnimationStateKey = &WindowAnimationStateKey;

const CGFloat kSpringFriction = 15.0; // How much damping (higher = less bounce)
const CGFloat kStopThreshold = 0.1;  // If speed and distance are below this, snap to target

// Helper function for spring physics update
static void updateSpring(CGFloat *currentValue, CGFloat *velocity, CGFloat targetValue, CGFloat tension, CGFloat friction, CGFloat deltaTime) {
    if (deltaTime <= 0 || deltaTime > 0.1) { // Prevent huge jumps if deltaTime is weird
        deltaTime = 1.0 / 60.0; // Assume 60fps if deltaTime is invalid
    }

    CGFloat displacement = targetValue - *currentValue;
    CGFloat springForce = tension * displacement;
    CGFloat dampingForce = friction * (*velocity);
    CGFloat acceleration = springForce - dampingForce; // Assume mass = 1

    *velocity = *velocity + acceleration * deltaTime;
    *currentValue = *currentValue + (*velocity) * deltaTime;
 
    if (fabs(*velocity) < kStopThreshold && fabs(targetValue - *currentValue) < kStopThreshold) {
        *velocity = 0.0;
        *currentValue = targetValue;
    }
}


float lerp(float a, float b, float t) {
    return a + t * (b - a);
}

@interface ResizePortDelegate : NSObject <NSMachPortDelegate>
@end

@implementation ResizePortDelegate

- (void)handleMachMessage:(void *)msg {
    mach_msg_header_t *msg_header = (mach_msg_header_t *)msg;
    NSLog(@"[!] Received Mach message with ID: %d, size: %u", msg_header->msgh_id, msg_header->msgh_size);

    switch (msg_header->msgh_id) {
        case BWM_TILE_MSG_ID: {
            size_t expectedSize = sizeof(mach_msg_header_t) + sizeof(TileCommandData);
            if (msg_header->msgh_size >= expectedSize) {
                TileCommandData *data = (TileCommandData *)((uint8_t *)msg_header + sizeof(mach_msg_header_t));
                uint32_t windowid = data->_wid;

                CGFloat newx = data->x;
                CGFloat newy = data->y;
                CGFloat newWidth = data->width;
                CGFloat newHeight = data->height;
                int animate = data->animate;
                CGFloat force = data->animate_force;

                dispatch_async(dispatch_get_main_queue(), ^{
                    NSWindow *mainWindow = [[NSApplication sharedApplication] windowWithWindowNumber:windowid];
                    if (!mainWindow || ([mainWindow styleMask] & NSWindowStyleMaskFullScreen)) return;

                    NSRect targetFrame = NSMakeRect(newx, newy, newWidth, newHeight);

                    switch (animate) {
                        case AnimationNone:
                            objc_setAssociatedObject(mainWindow, WindowAnimationStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                            [mainWindow setFrame:targetFrame display:NO animate:NO];
                            break;

                        case AnimationNormal:
                            [mainWindow setFrame:NSMakeRect(
                                lerp(mainWindow.frame.origin.x, newx, 0.3),
                                lerp(mainWindow.frame.origin.y, newy, 0.3),
                                lerp(mainWindow.frame.size.width, newWidth, 0.3),
                                lerp(mainWindow.frame.size.height, newHeight, 0.3)) display:YES animate:NO];
                            objc_setAssociatedObject(mainWindow, WindowAnimationStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                            break;

                        case AnimationBounce: { 
                            WindowAnimationState *state = objc_getAssociatedObject(mainWindow, WindowAnimationStateKey);
                            if (!state) {
                                state = [[WindowAnimationState alloc] init];
                                NSRect currentFrame = mainWindow.frame;
                                state.currentX = currentFrame.origin.x;
                                state.currentY = currentFrame.origin.y;
                                state.currentWidth = currentFrame.size.width;
                                state.currentHeight = currentFrame.size.height;
                                objc_setAssociatedObject(mainWindow, WindowAnimationStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                                NSLog(@"[!] Initialized bounce state for window ID %u", windowid);
                            }

                            NSTimeInterval currentTime = [NSDate timeIntervalSinceReferenceDate];
                            NSTimeInterval deltaTime = (state.lastUpdateTime > 0) ? (currentTime - state.lastUpdateTime) : (1.0 / 60.0);
                            state.lastUpdateTime = currentTime;

                            CGFloat localCurrentX = state.currentX;
                            CGFloat localVelocityX = state.velocityX;
                            updateSpring(&localCurrentX, &localVelocityX, newx, force, kSpringFriction, deltaTime);
                            state.currentX = localCurrentX;
                            state.velocityX = localVelocityX;

                            CGFloat localCurrentY = state.currentY;
                            CGFloat localVelocityY = state.velocityY;
                            updateSpring(&localCurrentY, &localVelocityY, newy, force, kSpringFriction, deltaTime);
                            state.currentY = localCurrentY;
                            state.velocityY = localVelocityY;

                            CGFloat localCurrentWidth = state.currentWidth;
                            CGFloat localVelocityWidth = state.velocityWidth;
                            updateSpring(&localCurrentWidth, &localVelocityWidth, newWidth, force, kSpringFriction, deltaTime);
                            state.currentWidth = localCurrentWidth;
                            state.velocityWidth = localVelocityWidth;

                            CGFloat localCurrentHeight = state.currentHeight;
                            CGFloat localVelocityHeight = state.velocityHeight;
                            updateSpring(&localCurrentHeight, &localVelocityHeight, newHeight, force, kSpringFriction, deltaTime);
                            state.currentHeight = localCurrentHeight;
                            state.velocityHeight = localVelocityHeight;

                            if (state.currentWidth < 10.0) state.currentWidth = 10.0;
                            if (state.currentHeight < 10.0) state.currentHeight = 10.0;

                            NSRect newFrame = NSMakeRect(state.currentX, state.currentY, state.currentWidth, state.currentHeight);
                            [mainWindow setFrame:newFrame display:NO animate:NO];
                            break;
                        }

                        default:
                            objc_setAssociatedObject(mainWindow, WindowAnimationStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                            [mainWindow setFrame:targetFrame display:NO animate:NO];
                            break;
                    }
                });
            }
            break;
        }

        case BWM_DECORATION_MSG_ID: {
            size_t expectedSize = sizeof(mach_msg_header_t) + sizeof(DecorationCommandData);
            if (msg_header->msgh_size >= expectedSize) {
                DecorationCommandData *in = (DecorationCommandData *)((uint8_t *)msg_header + sizeof(mach_msg_header_t));
 
                DecorationCommandData data = *in;
                dispatch_async(dispatch_get_main_queue(), ^{
                    uint32_t windowid = data._wid;
                    NSWindow *mainWindow = [[NSApplication sharedApplication] windowWithWindowNumber:windowid];
                    if (!mainWindow || ([mainWindow styleMask] & NSWindowStyleMaskFullScreen)) return;

                    NSWindow *titlebarWindow = objc_getAssociatedObject(mainWindow, WindowTitlebarKey);
                    if (!titlebarWindow) {
                        // First-time setup
                        MakeTitlebar(&titlebarWindow, mainWindow,
                                    data.gsd_button_position,
                                    data.gsd_title_or_icon,
                                    data.gsd_titlebar_height,
                                    CreateColorSwatchFromARGB(data.gsd_titlebar_col));

                        objc_setAssociatedObject(mainWindow, WindowTitlebarKey, titlebarWindow, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    } else {
                        // Update existing titlebar frame and background
                        NSRect mainFrame = mainWindow.frame;
                        NSRect titlebarFrame = NSMakeRect(
                            mainFrame.origin.x,
                            NSMaxY(mainFrame),
                            mainFrame.size.width,
                            data.gsd_titlebar_height
                        );
                        [titlebarWindow setFrame:titlebarFrame display:YES]; 
                    }

                    [mainWindow setHasShadow:data.shadow];

                    NSButton *closeButton = [mainWindow standardWindowButton:NSWindowCloseButton];
                    NSButton *minimizeButton = [mainWindow standardWindowButton:NSWindowMiniaturizeButton];
                    NSButton *zoomButton = [mainWindow standardWindowButton:NSWindowZoomButton];
                    if (closeButton) [closeButton setHidden:YES];
                    if (minimizeButton) [minimizeButton setHidden:YES];
                    if (zoomButton) [zoomButton setHidden:YES];
                });

            }
            break;
        }

        default:
            NSLog(@"[!] Warning: Received message with unhandled ID: %d", msg_header->msgh_id);
            break;
    }
}

@end

static NSMachPort *g_listenPort = nil;
static ResizePortDelegate *g_portDelegate = nil;
NSString * bsName = NULL;

__attribute__((constructor))
static void setup() {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSProcessInfo *processInfo = [NSProcessInfo processInfo];
        pid_t pid = [processInfo processIdentifier];
        bsName = [@"com.bwmport." stringByAppendingString:@(pid).stringValue];

        if ([[processInfo processName] isEqual:@"Dock"]) { 
            return;
        }

        g_portDelegate = [[ResizePortDelegate alloc] init];
        if (!g_portDelegate) {
            NSLog(@"[!] Error: Failed to create port delegate.");
            return;
        }

        g_listenPort = (NSMachPort *)[NSMachPort port];
        if (!g_listenPort) {
            NSLog(@"[!] Error: Failed to create NSMachPort.");
            g_portDelegate = nil;
            return;
        }

        NSPortNameServer *nameServer = [NSMachBootstrapServer sharedInstance];
        if (![nameServer registerPort:g_listenPort name:bsName]) {
            NSLog(@"[!] Error: Failed to register port with name: %@. Another instance running?", bsName);
            g_listenPort = nil;
            g_portDelegate = nil;
            return;
        } else {
            NSLog(@"[!] Successfully registered port with name: %@", bsName);
        }

        [g_listenPort setDelegate:g_portDelegate];
        [[NSRunLoop mainRunLoop] addPort:g_listenPort forMode:NSDefaultRunLoopMode];
        NSLog(@"[!] MachPort listener setup complete. Waiting for commands on port %@.", bsName);
    });
}

__attribute__((destructor))
static void teardown() {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_listenPort) {
            if (bsName) {
                [[NSRunLoop mainRunLoop] removePort:g_listenPort forMode:NSDefaultRunLoopMode]; 
                [[NSMachBootstrapServer sharedInstance] removePortForName:bsName];
                [g_listenPort invalidate];
                g_listenPort = nil;
            }
        }
        if (g_portDelegate) {
            g_portDelegate = nil;
        }
        NSLog(@"[!] MachPort IPC teardown complete.");
    });
}
