// SPDX-License-Identifier: MIT
// Every CoreGraphics mutation is replaced here. These tests never alter a display.
#import <Cocoa/Cocoa.h>
#import <ColorSync/ColorSync.h>
#import "DisplayManager.h"
static int writes=0, completed=0, cancelled=0, assertions=0;
static CGError nextError=kCGErrorSuccess;
static CGConfigureOption lastScope;
CGError CGBeginDisplayConfiguration(CGDisplayConfigRef *config) {*config=(CGDisplayConfigRef)(uintptr_t)1;writes++;return kCGErrorSuccess;}
CGError CGConfigureDisplayWithDisplayMode(CGDisplayConfigRef config,CGDirectDisplayID display,CGDisplayModeRef mode,CFDictionaryRef options) {writes++;return nextError;}
CGError CGConfigureDisplayOrigin(CGDisplayConfigRef config,CGDirectDisplayID display,int32_t x,int32_t y) {writes++;return nextError;}
CGError CGConfigureDisplayMirrorOfDisplay(CGDisplayConfigRef config,CGDirectDisplayID display,CGDirectDisplayID source) {writes++;return nextError;}
CGError CGCompleteDisplayConfiguration(CGDisplayConfigRef config,CGConfigureOption scope) {writes++;completed++;lastScope=scope;return nextError;}
CGError CGCancelDisplayConfiguration(CGDisplayConfigRef config) {cancelled++;return kCGErrorSuccess;}
bool ColorSyncDeviceSetCustomProfiles(CFStringRef cls,CFUUIDRef uuid,CFDictionaryRef profiles) {writes++;return true;}
// Deterministic read fixtures let the suite run on headless CI runners.
CGError CGGetOnlineDisplayList(uint32_t capacity,CGDirectDisplayID *ids,uint32_t *count) {if(count)*count=MIN(capacity,2u);if(ids && capacity)ids[0]=8101;if(ids && capacity>1)ids[1]=8102;return kCGErrorSuccess;}
CFUUIDRef CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID display) {return CFUUIDCreateFromString(NULL,display==8101?CFSTR("00000000-0000-0000-0000-000000008101"):CFSTR("00000000-0000-0000-0000-000000008102"));}
boolean_t CGDisplayIsBuiltin(CGDirectDisplayID d){return d==8101;}
boolean_t CGDisplayIsMain(CGDirectDisplayID d){return d==8101;}
boolean_t CGDisplayIsInMirrorSet(CGDirectDisplayID d){return false;}
CGDirectDisplayID CGDisplayMirrorsDisplay(CGDirectDisplayID d){return 0;}
uint32_t CGDisplayVendorNumber(CGDirectDisplayID d){return 111;}
CGRect CGDisplayBounds(CGDirectDisplayID d){return CGRectMake(d==8101?0:1920,0,1920,1080);}
double CGDisplayRotation(CGDirectDisplayID d){return 0;}
CGColorSpaceRef CGDisplayCopyColorSpace(CGDirectDisplayID d){return CGColorSpaceCreateDeviceRGB();}
static NSDictionary *FixtureMode(void){return @{@"width":@1920,@"height":@1080,@"pixelWidth":@3840,@"pixelHeight":@2160,@"refreshRate":@60};}
CGDisplayModeRef CGDisplayCopyDisplayMode(CGDirectDisplayID d){return (CGDisplayModeRef)CFBridgingRetain(FixtureMode());}
CFArrayRef CGDisplayCopyAllDisplayModes(CGDirectDisplayID d,CFDictionaryRef options){return (CFArrayRef)CFBridgingRetain(@[FixtureMode()]);}
size_t CGDisplayModeGetWidth(CGDisplayModeRef m){return [((__bridge NSDictionary *)m)[@"width"] unsignedIntegerValue];}
size_t CGDisplayModeGetHeight(CGDisplayModeRef m){return [((__bridge NSDictionary *)m)[@"height"] unsignedIntegerValue];}
size_t CGDisplayModeGetPixelWidth(CGDisplayModeRef m){return [((__bridge NSDictionary *)m)[@"pixelWidth"] unsignedIntegerValue];}
size_t CGDisplayModeGetPixelHeight(CGDisplayModeRef m){return [((__bridge NSDictionary *)m)[@"pixelHeight"] unsignedIntegerValue];}
double CGDisplayModeGetRefreshRate(CGDisplayModeRef m){return [((__bridge NSDictionary *)m)[@"refreshRate"] doubleValue];}
bool CGDisplayModeIsUsableForDesktopGUI(CGDisplayModeRef m){return true;}
CGDisplayModeRef CGDisplayModeRetain(CGDisplayModeRef m){return (CGDisplayModeRef)CFRetain(m);}
void CGDisplayModeRelease(CGDisplayModeRef m){CFRelease(m);}
static void Check(BOOL condition,NSString *message) {assertions++;if(!condition){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
int main(void) {@autoreleasepool {
    ODSDisplayManager *manager=[ODSDisplayManager new];manager.readOnly=YES;
    ODSManagedDisplay *display=manager.displays.firstObject;
    Check(display!=nil,@"Read-only display inventory");
    NSDictionary *profile=[manager captureProfile];Check([profile[@"displays"] count]>0,@"Capture current layout");
    NSDictionary *mode=profile[@"displays"][0][@"mode"];
    Check(![manager setMode:mode display:display],@"Preview rejects mode change");
    Check(![manager makeMain:display],@"Preview rejects main display change");
    Check(![manager mirror:display source:nil],@"Preview rejects mirroring");
    Check(![manager createVirtualWidth:@"1920" height:@"1080" name:@"Test"],@"Preview rejects virtual creation");
    Check(![manager applyProfile:profile],@"Preview rejects group application");
    Check(![manager setColorProfile:nil display:display],@"Preview rejects ICC mutation");
    [manager restoreSessionLayout];[manager removeVirtual:display];[manager setDimming:.5 warmth:.5 display:display];
    Check(writes==0,@"No CoreGraphics or ColorSync writes in preview");
    Check([[manager adjustments:display][@"brightness"] doubleValue]==1,@"No preview dimming overlay");
    Check([[manager adjustments:nil][@"brightness"] doubleValue]==1,@"Missing display adjustments are safe");
    Check(![manager setMode:nil display:display],@"Reject missing mode");
    Check(![manager setMode:mode display:nil],@"Reject missing display");
    manager.readOnly=NO;manager.canChangeLayout=^BOOL{return NO;};
    Check(![manager setMode:mode display:display],@"HiDPI ownership blocks native change");
    Check(writes==0,@"Ownership block precedes transaction");
    manager.canChangeLayout=^BOOL{return YES;};
    nextError=kCGErrorFailure;
    Check(![manager setMode:mode display:display],@"Propagate driver rejection");
    Check(cancelled==1 && completed==0,@"Rejected configuration is cancelled, not committed");
    Check(!manager.pending && !manager.hasLayoutChanges,@"Rejected change does not enter confirmation");
    nextError=kCGErrorSuccess;
    Check([manager setMode:mode display:display],@"Successful simulated configuration starts");
    Check(lastScope==kCGConfigureForAppOnly,@"Native changes scoped to process lifetime");
    Check(manager.pending && manager.secondsRemaining==20,@"20-second confirmation starts");
    int before=writes;
    Check(![manager setMode:mode display:display],@"Block concurrent configuration");
    Check(writes==before,@"No writes for concurrent configuration");
    [manager setValue:^BOOL{return NO;} forKey:@"verifyPending"];[manager keep];Check(manager.pending,@"Keep rejects unconfirmed hardware state");
    [manager revert];Check(!manager.pending,@"Revert clears confirmation");Check(!manager.hasLayoutChanges,@"Reverted first change leaves no session override");
    Check([manager setMode:mode display:display],@"Can apply after revert");[manager keep];
    Check(!manager.pending && manager.hasLayoutChanges,@"Keep retains session override");
    [manager restoreSessionLayout];Check(!manager.hasLayoutChanges,@"Restore clears saved override");
    NSMutableDictionary *bad=[profile mutableCopy];NSMutableArray *badDisplays=[profile[@"displays"] mutableCopy];NSMutableDictionary *badDisplay=[badDisplays[0] mutableCopy];badDisplay[@"uuid"]=@"not-connected";badDisplays[0]=badDisplay;bad[@"displays"]=badDisplays;
    before=writes;Check(![manager applyProfile:bad],@"Missing group display rejected");Check(writes==before,@"Missing group display performs no partial transaction");
    Check([manager applyProfile:profile],@"Valid group uses confirmation");Check(manager.pending,@"Group change is pending");[manager revert];
    // Exercise the actual timer path with a shortened deadline, no wall-clock 20s wait.
    Check([manager setMode:mode display:display],@"Timer trial starts");[manager setValue:[NSDate dateWithTimeIntervalSinceNow:-1] forKey:@"deadline"];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.2]];
    Check(!manager.pending,@"Expired trial rolls back through timer");
    Check(!manager.hasLayoutChanges,@"Expired trial clears baseline");
    [manager shutdown];printf("Passed %d display-manager assertions (CoreGraphics writes mocked).\n",assertions);
}return 0;}
