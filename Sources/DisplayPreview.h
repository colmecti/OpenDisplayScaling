// SPDX-License-Identifier: MIT
#import <Cocoa/Cocoa.h>
@interface ODSDisplayPreview : NSObject
- (void)showDisplay:(CGDirectDisplayID)display name:(NSString *)name;
- (void)stop;
@end
