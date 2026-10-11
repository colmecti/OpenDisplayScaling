// SPDX-License-Identifier: MIT
#import <Cocoa/Cocoa.h>
#import "ScalingConfiguration.h"

typedef NS_ENUM(NSInteger, ODSState) { ODSIdle, ODSApplying, ODSConfirming, ODSActive, ODSRestoring };

@interface ODSDisplay : NSObject
@property CGDirectDisplayID displayID;
@property(copy) NSString *uuid;
@property(copy) NSString *name;
@property NSUInteger nativeWidth, nativeHeight;
@property double refreshRate;
@property BOOL mirrored;
@end

@interface ODSDisplayController : NSObject
@property(readonly) ODSState state;
@property(readonly, copy) NSString *message;
@property(readonly) NSInteger confirmationSeconds;
@property(readonly, strong) ODSConfiguration *configuration;
@property(readonly, copy) NSString *targetUUID;
@property(copy) void (^onChange)(void);
+ (NSArray<ODSDisplay *> *)externalDisplays;
- (void)apply:(ODSConfiguration *)configuration toDisplay:(ODSDisplay *)display requireConfirmation:(BOOL)confirmation;
- (void)keep;
- (void)restore;
/// Returns YES when a previous process left an active-session recovery record.
- (BOOL)recoverPreviousSession;
- (void)shutdown;
@end
