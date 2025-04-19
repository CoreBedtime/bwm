#include <CoreFoundation/CoreFoundation.h>
#include <Foundation/Foundation.h>

#pragma once
// Message IDs
const mach_msg_id_t BWM_TILE_MSG_ID = 1001;
const mach_msg_id_t BWM_DECORATION_MSG_ID = 1002;

enum AnimationType { AnimationNone, AnimationNormal, AnimationBounce };

typedef struct {
    uint32_t _wid;
    CGFloat x, y;
    CGFloat width, height;
    int animate;
    CGFloat animate_force;
} TileCommandData;

typedef struct {
    uint32_t _wid;
    int gsd_titlebar_height;
    uint32_t gsd_titlebar_col;
    bool gsd_title_or_icon;
    bool gsd_button_position;
    bool shadow;
} DecorationCommandData;
