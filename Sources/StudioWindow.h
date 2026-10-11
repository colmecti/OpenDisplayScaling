// SPDX-License-Identifier: MIT
#import <Cocoa/Cocoa.h>
#import "DisplayManager.h"
@interface ODSStudioWindow : NSObject
@property(readonly,strong) NSWindow *window;
@property(readonly,strong) ODSDisplayManager *manager;
@property(copy) void (^openScaling)(void);
@property(copy) void (^toggleLogin)(void);
- (instancetype)initReadOnly:(BOOL)readOnly;
- (void)show;
- (void)populateMenu:(NSMenu *)menu;
- (void)shutdown;
@end
