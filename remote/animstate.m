#import "animstate.h"

@implementation WindowAnimationState
- (instancetype)init {
    self = [super init];
    if (self) {
        // Initialize velocities to zero
        _velocityX = 0.0;
        _velocityY = 0.0;
        _velocityWidth = 0.0;
        _velocityHeight = 0.0;
        _lastUpdateTime = 0.0; // Indicate not updated yet
    }
    return self;
}
@end