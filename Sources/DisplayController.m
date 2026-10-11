// SPDX-License-Identifier: MIT
#import "DisplayController.h"
#import "VirtualDisplayAPI.h"
#import <ColorSync/ColorSync.h>
#import <math.h>

static const uint32_t ODSVirtualVendor = 0x4F4453;
static NSString * const ODSJournalKey = @"ODSRecoveryJournal";

static NSArray<NSNumber *> *OnlineIDs(void) {
    CGDirectDisplayID ids[64]; uint32_t count = 0;
    if (CGGetOnlineDisplayList(64, ids, &count) != kCGErrorSuccess) return @[];
    NSMutableArray *result = [NSMutableArray new];
    for (uint32_t i = 0; i < count; i++) [result addObject:@(ids[i])];
    return result;
}
static NSString *DisplayUUID(CGDirectDisplayID display) {
    CFUUIDRef uuid = CGDisplayCreateUUIDFromDisplayID(display);
    if (!uuid) return nil;
    NSString *result = CFBridgingRelease(CFUUIDCreateString(NULL, uuid));
    CFRelease(uuid); return result;
}
static CGDirectDisplayID FindUUID(NSString *uuid) {
    if (!uuid.length) return kCGNullDirectDisplay;
    for (NSNumber *number in OnlineIDs())
        if ([DisplayUUID(number.unsignedIntValue) isEqualToString:uuid]) return number.unsignedIntValue;
    return kCGNullDirectDisplay;
}
static NSDictionary *ModeDictionary(CGDisplayModeRef mode) {
    if (!mode) return @{};
    return @{@"width": @(CGDisplayModeGetWidth(mode)), @"height": @(CGDisplayModeGetHeight(mode)),
             @"pixelWidth": @(CGDisplayModeGetPixelWidth(mode)), @"pixelHeight": @(CGDisplayModeGetPixelHeight(mode)),
             @"refreshRate": @(CGDisplayModeGetRefreshRate(mode))};
}
static NSArray *AllModes(CGDirectDisplayID display) {
    return CFBridgingRelease(CGDisplayCopyAllDisplayModes(display,
        (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGDisplayShowDuplicateLowResolutionModes: @YES})) ?: @[];
}
static NSArray *CaptureLayout(void) {
    NSMutableArray *snapshots = [NSMutableArray new];
    for (NSNumber *number in OnlineIDs()) {
        CGDirectDisplayID display = number.unsignedIntValue;
        if (CGDisplayVendorNumber(display) == ODSVirtualVendor) continue;
        NSString *uuid = DisplayUUID(display);
        CGDisplayModeRef mode = CGDisplayCopyDisplayMode(display);
        if (uuid && mode) {
            CGRect bounds = CGDisplayBounds(display);
            [snapshots addObject:@{@"uuid": uuid, @"mode": ModeDictionary(mode),
                @"x": @(bounds.origin.x), @"y": @(bounds.origin.y)}];
        }
        if (mode) CFRelease(mode);
    }
    return snapshots;
}

/// Restore only the selected display's mode. Other displays retain their mode;
/// origins are restored only if the original display set is still present.
static BOOL RestoreLayout(NSArray *snapshots, NSString *targetUUID) {
    if (![snapshots isKindOfClass:NSArray.class] || !targetUUID.length) return NO;
    CGDirectDisplayID target=FindUUID(targetUUID);
    CGDirectDisplayID mirrorSource=target?CGDisplayMirrorsDisplay(target):kCGNullDirectDisplay;
    // A recovery record must not take over a newer mirror group owned by another app.
    if (mirrorSource && CGDisplayVendorNumber(mirrorSource)!=ODSVirtualVendor) return NO;
    CGDisplayConfigRef cfg = NULL;
    if (CGBeginDisplayConfiguration(&cfg) != kCGErrorSuccess) return NO;
    BOOL exactSet = snapshots.count > 0;
    NSUInteger physicalCount = 0;
    for (NSNumber *n in OnlineIDs()) if (CGDisplayVendorNumber(n.unsignedIntValue) != ODSVirtualVendor) physicalCount++;
    exactSet = exactSet && physicalCount == snapshots.count;
    for (NSDictionary *snapshot in snapshots) {
        if (![snapshot isKindOfClass:NSDictionary.class] || ![snapshot[@"uuid"] isKindOfClass:NSString.class] || !FindUUID(snapshot[@"uuid"])) exactSet = NO;
    }
    BOOL ok = YES;
    for (NSDictionary *snapshot in snapshots) {
        if (![snapshot isKindOfClass:NSDictionary.class] || ![snapshot[@"uuid"] isKindOfClass:NSString.class]) { ok = NO; continue; }
        CGDirectDisplayID display = FindUUID(snapshot[@"uuid"]);
        if (!display) continue;
        if ([snapshot[@"uuid"] isEqualToString:targetUUID]) {
            CGDisplayModeRef match = NULL;
            for (id entry in AllModes(display)) {
                CGDisplayModeRef mode = (__bridge CGDisplayModeRef)entry;
                if (ODSModeMatches(CGDisplayModeGetWidth(mode), CGDisplayModeGetHeight(mode),
                    CGDisplayModeGetPixelWidth(mode), CGDisplayModeGetPixelHeight(mode),
                    CGDisplayModeGetRefreshRate(mode), snapshot[@"mode"])) { match = (CGDisplayModeRef)CFRetain(mode); break; }
            }
            if (match) {
                if (CGConfigureDisplayWithDisplayMode(cfg, display, match, NULL) != kCGErrorSuccess) ok = NO;
                CFRelease(match);
            } else ok = NO;
        }
        if (exactSet && [snapshot[@"x"] isKindOfClass:NSNumber.class] && [snapshot[@"y"] isKindOfClass:NSNumber.class])
            if (CGConfigureDisplayOrigin(cfg, display, [snapshot[@"x"] intValue], [snapshot[@"y"] intValue]) != kCGErrorSuccess) ok = NO;
    }
    return CGCompleteDisplayConfiguration(cfg, kCGConfigureForSession) == kCGErrorSuccess && ok;
}

@implementation ODSDisplay
@end

@interface ODSDisplayController ()
@property ODSState state;
@property(copy) NSString *message;
@property NSInteger confirmationSeconds;
@property(strong) ODSConfiguration *configuration;
@property(copy) NSString *targetUUID;
@property(copy) NSString *targetName;
@property(strong) CGVirtualDisplay *virtualDisplay;
@property(strong) NSArray *snapshots;
@property(strong) NSTimer *confirmationTimer;
@property(strong) NSDate *confirmationDeadline;
@property(strong) NSTimer *watchdog;
@property NSUInteger generation;
@property BOOL needsConfirmation;
- (void)checkConnection;
@end

static void DisplayReconfigured(CGDirectDisplayID display, CGDisplayChangeSummaryFlags flags, void *context) {
    if (flags & kCGDisplayBeginConfigurationFlag) return;
    __weak ODSDisplayController *controller=(__bridge ODSDisplayController *)context;
    NSUInteger generation=controller.generation;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(), ^{
        if (controller.generation==generation) [controller checkConnection];
    });
}

@implementation ODSDisplayController
- (instancetype)init {
    if ((self = [super init])) {
        _state = ODSIdle; _message = @"Choose a display and a comfortable desktop size.";
        CGDisplayRegisterReconfigurationCallback(DisplayReconfigured,(__bridge void *)self);
    }
    return self;
}
- (void)dealloc {
    CGDisplayRemoveReconfigurationCallback(DisplayReconfigured,(__bridge void *)self);
    [_confirmationTimer invalidate]; [_watchdog invalidate];
}
+ (NSArray<ODSDisplay *> *)externalDisplays {
    NSMutableDictionary *names = [NSMutableDictionary new];
    for (NSScreen *screen in NSScreen.screens) names[screen.deviceDescription[@"NSScreenNumber"]] = screen.localizedName;
    NSMutableArray *result = [NSMutableArray new];
    for (NSNumber *number in OnlineIDs()) {
        CGDirectDisplayID display = number.unsignedIntValue;
        if (CGDisplayIsBuiltin(display) || CGDisplayVendorNumber(display) == ODSVirtualVendor) continue;
        NSString *uuid = DisplayUUID(display); if (!uuid) continue;
        ODSDisplay *d = [ODSDisplay new]; d.displayID = display; d.uuid = uuid;
        d.name = names[number] ?: [NSString stringWithFormat:@"External display (%u)", display];
        d.mirrored = CGDisplayIsInMirrorSet(display);
        CGDisplayModeRef current = CGDisplayCopyDisplayMode(display);
        if (current) {
            d.refreshRate = CGDisplayModeGetRefreshRate(current);
            d.nativeWidth = CGDisplayModeGetPixelWidth(current); d.nativeHeight = CGDisplayModeGetPixelHeight(current);
            CFRelease(current);
        }
        NSUInteger largest = 0;
        for (id entry in AllModes(display)) {
            CGDisplayModeRef mode = (__bridge CGDisplayModeRef)entry;
            NSUInteger w = CGDisplayModeGetWidth(mode), h = CGDisplayModeGetHeight(mode);
            if (w == CGDisplayModeGetPixelWidth(mode) && w*h > largest && CGDisplayModeIsUsableForDesktopGUI(mode)) {
                largest = w*h; d.nativeWidth = w; d.nativeHeight = h;
            }
        }
        if (d.refreshRate < 24 || d.refreshRate > 240) d.refreshRate = 60;
        [result addObject:d];
    }
    return result;
}
- (void)changed { if (self.onChange) self.onChange(); }
- (void)fail:(NSString *)message {
    [self restore];
    self.message = [message stringByAppendingString:@" Your previous setup has been requested; check Displays if it looks different."];
    [self changed];
}
- (void)apply:(ODSConfiguration *)configuration toDisplay:(ODSDisplay *)display requireConfirmation:(BOOL)confirmation {
    if (self.state != ODSIdle) return;
    if (!FindUUID(display.uuid)) { self.message = @"That display disconnected. Refresh the display list."; [self changed]; return; }
    if (fabs(CGDisplayRotation(display.displayID))>.1) { self.message = @"Rotated displays are not supported in this preview. Use a display with Standard rotation."; [self changed]; return; }
    if (CGDisplayIsInMirrorSet(display.displayID)) { self.message = @"This display is already mirrored. Stop its current mirroring or scaling app first."; [self changed]; return; }
    for (NSString *name in @[@"CGVirtualDisplay", @"CGVirtualDisplayDescriptor", @"CGVirtualDisplaySettings", @"CGVirtualDisplayMode"])
        if (!NSClassFromString(name)) { self.message = @"This macOS version does not expose the required display API."; [self changed]; return; }
    self.generation++; self.state = ODSApplying; self.message = @"Preparing a HiDPI desktop…";
    self.configuration = configuration; self.targetUUID = display.uuid; self.targetName = display.name;
    self.needsConfirmation = confirmation; self.snapshots = CaptureLayout();
    if (!self.snapshots.count) { self.state = ODSIdle; self.message = @"Could not record the existing display setup."; [self changed]; return; }
    [NSUserDefaults.standardUserDefaults setObject:@{@"targetUUID": self.targetUUID, @"snapshots": self.snapshots} forKey:ODSJournalKey];
    [NSUserDefaults.standardUserDefaults synchronize];
    [self changed];
    CGVirtualDisplayDescriptor *desc = [[NSClassFromString(@"CGVirtualDisplayDescriptor") alloc] init];
    desc.queue = dispatch_get_main_queue(); desc.name = @"OpenDisplayScaling";
    desc.sizeInMillimeters = CGDisplayScreenSize(display.displayID);
    desc.maxPixelsWide = (unsigned int)configuration.width * 2;
    desc.maxPixelsHigh = (unsigned int)configuration.height * 2;
    desc.redPrimary = CGPointMake(.64,.33); desc.greenPrimary = CGPointMake(.30,.60);
    desc.bluePrimary = CGPointMake(.15,.06); desc.whitePoint = CGPointMake(.3127,.3290);
    desc.vendorID = ODSVirtualVendor;
    // Deterministic identity per monitor + requested mode; macOS stores its own
    // preferred mode by vendor/product. Never use transient CG display IDs here.
    uint32_t hash = 2166136261u;
    NSString *identity = [NSString stringWithFormat:@"%@/%lu/%lu/%.3f", display.uuid,
        (unsigned long)configuration.width, (unsigned long)configuration.height, configuration.refreshRate];
    NSData *data = [identity dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *bytes = data.bytes;
    for (NSUInteger i=0; i<data.length; i++) { hash ^= bytes[i]; hash *= 16777619u; }
    desc.productID = hash ?: 1; desc.serialNum = 1;
    self.virtualDisplay = [[NSClassFromString(@"CGVirtualDisplay") alloc] initWithDescriptor:desc];
    if (!self.virtualDisplay) { [self fail:@"macOS could not create the virtual display."]; return; }
    CGVirtualDisplaySettings *settings = [[NSClassFromString(@"CGVirtualDisplaySettings") alloc] init];
    settings.hiDPI = YES;
    NSMutableArray *modes = [NSMutableArray new];
    for (NSArray *size in configuration.backingModes)
        [modes addObject:[[NSClassFromString(@"CGVirtualDisplayMode") alloc] initWithWidth:[size[0] unsignedIntValue]
            height:[size[1] unsignedIntValue] refreshRate:configuration.refreshRate]];
    settings.modes = modes;
    if (![self.virtualDisplay applySettings:settings]) { [self fail:@"macOS rejected that rendering size."]; return; }
    [self waitForMode:0 generation:self.generation];
}
- (void)waitForMode:(NSUInteger)attempt generation:(NSUInteger)generation {
    if (generation != self.generation || self.state != ODSApplying) return;
    CGDirectDisplayID target = FindUUID(self.targetUUID);
    if (!target) { [self fail:@"The selected display disconnected."]; return; }
    CGDirectDisplayID virtualID = self.virtualDisplay.displayID;
    NSArray *modes = AllModes(virtualID);
    CGDisplayModeRef desired = NULL;
    for (id entry in modes) {
        CGDisplayModeRef mode = (__bridge CGDisplayModeRef)entry;
        if ([self modeIsDesired:mode]) { desired = mode; break; }
    }
    if (!desired) {
        if (attempt >= 32) { [self fail:@"HiDPI is unavailable at that size or refresh rate. Try a smaller size or 60 Hz."]; return; }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250*NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ [self waitForMode:attempt+1 generation:generation]; });
        return;
    }
    CGDisplayConfigRef cfg = NULL;
    CGError err = CGBeginDisplayConfiguration(&cfg);
    if (err == kCGErrorSuccess) err = CGConfigureDisplayWithDisplayMode(cfg, virtualID, desired, NULL);
    if (err == kCGErrorSuccess) err = CGConfigureDisplayMirrorOfDisplay(cfg, target, virtualID);
    if (err == kCGErrorSuccess) err = CGCompleteDisplayConfiguration(cfg, kCGConfigureForSession);
    else if (cfg) CGCancelDisplayConfiguration(cfg);
    if (err != kCGErrorSuccess) { [self fail:[NSString stringWithFormat:@"macOS could not apply the display setup (%d).", err]]; return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [self verify:0 generation:generation]; });
}
- (BOOL)modeIsDesired:(CGDisplayModeRef)mode {
    return mode && CGDisplayModeGetWidth(mode) == self.configuration.width
        && CGDisplayModeGetHeight(mode) == self.configuration.height
        && CGDisplayModeGetPixelWidth(mode) == self.configuration.width * 2
        && CGDisplayModeGetPixelHeight(mode) == self.configuration.height * 2
        && fabs(CGDisplayModeGetRefreshRate(mode) - self.configuration.refreshRate) < 1;
}
- (void)verify:(NSUInteger)attempt generation:(NSUInteger)generation {
    if (generation != self.generation || self.state != ODSApplying) return;
    CGDirectDisplayID target = FindUUID(self.targetUUID), virtualID = self.virtualDisplay.displayID;
    CGDisplayModeRef mode = CGDisplayCopyDisplayMode(virtualID);
    if (!mode && target) mode = CGDisplayCopyDisplayMode(target);
    BOOL correct = [self modeIsDesired:mode] && target && CGDisplayMirrorsDisplay(target) == virtualID;
    if (mode) CFRelease(mode);
    if (!correct) {
        if (attempt >= 6) { [self fail:@"The requested HiDPI mode did not take effect."]; return; }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250*NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ [self verify:attempt+1 generation:generation]; }); return;
    }
    CGDisplayConfigRef cfg = NULL;
    if (CGBeginDisplayConfiguration(&cfg) == kCGErrorSuccess) {
        for (NSDictionary *snapshot in self.snapshots) {
            CGDirectDisplayID display = [snapshot[@"uuid"] isEqualToString:self.targetUUID] ? virtualID : FindUUID(snapshot[@"uuid"]);
            if (display) CGConfigureDisplayOrigin(cfg, display, [snapshot[@"x"] intValue], [snapshot[@"y"] intValue]);
        }
        CGCompleteDisplayConfiguration(cfg, kCGConfigureForSession);
    }
    __weak typeof(self) weakSelf = self;
    self.watchdog = [NSTimer scheduledTimerWithTimeInterval:3 repeats:YES block:^(NSTimer *timer) { [weakSelf checkConnection]; }];
    [NSRunLoop.mainRunLoop addTimer:self.watchdog forMode:NSRunLoopCommonModes];
    if (self.needsConfirmation) {
        self.state = ODSConfirming; self.confirmationDeadline = [NSDate dateWithTimeIntervalSinceNow:20];
        self.confirmationSeconds = 20; self.message = @"Does this look right? Keep it, or your previous setup returns in 20 seconds.";
        self.confirmationTimer = [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) { [weakSelf tick]; }];
        [NSRunLoop.mainRunLoop addTimer:self.confirmationTimer forMode:NSRunLoopCommonModes];
    } else { self.state = ODSActive; [self activeMessage]; }
    [self changed];
}
- (void)activeMessage {
    self.message = [NSString stringWithFormat:@"Active · %lu × %lu HiDPI at %.0f Hz", (unsigned long)self.configuration.width,
        (unsigned long)self.configuration.height, self.configuration.refreshRate];
}
- (void)tick {
    self.confirmationSeconds = MAX(0, (NSInteger)ceil(self.confirmationDeadline.timeIntervalSinceNow));
    if (!self.confirmationSeconds) {
        [self restore]; self.message = [@"Change wasn’t confirmed. " stringByAppendingString:self.message];
    } else self.message = [NSString stringWithFormat:@"Keep this size? Reverting in %ld seconds.", (long)self.confirmationSeconds];
    [self changed];
}
- (void)keep {
    if (self.state != ODSConfirming) return;
    [self.confirmationTimer invalidate]; self.confirmationTimer = nil;
    self.state = ODSActive; self.confirmationSeconds = 0;
    [NSUserDefaults.standardUserDefaults setObject:@{@"uuid": self.targetUUID, @"name": self.targetName,
        @"configuration": self.configuration.dictionaryRepresentation} forKey:@"ODSLastProfile"];
    [self activeMessage]; [self changed];
}
- (void)checkConnection {
    if (self.state != ODSActive && self.state != ODSConfirming) return;
    CGDirectDisplayID target = FindUUID(self.targetUUID);
    CGDisplayModeRef mode=CGDisplayCopyDisplayMode(self.virtualDisplay.displayID);
    if (!mode && target) mode=CGDisplayCopyDisplayMode(target);
    BOOL correct=[self modeIsDesired:mode];
    if (mode) CFRelease(mode);
    if (!target || CGDisplayMirrorsDisplay(target) != self.virtualDisplay.displayID || !correct) {
        [self restore]; self.message = target ? @"Mirroring changed outside the app. Scaling stopped." : @"Display disconnected. Scaling stopped.";
        [self changed];
    }
}
- (void)restore {
    self.generation++;
    [self.confirmationTimer invalidate]; self.confirmationTimer = nil;
    [self.watchdog invalidate]; self.watchdog = nil;
    if (!self.snapshots.count && !self.virtualDisplay) { self.state = ODSIdle; return; }
    self.state = ODSRestoring; self.message = @"Restoring your previous display setup…"; [self changed];
    CGDirectDisplayID target = FindUUID(self.targetUUID);
    if (target && self.virtualDisplay && CGDisplayMirrorsDisplay(target) == self.virtualDisplay.displayID) {
        CGDisplayConfigRef cfg = NULL;
        if (CGBeginDisplayConfiguration(&cfg) == kCGErrorSuccess) {
            CGConfigureDisplayMirrorOfDisplay(cfg, target, kCGNullDirectDisplay);
            CGCompleteDisplayConfiguration(cfg, kCGConfigureForSession);
        }
    }
    self.virtualDisplay = nil;
    BOOL restored = RestoreLayout(self.snapshots, self.targetUUID);
    [NSUserDefaults.standardUserDefaults removeObjectForKey:ODSJournalKey];
    [NSUserDefaults.standardUserDefaults synchronize];
    self.snapshots = nil; self.confirmationSeconds = 0; self.state = ODSIdle;
    self.message = restored ? @"Previous display setup restored." : @"Scaling stopped. Check System Settings → Displays if the previous mode is unavailable.";
    [self changed];
}
- (BOOL)recoverPreviousSession {
    NSDictionary *journal = [NSUserDefaults.standardUserDefaults dictionaryForKey:ODSJournalKey];
    if (!journal) return NO;
    if ([journal[@"targetUUID"] isKindOfClass:NSString.class] && [journal[@"snapshots"] isKindOfClass:NSArray.class])
        RestoreLayout(journal[@"snapshots"], journal[@"targetUUID"]);
    [NSUserDefaults.standardUserDefaults removeObjectForKey:ODSJournalKey];
    self.message = @"The last session ended unexpectedly. Recovery attempted; apply your saved size manually.";
    return YES;
}
- (void)shutdown { [self restore]; }
@end
