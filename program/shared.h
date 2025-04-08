#include <CoreGraphics/CoreGraphics.h>

#pragma once

typedef struct {
    CGKeyCode keyCode;
    CGEventFlags requiredFlags;
    NSString *action;
} KeyBinding;