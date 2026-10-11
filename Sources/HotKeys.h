// SPDX-License-Identifier: MIT
#import <Foundation/Foundation.h>
@interface ODSHotKeys : NSObject
@property(copy) void (^action)(NSUInteger action);
- (BOOL)setEnabled:(BOOL)enabled;
@end
