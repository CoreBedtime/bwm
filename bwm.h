#include <CoreFoundation/CoreFoundation.h>
#include <Foundation/Foundation.h>

#pragma once
const mach_msg_id_t BWM_RESIZE_MSG_ID = 1001; // Replace with your actual message ID

enum AnimationType {AnimationNone, AnimationNormal, AnimationBounce};

// Define the expected structure of the message data following the header
typedef struct {
    uint32_t _wid;
    int animate;
    CGFloat animate_force;
    bool shadow;
    int gsd_titlebar_height;
    uint32_t gsd_titlebar_col;
    bool gsd_title_or_icon;
    bool gsd_button_position;
    CGFloat x, y;
    CGFloat width, height;
} ResizeCommandData; // Data part of the message
