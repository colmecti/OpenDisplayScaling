// SPDX-License-Identifier: MIT
#import <Cocoa/Cocoa.h>

@interface ODSManagedDisplay : NSObject
@property CGDirectDisplayID displayID;
@property(copy) NSString *uuid, *name, *colorSpace;
@property BOOL builtIn, main, mirrored, ownedVirtual;
@property CGRect bounds;
@property NSUInteger width, height, pixelWidth, pixelHeight;
@property double refreshRate, rotation;
@property(copy) NSArray<NSDictionary *> *modes;
@end

@interface ODSDisplayManager : NSObject
@property BOOL readOnly;
@property(copy) BOOL (^canChangeLayout)(void);
@property(copy) void (^onChange)(void);
@property(readonly, copy) NSArray<ODSManagedDisplay *> *displays;
@property(readonly, copy) NSString *message;
@property(readonly) NSInteger secondsRemaining;
@property(readonly) BOOL pending;
@property(readonly) BOOL hasLayoutChanges;
- (void)restoreSessionLayout;
- (void)refresh;
- (BOOL)setMode:(NSDictionary *)mode display:(ODSManagedDisplay *)display;
- (BOOL)mirror:(ODSManagedDisplay *)display source:(ODSManagedDisplay *)source;
- (BOOL)makeMain:(ODSManagedDisplay *)display;
- (BOOL)move:(ODSManagedDisplay *)display relativeTo:(ODSManagedDisplay *)anchor direction:(NSString *)direction;
- (void)keep;
- (void)revert;
- (BOOL)createVirtualWidth:(NSString *)width height:(NSString *)height name:(NSString *)name;
- (void)removeVirtual:(ODSManagedDisplay *)display;
- (void)setDimming:(double)brightness warmth:(double)warmth display:(ODSManagedDisplay *)display;
- (NSDictionary *)adjustments:(ODSManagedDisplay *)display;
- (void)resetAdjustments;
- (NSDictionary *)captureProfile;
- (BOOL)applyProfile:(NSDictionary *)profile;
- (BOOL)setColorProfile:(NSURL *)url display:(ODSManagedDisplay *)display;
- (void)shutdown;
@end
