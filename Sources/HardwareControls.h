// SPDX-License-Identifier: MIT
#import "DisplayManager.h"
@interface ODSHardwareControls : NSObject
@property BOOL readOnly;
- (void)read:(NSString *)feature display:(ODSManagedDisplay *)display completion:(void (^)(NSNumber *value, NSNumber *maximum, NSString *error))completion;
- (void)write:(NSString *)feature value:(NSInteger)value maximum:(NSInteger)maximum display:(ODSManagedDisplay *)display completion:(void (^)(NSString *message))completion;
@end
