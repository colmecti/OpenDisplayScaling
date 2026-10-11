// SPDX-License-Identifier: MIT
#import "DisplayManager.h"
#import "VirtualDisplayAPI.h"
#import "ScalingConfiguration.h"
#import <math.h>
#import <ColorSync/ColorSync.h>

@implementation ODSManagedDisplay
@end
static NSString *UUIDFor(CGDirectDisplayID display) {
    if(display==kCGNullDirectDisplay)return @"";
    CFUUIDRef value=CGDisplayCreateUUIDFromDisplayID(display);
    if (!value) return @"";
    NSString *s=CFBridgingRelease(CFUUIDCreateString(NULL,value)); CFRelease(value); return s ?: @"";
}
static NSDictionary *ModeInfo(CGDisplayModeRef m) {
    return @{@"width":@(CGDisplayModeGetWidth(m)),@"height":@(CGDisplayModeGetHeight(m)),
        @"pixelWidth":@(CGDisplayModeGetPixelWidth(m)),@"pixelHeight":@(CGDisplayModeGetPixelHeight(m)),
        @"refreshRate":@(CGDisplayModeGetRefreshRate(m))};
}
static CGDisplayModeRef FindMode(CGDirectDisplayID display, NSDictionary *info) CF_RETURNS_RETAINED {
    NSArray *modes=CFBridgingRelease(CGDisplayCopyAllDisplayModes(display,(__bridge CFDictionaryRef)@{(__bridge NSString *)kCGDisplayShowDuplicateLowResolutionModes:@YES}));
    for (id entry in modes) {
        CGDisplayModeRef m=(__bridge CGDisplayModeRef)entry;
        if (ODSModeMatches(CGDisplayModeGetWidth(m),CGDisplayModeGetHeight(m),CGDisplayModeGetPixelWidth(m),CGDisplayModeGetPixelHeight(m),CGDisplayModeGetRefreshRate(m),info)) return CGDisplayModeRetain(m);
    }
    return NULL;
}
@interface ODSDisplayManager ()
@property(copy) NSArray<ODSManagedDisplay *> *displays;
@property(copy) NSString *message;
@property NSInteger secondsRemaining;
@property BOOL pending;
@property BOOL hasLayoutChanges;
@property(strong) NSDictionary *sessionBaseline;
@property(strong) NSMutableDictionary<NSString *,CGVirtualDisplay *> *virtuals;
@property(strong) NSMutableDictionary<NSString *,NSWindow *> *overlays;
@property(strong) NSMutableDictionary<NSString *,NSDictionary *> *imageValues;
@property(strong) NSDictionary *rollback;
@property(strong) NSTimer *timer;
@property(strong) NSDate *deadline;
@property(copy) BOOL (^verifyPending)(void);
@end
@implementation ODSDisplayManager
- (instancetype)init {
    if ((self=[super init])) {
        _virtuals=[NSMutableDictionary new]; _overlays=[NSMutableDictionary new]; _imageValues=[NSMutableDictionary new];
        _message=@"Display changes stay active while this app is running."; [self refresh];
        [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(sleep:) name:NSWorkspaceWillSleepNotification object:nil];
    } return self;
}
- (void)sleep:(NSNotification *)note { if (self.pending) [self revert]; }
- (void)dealloc { [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self]; [_timer invalidate]; }
- (void)changed { if(self.onChange) self.onChange(); }
- (void)refresh {
    CGDirectDisplayID ids[64]; uint32_t count=0; CGGetOnlineDisplayList(64,ids,&count);
    NSMutableArray *result=[NSMutableArray new];
    NSMutableDictionary *names=[NSMutableDictionary new];
    for(NSScreen *screen in NSScreen.screens) names[screen.deviceDescription[@"NSScreenNumber"]]=screen.localizedName;
    for(uint32_t i=0;i<count;i++) {
        ODSManagedDisplay *d=[ODSManagedDisplay new]; d.displayID=ids[i]; d.uuid=UUIDFor(ids[i]); if(!d.uuid.length) continue;
        d.name=names[@(ids[i])] ?: (CGDisplayIsBuiltin(ids[i])?@"Built-in Display":@"External Display");
        d.builtIn=CGDisplayIsBuiltin(ids[i]); d.main=CGDisplayIsMain(ids[i]); d.mirrored=CGDisplayIsInMirrorSet(ids[i]);
        d.ownedVirtual=self.virtuals[d.uuid]!=nil; d.bounds=CGDisplayBounds(ids[i]); d.rotation=CGDisplayRotation(ids[i]);
        CGDisplayModeRef current=CGDisplayCopyDisplayMode(ids[i]);
        if(current) { d.width=CGDisplayModeGetWidth(current); d.height=CGDisplayModeGetHeight(current); d.pixelWidth=CGDisplayModeGetPixelWidth(current); d.pixelHeight=CGDisplayModeGetPixelHeight(current); d.refreshRate=CGDisplayModeGetRefreshRate(current); CGDisplayModeRelease(current); }
        CGColorSpaceRef color=CGDisplayCopyColorSpace(ids[i]); d.colorSpace=color?CFBridgingRelease(CGColorSpaceCopyName(color)):@"System default"; if(color) CGColorSpaceRelease(color);
        NSArray *modes=CFBridgingRelease(CGDisplayCopyAllDisplayModes(ids[i],(__bridge CFDictionaryRef)@{(__bridge NSString *)kCGDisplayShowDuplicateLowResolutionModes:@YES}));
        NSMutableArray *choices=[NSMutableArray new];
        for(id m in modes) if(CGDisplayModeIsUsableForDesktopGUI((__bridge CGDisplayModeRef)m)) { NSDictionary *info=ModeInfo((__bridge CGDisplayModeRef)m); if(![choices containsObject:info]) [choices addObject:info]; }
        d.modes=[choices sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){
            NSUInteger aa=[a[@"width"] unsignedIntegerValue]*[a[@"height"] unsignedIntegerValue], bb=[b[@"width"] unsignedIntegerValue]*[b[@"height"] unsignedIntegerValue];
            if(aa!=bb) return aa<bb?NSOrderedAscending:NSOrderedDescending;
            return [a[@"refreshRate"] compare:b[@"refreshRate"]];
        }]; [result addObject:d];
    }
    self.displays=result;
    for(NSString *uuid in self.overlays.allKeys) {
        NSScreen *match=nil; for(NSScreen *s in NSScreen.screens) if([UUIDFor([s.deviceDescription[@"NSScreenNumber"] unsignedIntValue]) isEqual:uuid]) match=s;
        if(match) [self.overlays[uuid] setFrame:match.frame display:YES];
        else { [self.overlays[uuid] close]; [self.overlays removeObjectForKey:uuid]; [self.imageValues removeObjectForKey:uuid]; }
    }
}
- (ODSManagedDisplay *)find:(NSString *)uuid { for(ODSManagedDisplay *d in self.displays) if([d.uuid isEqual:uuid]) return d; return nil; }
- (BOOL)allowed {
    if(self.readOnly) { self.message=@"Preview mode: display changes are disabled."; [self changed]; return NO; }
    if(self.pending) { self.message=@"Keep or revert the pending change first."; [self changed]; return NO; }
    if(self.canChangeLayout && !self.canChangeLayout()) { self.message=@"Restore the active custom HiDPI session before changing the display layout."; [self changed]; return NO; }
    [self refresh];
    // Do not modify mirror groups created by another running utility.
    for(ODSManagedDisplay *d in self.displays) if(d.mirrored && CGDisplayVendorNumber(CGDisplayMirrorsDisplay(d.displayID))==0x4F4453 && ![self find:UUIDFor(CGDisplayMirrorsDisplay(d.displayID))].ownedVirtual) {
        self.message=@"Another OpenDisplayScaling process owns this mirror session. Restore it in that app first."; [self changed]; return NO;
    }
    return YES;
}
- (NSDictionary *)captureProfile {
    [self refresh]; NSMutableArray *items=[NSMutableArray new];
    for(ODSManagedDisplay *d in self.displays) {
        NSString *uuid=d.uuid;if(!uuid.length)continue;
        CGDisplayModeRef mode=CGDisplayCopyDisplayMode(d.displayID); if(!mode) continue;
        [items addObject:@{@"uuid":uuid,@"name":d.name ?: @"Display",@"mode":ModeInfo(mode),@"x":@(d.bounds.origin.x),@"y":@(d.bounds.origin.y),@"mirror":UUIDFor(CGDisplayMirrorsDisplay(d.displayID)),@"image":[self adjustments:d]}]; CGDisplayModeRelease(mode);
    } return @{@"version":@1,@"displays":items};
}
- (BOOL)transaction:(CGError (^)(CGDisplayConfigRef))change verification:(BOOL (^)(void))verification {
    if(![self allowed]) return NO;
    self.rollback=[self captureProfile]; CGDisplayConfigRef config=NULL;
    CGError error=CGBeginDisplayConfiguration(&config);
    if(error==kCGErrorSuccess) {
        error=change(config);
        if(error==kCGErrorSuccess) error=CGCompleteDisplayConfiguration(config,kCGConfigureForAppOnly);
        else CGCancelDisplayConfiguration(config);
    }
    if(error!=kCGErrorSuccess) { self.rollback=nil; self.message=[NSString stringWithFormat:@"macOS rejected this change (error %d).",error]; [self changed]; return NO; }
    if(!self.sessionBaseline)self.sessionBaseline=self.rollback;
    self.verifyPending=verification;
    self.pending=YES; self.deadline=[NSDate dateWithTimeIntervalSinceNow:20]; self.secondsRemaining=20;
    self.message=@"Keep this display configuration? It reverts in 20 seconds.";
    __weak typeof(self) weak=self;
    self.timer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t){
        typeof(self) strong=weak; strong.secondsRemaining=MAX(0,(NSInteger)ceil(strong.deadline.timeIntervalSinceNow));
        if(!strong.secondsRemaining) [strong revert];
        else { strong.message=[NSString stringWithFormat:@"Keep this display configuration? Reverting in %ld seconds.",(long)strong.secondsRemaining]; [strong changed]; }
    }]; [self refresh]; [self changed]; return YES;
}
- (BOOL)setMode:(NSDictionary *)mode display:(ODSManagedDisplay *)display {
    if(!display || ![mode isKindOfClass:NSDictionary.class]) return NO;
    CGDisplayModeRef m=FindMode(display.displayID,mode); if(!m) { self.message=@"This mode is no longer available. Refresh the display list."; [self changed]; return NO; }
    BOOL ok=[self transaction:^CGError(CGDisplayConfigRef cfg){return CGConfigureDisplayWithDisplayMode(cfg,display.displayID,m,NULL);} verification:^BOOL{CGDisplayModeRef current=CGDisplayCopyDisplayMode(display.displayID);BOOL matches=current && ODSModeMatches(CGDisplayModeGetWidth(current),CGDisplayModeGetHeight(current),CGDisplayModeGetPixelWidth(current),CGDisplayModeGetPixelHeight(current),CGDisplayModeGetRefreshRate(current),mode);if(current)CGDisplayModeRelease(current);return matches;}]; CGDisplayModeRelease(m); return ok;
}
- (BOOL)mirror:(ODSManagedDisplay *)display source:(ODSManagedDisplay *)source {
    if(!display || display.displayID==source.displayID) return NO;
    return [self transaction:^CGError(CGDisplayConfigRef cfg){return CGConfigureDisplayMirrorOfDisplay(cfg,display.displayID,source?source.displayID:kCGNullDirectDisplay);} verification:^BOOL{return CGDisplayMirrorsDisplay(display.displayID)==(source?source.displayID:kCGNullDirectDisplay);}];
}
- (BOOL)makeMain:(ODSManagedDisplay *)display {
    if(!display || display.mirrored) { self.message=@"Use an extended display to change the main display."; [self changed]; return NO; }
    return [self transaction:^CGError(CGDisplayConfigRef cfg){
        for(ODSManagedDisplay *d in self.displays) { CGError e=CGConfigureDisplayOrigin(cfg,d.displayID,(int32_t)(d.bounds.origin.x-display.bounds.origin.x),(int32_t)(d.bounds.origin.y-display.bounds.origin.y)); if(e) return e; } return kCGErrorSuccess;
    } verification:^BOOL{return CGDisplayIsMain(display.displayID); }];
}
- (BOOL)move:(ODSManagedDisplay *)display relativeTo:(ODSManagedDisplay *)anchor direction:(NSString *)direction {
    if(!display || !anchor || display==anchor || display.main || display.mirrored || anchor.mirrored) { self.message=@"Move an extended secondary display relative to another extended display."; [self changed]; return NO; }
    CGRect b=anchor.bounds; double x=b.origin.x,y=b.origin.y;
    if([direction isEqual:@"Left"]) x-=display.bounds.size.width;
    else if([direction isEqual:@"Right"]) x+=b.size.width;
    else if([direction isEqual:@"Above"]) y-=display.bounds.size.height;
    else if([direction isEqual:@"Below"]) y+=b.size.height; else return NO;
    return [self transaction:^CGError(CGDisplayConfigRef cfg){return CGConfigureDisplayOrigin(cfg,display.displayID,(int32_t)x,(int32_t)y);} verification:^BOOL{CGRect actual=CGDisplayBounds(display.displayID);return fabs(actual.origin.x-x)<1 && fabs(actual.origin.y-y)<1;}];
}
- (BOOL)restoreSnapshot:(NSDictionary *)snapshot {
    [self refresh]; NSArray *items=snapshot[@"displays"]; if(![items isKindOfClass:NSArray.class]) return NO;
    CGDisplayConfigRef cfg=NULL; if(CGBeginDisplayConfiguration(&cfg)) return NO; BOOL ok=YES;
    for(NSDictionary *item in items) {
        ODSManagedDisplay *d=[self find:item[@"uuid"]]; if(!d) {ok=NO;continue;}
        if(CGConfigureDisplayMirrorOfDisplay(cfg,d.displayID,kCGNullDirectDisplay)) ok=NO;
        CGDisplayModeRef mode=FindMode(d.displayID,item[@"mode"]); if(mode) { if(CGConfigureDisplayWithDisplayMode(cfg,d.displayID,mode,NULL)) ok=NO; CGDisplayModeRelease(mode); } else ok=NO;
        if(CGConfigureDisplayOrigin(cfg,d.displayID,[item[@"x"] intValue],[item[@"y"] intValue])) ok=NO;
    }
    for(NSDictionary *item in items) if([item[@"mirror"] length]) {
        ODSManagedDisplay *d=[self find:item[@"uuid"]],*source=[self find:item[@"mirror"]];
        if(d && source) { if(CGConfigureDisplayMirrorOfDisplay(cfg,d.displayID,source.displayID)) ok=NO; } else ok=NO;
    }
    CGError result=CGCompleteDisplayConfiguration(cfg,kCGConfigureForAppOnly); return ok && result==kCGErrorSuccess;
}
- (void)keep { if(!self.pending) return; if(self.verifyPending && !self.verifyPending()){self.message=@"macOS has not confirmed the requested configuration. It will still revert unless the expected state appears.";[self changed];return;} self.verifyPending=nil;[self.timer invalidate]; self.timer=nil; self.pending=NO; self.hasLayoutChanges=YES; self.rollback=nil; self.message=@"Configuration kept for this app session."; [self refresh]; [self changed]; }
- (void)revert {
    if(!self.pending) return; self.verifyPending=nil;[self.timer invalidate]; self.timer=nil; self.pending=NO;
    BOOL ok=[self restoreSnapshot:self.rollback]; self.rollback=nil;
    if(!self.hasLayoutChanges && ok)self.sessionBaseline=nil;
    if(!ok)self.hasLayoutChanges=YES;
    self.message=ok?@"Previous display configuration restored.":@"Could not fully restore the previous setup. Open macOS Displays settings.";
    [self refresh]; [self changed];
}
- (BOOL)applyProfile:(NSDictionary *)profile {
    if(![profile isKindOfClass:NSDictionary.class] || ![profile[@"displays"] isKindOfClass:NSArray.class]) return NO;
    if(![self allowed]) return NO;
    NSArray *items=profile[@"displays"];
    for(NSDictionary *item in items) {
        ODSManagedDisplay *d=[self find:item[@"uuid"]]; CGDisplayModeRef mode=d?FindMode(d.displayID,item[@"mode"]):NULL;
        if(!mode) { self.message=@"This group needs a missing display or unavailable mode. Nothing changed."; [self changed]; return NO; } CGDisplayModeRelease(mode);
    }
    // Reuse the same confirmation transaction and apply all group modes atomically.
    return [self transaction:^CGError(CGDisplayConfigRef cfg){
        for(NSDictionary *item in items) {
            ODSManagedDisplay *d=[self find:item[@"uuid"]]; CGDisplayModeRef mode=FindMode(d.displayID,item[@"mode"]);
            CGError e=mode?CGConfigureDisplayWithDisplayMode(cfg,d.displayID,mode,NULL):kCGErrorFailure; if(mode) CGDisplayModeRelease(mode); if(e) return e;
            e=CGConfigureDisplayOrigin(cfg,d.displayID,[item[@"x"] intValue],[item[@"y"] intValue]); if(e) return e;
            ODSManagedDisplay *source=[self find:item[@"mirror"]]; if([item[@"mirror"] length] && !source) return kCGErrorFailure;
            e=CGConfigureDisplayMirrorOfDisplay(cfg,d.displayID,source?source.displayID:kCGNullDirectDisplay); if(e) return e;
        } return kCGErrorSuccess;
    } verification:^BOOL{
        for(NSDictionary *item in items){ODSManagedDisplay *d=[self find:item[@"uuid"]];if(!d)return NO;CGDisplayModeRef m=CGDisplayCopyDisplayMode(d.displayID);BOOL matches=m && ODSModeMatches(CGDisplayModeGetWidth(m),CGDisplayModeGetHeight(m),CGDisplayModeGetPixelWidth(m),CGDisplayModeGetPixelHeight(m),CGDisplayModeGetRefreshRate(m),item[@"mode"]);if(m)CGDisplayModeRelease(m);if(!matches)return NO;CGRect b=CGDisplayBounds(d.displayID);if(fabs(b.origin.x-[item[@"x"] doubleValue])>=1 || fabs(b.origin.y-[item[@"y"] doubleValue])>=1)return NO;if(![UUIDFor(CGDisplayMirrorsDisplay(d.displayID)) isEqual:item[@"mirror"]])return NO;}return YES;
    }];
}
- (BOOL)createVirtualWidth:(NSString *)width height:(NSString *)height name:(NSString *)name {
    if(![self allowed]) return NO; NSString *error=nil;
    ODSConfiguration *c=[ODSConfiguration configurationWithWidth:width height:height refreshRate:60 error:&error];
    if(!c || self.virtuals.count>=3) { self.message=error ?: @"A maximum of three standalone virtual screens is supported."; [self changed]; return NO; }
    if(!NSClassFromString(@"CGVirtualDisplay")) { self.message=@"Virtual displays are unavailable on this macOS version."; [self changed]; return NO; }
    CGVirtualDisplayDescriptor *desc=[CGVirtualDisplayDescriptor new]; desc.name=name.length?name:@"ODS Virtual Screen"; desc.queue=dispatch_get_main_queue();
    desc.maxPixelsWide=(unsigned)c.width*2; desc.maxPixelsHigh=(unsigned)c.height*2;
    desc.sizeInMillimeters=CGSizeMake(c.width*0.264,c.height*0.264); desc.vendorID=0x4F4453; desc.productID=2; desc.serialNum=arc4random_uniform(UINT32_MAX-1)+1;
    desc.redPrimary=CGPointMake(.64,.33); desc.greenPrimary=CGPointMake(.30,.60); desc.bluePrimary=CGPointMake(.15,.06); desc.whitePoint=CGPointMake(.3127,.329);
    CGVirtualDisplay *v=[[CGVirtualDisplay alloc] initWithDescriptor:desc]; CGVirtualDisplaySettings *settings=[CGVirtualDisplaySettings new]; settings.hiDPI=YES;
    settings.modes=@[[[CGVirtualDisplayMode alloc] initWithWidth:(unsigned)c.width*2 height:(unsigned)c.height*2 refreshRate:60]];
    if(!v || ![v applySettings:settings]) { self.message=@"macOS could not create the virtual screen."; [self changed]; return NO; }
    NSString *uuid=UUIDFor(v.displayID); if(!uuid.length) { self.message=@"Virtual screen did not register with macOS."; [self changed]; return NO; }
    self.virtuals[uuid]=v; self.message=@"Virtual screen created. It will disappear when this app quits."; [self refresh]; [self changed]; return YES;
}
- (void)removeVirtual:(ODSManagedDisplay *)display {
    if(![self allowed] || !self.virtuals[display.uuid]) return;
    // Removal is only offered for standalone extended screens.
    if(display.mirrored) { self.message=@"Stop mirroring this virtual screen before removing it."; [self changed]; return; }
    [self.virtuals removeObjectForKey:display.uuid]; self.message=@"Virtual screen removed."; [self refresh]; [self changed];
}
- (NSDictionary *)adjustments:(ODSManagedDisplay *)display { return (display.uuid ? self.imageValues[display.uuid] : nil) ?: @{@"brightness":@1,@"warmth":@0}; }
- (void)setDimming:(double)brightness warmth:(double)warmth display:(ODSManagedDisplay *)display {
    if(self.readOnly || !display || !isfinite(brightness) || !isfinite(warmth)) return;
    NSScreen *screen=nil; for(NSScreen *s in NSScreen.screens) if([s.deviceDescription[@"NSScreenNumber"] unsignedIntValue]==display.displayID) screen=s;
    if(!screen || display.mirrored) { self.message=@"Software dimming requires an extended, active display."; [self changed]; return; }
    brightness=fmax(.2,fmin(1,brightness)); warmth=fmax(0,fmin(1,warmth));
    NSWindow *overlay=self.overlays[display.uuid];
    if(!overlay) {
        overlay=[[NSWindow alloc] initWithContentRect:screen.frame styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        overlay.opaque=NO; overlay.hasShadow=NO; overlay.ignoresMouseEvents=YES; overlay.level=NSStatusWindowLevel+1; overlay.releasedWhenClosed=NO;
        overlay.collectionBehavior=NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorStationary|NSWindowCollectionBehaviorFullScreenAuxiliary;
        self.overlays[display.uuid]=overlay;
    }
    double alpha=1-brightness+warmth*.15;
    overlay.backgroundColor=[NSColor colorWithSRGBRed:warmth*.8 green:warmth*.32 blue:0 alpha:fmin(.85,alpha)];
    if(alpha<.001) [overlay orderOut:nil]; else [overlay orderFrontRegardless];
    self.imageValues[display.uuid]=@{@"brightness":@(brightness),@"warmth":@(warmth)};
}
- (void)resetAdjustments { for(NSWindow *w in self.overlays.allValues) [w close]; [self.overlays removeAllObjects]; [self.imageValues removeAllObjects]; }
- (void)restoreSessionLayout {
    if(self.readOnly) return;
    if(self.pending) [self revert];
    if(!self.sessionBaseline || !self.hasLayoutChanges) return;
    BOOL ok=[self restoreSnapshot:self.sessionBaseline];
    if(ok) {self.hasLayoutChanges=NO;self.sessionBaseline=nil;}
    self.message=ok?@"Original app-session layout restored.":@"Some displays could not be restored. Check macOS Displays settings.";[self refresh];[self changed];
}
- (BOOL)setColorProfile:(NSURL *)url display:(ODSManagedDisplay *)display {
    if(self.readOnly || !display.uuid.length) return NO;
    if(url) {
        CFErrorRef error=NULL;ColorSyncProfileRef profile=ColorSyncProfileCreateWithURL((__bridge CFURLRef)url,&error);
        if(!profile || !ColorSyncProfileVerify(profile,NULL,NULL)) {if(profile)CFRelease(profile);if(error)CFRelease(error);self.message=@"Choose a valid ICC color profile.";[self changed];return NO;}
        CFRelease(profile);if(error)CFRelease(error);
    }
    CFUUIDRef uuid=CGDisplayCreateUUIDFromDisplayID(display.displayID);if(!uuid)return NO;
    NSDictionary *info=@{(__bridge NSString *)kColorSyncDeviceDefaultProfileID:url ?: (id)NSNull.null,
        (__bridge NSString *)kColorSyncProfileUserScope:(__bridge NSString *)kCFPreferencesCurrentUser};
    BOOL ok=ColorSyncDeviceSetCustomProfiles(kColorSyncDisplayDeviceClass,uuid,(__bridge CFDictionaryRef)info);CFRelease(uuid);
    self.message=ok?@"ColorSync accepted the profile. This preference persists after quitting.":@"ColorSync could not apply this profile to the selected display.";[self refresh];[self changed];return ok;
}
- (void)shutdown { if(self.pending) [self revert]; [self resetAdjustments]; [self.virtuals removeAllObjects]; }
@end
