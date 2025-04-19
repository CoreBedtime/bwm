// request.m
#include <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#include <sys/socket.h>
#import <sys/un.h>
#import <unistd.h>
#import <stdlib.h>
#import <errno.h>

#include "../bwm.h"

bool send_tile_command(mach_port_t port, uint32_t wid, CGFloat x, CGFloat y, CGFloat w, CGFloat h, int animate, CGFloat force) {
    struct {
        mach_msg_header_t header;
        TileCommandData data;
    } msg;

    msg.header.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0);
    msg.header.msgh_size = sizeof(msg);
    msg.header.msgh_remote_port = port;
    msg.header.msgh_local_port = MACH_PORT_NULL;
    msg.header.msgh_id = BWM_TILE_MSG_ID;

    msg.data._wid = wid;
    msg.data.x = x;
    msg.data.y = y;
    msg.data.width = w;
    msg.data.height = h;
    msg.data.animate = animate;
    msg.data.animate_force = force;

    return mach_msg(&msg.header, MACH_SEND_MSG, msg.header.msgh_size, 0, MACH_PORT_NULL, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL) == KERN_SUCCESS;
}

bool send_decoration_command(mach_port_t port, uint32_t wid, int height, uint32_t color, bool icon, bool button_position, bool shadow) {
    struct {
        mach_msg_header_t header;
        DecorationCommandData data;
    } msg;

    msg.header.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0);
    msg.header.msgh_size = sizeof(msg);
    msg.header.msgh_remote_port = port;
    msg.header.msgh_local_port = MACH_PORT_NULL;
    msg.header.msgh_id = BWM_DECORATION_MSG_ID;

    msg.data._wid = wid;
    msg.data.gsd_titlebar_height = height;
    msg.data.gsd_titlebar_col = color;
    msg.data.gsd_title_or_icon = icon;
    msg.data.gsd_button_position = button_position;
    msg.data.shadow = shadow;

    return mach_msg(&msg.header, MACH_SEND_MSG, msg.header.msgh_size, 0, MACH_PORT_NULL, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL) == KERN_SUCCESS;
}
