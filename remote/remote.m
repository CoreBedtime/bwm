#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#include <stdbool.h>
#import <mach/mach.h>
#import <AppKit/AppKit.h>

#import "../bwm.h"

#include <stdint.h>

float lerp(float a, float b, float t) {
    return a + t * (b - a);
}

@interface ResizePortDelegate : NSObject <NSMachPortDelegate>
@end

@implementation ResizePortDelegate

- (void)handleMachMessage:(void *)msg {
    mach_msg_header_t *msg_header = (mach_msg_header_t *)msg;
    NSLog(@"[!] Received Mach message with ID: %d, size: %u", msg_header->msgh_id, msg_header->msgh_size);

    if (msg_header->msgh_id == BWM_RESIZE_MSG_ID) {
        size_t expectedSize = sizeof(mach_msg_header_t) + sizeof(ResizeCommandData);

        if (msg_header->msgh_size >= expectedSize) {
            ResizeCommandData *data = (ResizeCommandData *)((uint8_t *)msg_header + sizeof(mach_msg_header_t));
            uint32_t windowid = data->_wid;
            int animate = data->animate;
            bool shadow = data->shadow;
            bool trafficlights = data->trafficlights;
            CGFloat newWidth = data->width;
            CGFloat newHeight = data->height;
            CGFloat newx = data->x;
            CGFloat newy = data->y;

            NSLog(@"[!] Resize command received: Width=%.2f, Height=%.2f", newWidth, newHeight);

            dispatch_async(dispatch_get_main_queue(), ^{
                NSWindow *mainWindow = [[NSApplication sharedApplication] windowWithWindowNumber:windowid];
                if (mainWindow) {
                    NSButton *closeButton = [mainWindow standardWindowButton:NSWindowCloseButton];
                    NSButton *minimizeButton = [mainWindow standardWindowButton:NSWindowMiniaturizeButton];
                    NSButton *zoomButton = [mainWindow standardWindowButton:NSWindowZoomButton];

                    [mainWindow setHasShadow:shadow];
                    [closeButton setHidden:trafficlights];
                    [minimizeButton setHidden:trafficlights];
                    [zoomButton setHidden:trafficlights];
            

                    switch (animate) {
                        case AnimationNone:
                            [mainWindow setFrame:NSMakeRect(newx, 
                                                            newy, 
                                                            newWidth, 
                                                            newHeight) display:YES animate:NO];
                            break;
                    
                        case AnimationNormal:
                            [mainWindow setFrame:NSMakeRect(lerp(mainWindow.frame.origin.x, newx, 0.2), 
                                                            lerp(mainWindow.frame.origin.y, newy, 0.2), 
                                                            lerp(mainWindow.frame.size.width, newWidth, 0.2), 
                                                            lerp(mainWindow.frame.size.height, newHeight, 0.2)) display:YES animate:NO];
                            break;
                    
                        default:
                            [mainWindow setFrame:NSMakeRect(newx, 
                                                            newy, 
                                                            newWidth, 
                                                            newHeight) display:YES animate:NO];
                            break;
                    }
                }
            });
        } else {
            NSLog(@"[!] Error: Received resize message with unexpected size: %u (expected at least %zu)", msg_header->msgh_size, expectedSize);
        }
    } else {
        NSLog(@"[!] Warning: Received message with unhandled ID: %d", msg_header->msgh_id);
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
