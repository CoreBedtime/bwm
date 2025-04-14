#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h> // For CGFloat

@interface WindowAnimationState : NSObject
@property (nonatomic, assign) CGFloat currentX;
@property (nonatomic, assign) CGFloat currentY;
@property (nonatomic, assign) CGFloat currentWidth;
@property (nonatomic, assign) CGFloat currentHeight;
@property (nonatomic, assign) CGFloat velocityX;
@property (nonatomic, assign) CGFloat velocityY;
@property (nonatomic, assign) CGFloat velocityWidth;
@property (nonatomic, assign) CGFloat velocityHeight;
@property (nonatomic, assign) NSTimeInterval lastUpdateTime; // Track time for delta calculation
@end
