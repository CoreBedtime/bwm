// request.m
#include <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#include <sys/socket.h>
#import <sys/un.h>
#import <unistd.h>
#import <stdlib.h>
#import <errno.h>

#include "../bwm.h"

bool bwm_resize_command(mach_port_t remote_port, 
                        uint32_t wid, 
                        CGFloat x, CGFloat y, 
                        CGFloat width, CGFloat height, 
                        CGFloat animate_force,
                        int animate,
                        int titlebarheight,
                        bool shadow,
                        bool button_position,
                        bool title_or_icon) {
    kern_return_t kr;
    struct {
        mach_msg_header_t header;
        ResizeCommandData data;
    } msg;

    msg.header.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0);
    msg.header.msgh_size = sizeof(msg);
    msg.header.msgh_remote_port = remote_port;
    msg.header.msgh_local_port = MACH_PORT_NULL;
    msg.header.msgh_voucher_port = MACH_PORT_NULL;
    
    msg.header.msgh_id = BWM_RESIZE_MSG_ID;

    msg.data._wid = wid;

    msg.data.animate_force = animate_force;
    msg.data.animate = animate;
    msg.data.shadow = shadow;

    msg.data.gsd_titlebar_height = titlebarheight;
    msg.data.gsd_button_position = button_position;
    msg.data.gsd_title_or_icon = title_or_icon;

    msg.data.width = width;
    msg.data.height = height;
    msg.data.x = x;
    msg.data.y = y;

    kr = mach_msg(&msg.header, MACH_SEND_MSG, msg.header.msgh_size, 0, MACH_PORT_NULL, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);

    if (kr != KERN_SUCCESS) {
        NSLog(@"[!] Error sending Mach message to port %d: %s (kern_return_t: %d)", remote_port, mach_error_string(kr), kr);
        return false;
    }
    return true;
}