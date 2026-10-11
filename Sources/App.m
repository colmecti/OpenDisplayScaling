// SPDX-License-Identifier: MIT
#import <Cocoa/Cocoa.h>
#import <ServiceManagement/ServiceManagement.h>
#import "DisplayController.h"
#import <signal.h>

static NSTextField *Label(NSString *text, CGFloat size, NSFontWeight weight) {
    NSTextField *view = [NSTextField wrappingLabelWithString:text];
    view.font = [NSFont systemFontOfSize:size weight:weight];
    view.selectable = NO;
    return view;
}
static NSStackView *Stack(NSArray<NSView *> *views, NSUserInterfaceLayoutOrientation direction, CGFloat spacing) {
    NSStackView *stack = [NSStackView stackViewWithViews:views];
    stack.orientation = direction; stack.spacing = spacing;
    stack.alignment = direction == NSUserInterfaceLayoutOrientationVertical ? NSLayoutAttributeLeading : NSLayoutAttributeCenterY;
    return stack;
}
static NSButton *Button(NSString *title, id target, SEL action) {
    return [NSButton buttonWithTitle:title target:target action:action];
}

@interface ODSApp : NSObject <NSApplicationDelegate, NSWindowDelegate, NSTextFieldDelegate, NSMenuDelegate>
@property(strong) NSWindow *window;
@property(strong) NSStatusItem *statusItem;
@property(strong) NSMenuItem *statusLabel, *loginMenu;
@property(strong) ODSDisplayController *controller;
@property(strong) NSArray<ODSDisplay *> *displays;
@property(strong) NSPopUpButton *displayPicker, *presets, *refreshPicker;
@property(strong) NSTextField *widthField, *heightField, *preview, *statusText, *displayDescription;
@property(strong) NSButton *applyButton, *keepButton, *restoreButton, *rescanButton, *proportions, *loginBox, *reapplyBox, *loginSettings;
@property BOOL editingFields, autoAttempted, recovered;
@property ODSState previousControllerState;
@property(strong) NSTimer *discoveryTimer;
@end

@implementation ODSApp
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    // LaunchServices normally enforces this. Also protect direct binary launches.
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
    for (NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleID]) {
        if (app.processIdentifier != NSProcessInfo.processInfo.processIdentifier) {
            [app activateWithOptions:NSApplicationActivateIgnoringOtherApps];
            [NSApp terminate:nil]; return;
        }
    }
    self.controller = [ODSDisplayController new];
    self.recovered = [self.controller recoverPreviousSession];
    [self createMainMenu]; [self createMenu]; [self createWindow]; [self refreshDisplays:nil];
    __weak typeof(self) weakSelf = self;
    self.controller.onChange = ^{ [weakSelf updateUI]; };
    [self updateUI];
    // A login launch stays in the menu bar when automatic reapply is enabled.
    if (![NSUserDefaults.standardUserDefaults boolForKey:@"ODSReapplyOnLaunch"] || self.recovered) [self showWindow:nil];
    [self tryAutomaticApply];
    self.discoveryTimer = [NSTimer scheduledTimerWithTimeInterval:5 repeats:YES block:^(NSTimer *timer) {
        [weakSelf updateLoginState]; [weakSelf tryAutomaticApply];
    }];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(willSleep:) name:NSWorkspaceWillSleepNotification object:nil];
}
- (void)createMainMenu {
    NSMenu *bar=[NSMenu new];
    NSMenuItem *application=[NSMenuItem new]; NSMenu *appMenu=[NSMenu new]; application.submenu=appMenu; [bar addItem:application];
    [appMenu addItemWithTitle:@"About OpenDisplayScaling" action:@selector(about:) keyEquivalent:@""].target=self;
    [appMenu addItem:NSMenuItem.separatorItem];
    [appMenu addItemWithTitle:@"Hide OpenDisplayScaling" action:@selector(hide:) keyEquivalent:@"h"];
    [appMenu addItemWithTitle:@"Quit OpenDisplayScaling" action:@selector(terminate:) keyEquivalent:@"q"];
    NSMenuItem *edit=[NSMenuItem new]; edit.title=@"Edit"; NSMenu *editMenu=[[NSMenu alloc] initWithTitle:@"Edit"]; edit.submenu=editMenu; [bar addItem:edit];
    [editMenu addItemWithTitle:@"Undo" action:NSSelectorFromString(@"undo:") keyEquivalent:@"z"];
    [editMenu addItemWithTitle:@"Redo" action:NSSelectorFromString(@"redo:") keyEquivalent:@"Z"];
    [editMenu addItem:NSMenuItem.separatorItem];
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    NSMenuItem *window=[NSMenuItem new]; window.title=@"Window"; NSMenu *windowMenu=[[NSMenu alloc] initWithTitle:@"Window"]; window.submenu=windowMenu; [bar addItem:window];
    [windowMenu addItemWithTitle:@"Close Window" action:@selector(performClose:) keyEquivalent:@"w"];
    NSApp.mainMenu=bar;
}
- (void)createMenu {
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    self.statusItem.button.image = [NSImage imageWithSystemSymbolName:@"display" accessibilityDescription:@"OpenDisplayScaling"];
    self.statusItem.button.toolTip = @"OpenDisplayScaling";
    NSMenu *menu = [NSMenu new]; menu.delegate = self;
    self.statusLabel = [[NSMenuItem alloc] initWithTitle:@"OpenDisplayScaling" action:nil keyEquivalent:@""];
    [menu addItem:self.statusLabel]; [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *(^item)(NSString *, SEL, NSString *) = ^NSMenuItem *(NSString *name, SEL action, NSString *key) {
        NSMenuItem *i = [[NSMenuItem alloc] initWithTitle:name action:action keyEquivalent:key]; i.target=self; [menu addItem:i]; return i;
    };
    item(@"Settings…", @selector(showWindow:), @",");
    item(@"Restore original display", @selector(restore:), @"");
    self.loginMenu = item(@"Launch at login", @selector(toggleLogin:), @"");
    [menu addItem:NSMenuItem.separatorItem];
    item(@"Source & support on GitHub", @selector(openGitHub:), @"");
    item(@"About OpenDisplayScaling", @selector(about:), @"");
    [menu addItem:NSMenuItem.separatorItem];
    item(@"Quit OpenDisplayScaling", @selector(quit:), @"q");
    self.statusItem.menu = menu;
}
- (NSTextField *)dimensionField:(NSString *)value name:(NSString *)name {
    NSTextField *field = [NSTextField textFieldWithString:value];
    field.font = [NSFont monospacedDigitSystemFontOfSize:20 weight:NSFontWeightMedium];
    field.alignment = NSTextAlignmentCenter; field.delegate = self;
    field.accessibilityLabel = name;
    [field.widthAnchor constraintEqualToConstant:112].active = YES;
    return field;
}
- (void)createWindow {
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,580,655)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable
        backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"OpenDisplayScaling"; self.window.delegate=self;
    self.window.releasedWhenClosed=NO;
    [self.window center];
    NSView *content = self.window.contentView;
    NSImageView *icon = [[NSImageView alloc] init];
    icon.image = [NSImage imageNamed:NSImageNameApplicationIcon];
    [icon.widthAnchor constraintEqualToConstant:54].active=YES;
    [icon.heightAnchor constraintEqualToConstant:54].active=YES;
    NSTextField *title = Label(@"OpenDisplayScaling", 25, NSFontWeightSemibold);
    NSTextField *tagline = Label(@"Your display. A more comfortable size.", 13, NSFontWeightRegular);
    tagline.textColor = NSColor.secondaryLabelColor;
    NSStackView *header = Stack(@[icon,Stack(@[title,tagline],NSUserInterfaceLayoutOrientationVertical,4)],NSUserInterfaceLayoutOrientationHorizontal,14);
    NSTextField *badge = Label(@"FREE & OPEN SOURCE  ·  EARLY RELEASE",10,NSFontWeightSemibold);
    badge.textColor=NSColor.systemBlueColor;

    self.displayPicker = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.displayPicker.target=self; self.displayPicker.action=@selector(displayChanged:);
    self.displayPicker.accessibilityLabel=@"External display";
    [self.displayPicker.widthAnchor constraintEqualToConstant:400].active=YES;
    self.rescanButton=Button(@"Refresh",self,@selector(refreshDisplays:));
    self.displayDescription=Label(@"",11,NSFontWeightRegular); self.displayDescription.textColor=NSColor.secondaryLabelColor;
    NSStackView *displaySection=Stack(@[Label(@"Display",13,NSFontWeightSemibold),
        Stack(@[self.displayPicker,self.rescanButton],NSUserInterfaceLayoutOrientationHorizontal,8),self.displayDescription],NSUserInterfaceLayoutOrientationVertical,5);

    self.presets=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.presets addItemsWithTitles:@[@"Custom size",@"Larger text · 150%",@"Balanced · 133%",@"More space · 125%"]];
    self.presets.target=self; self.presets.action=@selector(presetChanged:);
    self.presets.accessibilityLabel=@"Size preset";
    self.widthField=[self dimensionField:@"2560" name:@"Desktop width"];
    self.heightField=[self dimensionField:@"1080" name:@"Desktop height"];
    self.proportions=[NSButton checkboxWithTitle:@"Keep display proportions" target:self action:@selector(proportionsChanged:)];
    self.proportions.state=NSControlStateValueOn;
    self.preview=Label(@"",12,NSFontWeightRegular); self.preview.textColor=NSColor.secondaryLabelColor;
    [self.preview.widthAnchor constraintEqualToConstant:510].active=YES;
    self.refreshPicker=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.refreshPicker.target=self; self.refreshPicker.action=@selector(inputChanged:);
    self.refreshPicker.accessibilityLabel=@"Rendering refresh rate";
    NSStackView *sizeSection=Stack(@[Label(@"Desktop size · looks like",13,NSFontWeightSemibold),self.presets,
        Stack(@[self.widthField,Label(@"×",18,NSFontWeightRegular),self.heightField],NSUserInterfaceLayoutOrientationHorizontal,10),
        self.proportions, self.preview,
        Stack(@[Label(@"Refresh rate",12,NSFontWeightMedium),self.refreshPicker],NSUserInterfaceLayoutOrientationHorizontal,10)],NSUserInterfaceLayoutOrientationVertical,8);

    NSBox *rule=[NSBox new]; rule.boxType=NSBoxSeparator;
    [rule.widthAnchor constraintEqualToConstant:510].active=YES;
    self.loginBox=[NSButton checkboxWithTitle:@"Launch at login" target:self action:@selector(toggleLogin:)];
    self.reapplyBox=[NSButton checkboxWithTitle:@"Apply saved size when the app opens" target:self action:@selector(toggleReapply:)];
    self.reapplyBox.state=[NSUserDefaults.standardUserDefaults boolForKey:@"ODSReapplyOnLaunch"] ? NSControlStateValueOn : NSControlStateValueOff;
    self.loginSettings=Button(@"Allow in Login Items Settings…",self,@selector(openLoginSettings:)); self.loginSettings.hidden=YES;
    NSStackView *startup=Stack(@[self.loginBox,self.reapplyBox,self.loginSettings],NSUserInterfaceLayoutOrientationVertical,6);

    self.statusText=Label(@"",12,NSFontWeightMedium); [self.statusText.widthAnchor constraintEqualToConstant:510].active=YES;
    self.applyButton=Button(@"Apply HiDPI",self,@selector(apply:)); self.applyButton.bezelColor=NSColor.systemBlueColor;
    self.keepButton=Button(@"Keep this size",self,@selector(keep:)); self.keepButton.hidden=YES;
    self.restoreButton=Button(@"Restore original",self,@selector(restore:));
    NSStackView *actions=Stack(@[self.applyButton,self.keepButton,self.restoreButton],NSUserInterfaceLayoutOrientationHorizontal,10);
    NSTextField *footer=Label(@"Stays in the menu bar. New sizes revert after 20 seconds unless you keep them.",11,NSFontWeightRegular);
    footer.textColor=NSColor.secondaryLabelColor;
    [footer.widthAnchor constraintEqualToConstant:510].active=YES;
    NSStackView *root=Stack(@[header,badge,displaySection,sizeSection,rule,startup,self.statusText,actions,footer],NSUserInterfaceLayoutOrientationVertical,16);
    root.translatesAutoresizingMaskIntoConstraints=NO; [content addSubview:root];
    [NSLayoutConstraint activateConstraints:@[[root.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:30],
        [root.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-30],
        [root.topAnchor constraintEqualToAnchor:content.topAnchor constant:24],
        [root.bottomAnchor constraintLessThanOrEqualToAnchor:content.bottomAnchor constant:-20]]];
    [content layoutSubtreeIfNeeded];
    NSSize fitting=root.fittingSize;
    [self.window setContentSize:NSMakeSize(580,MAX(655,fitting.height+48))];
}
- (ODSDisplay *)selectedDisplay {
    NSInteger index=self.displayPicker.indexOfSelectedItem;
    return index>=0 && index<(NSInteger)self.displays.count ? self.displays[index] : nil;
}
- (void)refreshDisplays:(id)sender {
    if (self.controller.state!=ODSIdle) return;
    NSString *previous=[self selectedDisplay].uuid;
    self.displays=ODSDisplayController.externalDisplays;
    [self.displayPicker removeAllItems];
    NSDictionary *saved=[NSUserDefaults.standardUserDefaults dictionaryForKey:@"ODSLastProfile"];
    NSString *preferred=previous ?: saved[@"uuid"];
    for (ODSDisplay *d in self.displays) {
        [self.displayPicker addItemWithTitle:[NSString stringWithFormat:@"%@%@",d.name,d.mirrored?@" (already mirrored)":@""]];
        if ([d.uuid isEqualToString:preferred]) [self.displayPicker selectItemAtIndex:self.displayPicker.numberOfItems-1];
    }
    if (!self.displays.count) [self.displayPicker addItemWithTitle:@"No external display connected"];
    [self displayChanged:nil];
}
- (void)displayChanged:(id)sender {
    ODSDisplay *d=[self selectedDisplay];
    self.editingFields=YES;
    [self.refreshPicker removeAllItems];
    if (d) {
        self.displayDescription.stringValue=[NSString stringWithFormat:@"Display reference size: %lu × %lu · Current refresh: %.0f Hz",(unsigned long)d.nativeWidth,(unsigned long)d.nativeHeight,d.refreshRate];
        [self.refreshPicker addItemWithTitle:[NSString stringWithFormat:@"Match display · %.0f Hz",d.refreshRate]];
        self.refreshPicker.lastItem.representedObject=@(d.refreshRate);
        for (NSNumber *rate in @[@60,@120,@144,@165,@240]) if (rate.doubleValue <= d.refreshRate+1 && fabs(rate.doubleValue-d.refreshRate)>=1) {
            [self.refreshPicker addItemWithTitle:[NSString stringWithFormat:@"%@ Hz",rate]]; self.refreshPicker.lastItem.representedObject=rate;
        }
        NSDictionary *saved=[NSUserDefaults.standardUserDefaults dictionaryForKey:@"ODSLastProfile"];
        ODSConfiguration *c=[saved[@"uuid"] isEqualToString:d.uuid] ? [ODSConfiguration fromDictionary:saved[@"configuration"]] : nil;
        if (c) {
            self.widthField.stringValue=[NSString stringWithFormat:@"%lu",(unsigned long)c.width];
            self.heightField.stringValue=[NSString stringWithFormat:@"%lu",(unsigned long)c.height];
            for (NSMenuItem *item in self.refreshPicker.itemArray) if (fabs([item.representedObject doubleValue]-c.refreshRate)<1) [self.refreshPicker selectItem:item];
            [self.presets selectItemAtIndex:0];
        } else {
            [self.presets selectItemAtIndex:2]; [self presetChanged:nil];
        }
    } else self.displayDescription.stringValue=@"Connect an external monitor, then choose Refresh.";
    self.editingFields=NO; [self updatePreview]; [self updateUI];
}
- (void)presetChanged:(id)sender {
    ODSDisplay *d=[self selectedDisplay]; NSInteger index=self.presets.indexOfSelectedItem;
    if (!d || index<1) return;
    double scale=index==1?1.5:index==2?4.0/3.0:1.25;
    NSUInteger width=(NSUInteger)llround(d.nativeWidth/scale/2.0)*2;
    NSUInteger height=(NSUInteger)llround(d.nativeHeight/scale/2.0)*2;
    self.widthField.stringValue=[NSString stringWithFormat:@"%lu",(unsigned long)width];
    self.heightField.stringValue=[NSString stringWithFormat:@"%lu",(unsigned long)height];
    self.proportions.state=NSControlStateValueOn; [self updatePreview];
}
- (void)controlTextDidChange:(NSNotification *)notification {
    if (self.editingFields) return;
    [self.presets selectItemAtIndex:0];
    ODSDisplay *d=[self selectedDisplay];
    if (self.proportions.state==NSControlStateValueOn && d.nativeWidth && d.nativeHeight) {
        self.editingFields=YES;
        if (notification.object==self.widthField && isfinite(self.widthField.doubleValue) && self.widthField.doubleValue>0 && self.widthField.doubleValue<=10000)
            self.heightField.integerValue=(NSInteger)llround(self.widthField.doubleValue*d.nativeHeight/d.nativeWidth/2.0)*2;
        else if (notification.object==self.heightField && isfinite(self.heightField.doubleValue) && self.heightField.doubleValue>0 && self.heightField.doubleValue<=10000)
            self.widthField.integerValue=(NSInteger)llround(self.heightField.doubleValue*d.nativeWidth/d.nativeHeight/2.0)*2;
        self.editingFields=NO;
    }
    [self updatePreview];
}
- (void)proportionsChanged:(id)sender {
    if (self.proportions.state==NSControlStateValueOn) [self controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:self.widthField]];
    else [self updatePreview];
}
- (void)inputChanged:(id)sender { [self updatePreview]; }
- (ODSConfiguration *)inputConfiguration:(NSString **)error {
    return [ODSConfiguration configurationWithWidth:self.widthField.stringValue height:self.heightField.stringValue
        refreshRate:[self.refreshPicker.selectedItem.representedObject doubleValue] error:error];
}
- (void)updatePreview {
    NSString *error=nil; ODSConfiguration *c=[self inputConfiguration:&error];
    if (!c) self.preview.stringValue=error ?: @"Choose a display to begin.";
    else {
        ODSDisplay *d=[self selectedDisplay];
        BOOL different=d.nativeWidth && d.nativeHeight && fabs((double)c.width/c.height / ((double)d.nativeWidth/d.nativeHeight)-1) > .02;
        self.preview.stringValue=[NSString stringWithFormat:@"Rendered at %lu × %lu for finer text. %@",
            (unsigned long)c.width*2,(unsigned long)c.height*2,different?@"Different proportions may add black bars.":@"The panel keeps its physical pixel count."];
    }
}
- (void)apply:(id)sender {
    NSString *error=nil; ODSConfiguration *c=[self inputConfiguration:&error]; ODSDisplay *d=[self selectedDisplay];
    if (!c || !d) { self.statusText.stringValue=error ?: @"Choose a connected external display."; return; }
    self.autoAttempted=YES;
    [self.controller apply:c toDisplay:d requireConfirmation:YES];
}
- (void)keep:(id)sender { [self.controller keep]; }
- (void)restore:(id)sender {
    self.autoAttempted=YES; [self.controller restore]; [self refreshDisplays:nil];
}
- (void)tryAutomaticApply {
    if (self.autoAttempted || self.recovered || self.controller.state!=ODSIdle || ![NSUserDefaults.standardUserDefaults boolForKey:@"ODSReapplyOnLaunch"]) return;
    NSDictionary *profile=[NSUserDefaults.standardUserDefaults dictionaryForKey:@"ODSLastProfile"];
    ODSConfiguration *c=[ODSConfiguration fromDictionary:profile[@"configuration"]];
    if (!c || ![profile[@"uuid"] isKindOfClass:NSString.class]) return;
    for (ODSDisplay *d in ODSDisplayController.externalDisplays) if ([d.uuid isEqualToString:profile[@"uuid"]]) {
        self.autoAttempted=YES;
        [self.controller apply:c toDisplay:d requireConfirmation:NO]; return;
    }
}
- (void)toggleReapply:(id)sender {
    [NSUserDefaults.standardUserDefaults setBool:self.reapplyBox.state==NSControlStateValueOn forKey:@"ODSReapplyOnLaunch"];
}
- (void)toggleLogin:(id)sender {
    if (![NSBundle.mainBundle.bundlePath hasPrefix:@"/Applications/"] && ![NSBundle.mainBundle.bundlePath hasPrefix:[NSHomeDirectory() stringByAppendingString:@"/Applications/"]]) {
        self.statusText.stringValue=@"Move the app into Applications, reopen it, then enable Launch at login.";
        [self updateLoginState]; [self showWindow:nil]; return;
    }
    SMAppService *service=SMAppService.mainAppService; NSError *error=nil;
    BOOL registered=service.status==SMAppServiceStatusEnabled || service.status==SMAppServiceStatusRequiresApproval;
    BOOL success=registered?[service unregisterAndReturnError:&error]:[service registerAndReturnError:&error];
    [self updateLoginState];
    if (!success) { self.statusText.stringValue=[NSString stringWithFormat:@"Login setting could not change: %@",error.localizedDescription ?: @"Unknown error"]; [self showWindow:nil]; }
    else if (service.status==SMAppServiceStatusRequiresApproval) [self showWindow:nil];
}
- (void)updateLoginState {
    SMAppServiceStatus status=SMAppService.mainAppService.status;
    NSControlStateValue checked=status==SMAppServiceStatusEnabled?NSControlStateValueOn:status==SMAppServiceStatusRequiresApproval?NSControlStateValueMixed:NSControlStateValueOff;
    self.loginBox.state=checked; self.loginMenu.state=checked;
    self.loginSettings.hidden=status!=SMAppServiceStatusRequiresApproval;
}
- (void)openLoginSettings:(id)sender { [SMAppService openSystemSettingsLoginItems]; }
- (void)updateUI {
    BOOL idle=self.controller.state==ODSIdle, confirming=self.controller.state==ODSConfirming;
    self.displayPicker.enabled=idle; self.rescanButton.enabled=idle;
    self.presets.enabled=idle; self.widthField.enabled=idle; self.heightField.enabled=idle;
    self.proportions.enabled=idle; self.refreshPicker.enabled=idle;
    self.applyButton.hidden=confirming; self.applyButton.enabled=idle && [self selectedDisplay]!=nil;
    self.keepButton.hidden=!confirming; self.keepButton.keyEquivalent=confirming?@"\r":@"";
    self.applyButton.keyEquivalent=idle?@"\r":@"";
    self.restoreButton.enabled=!idle && self.controller.state!=ODSRestoring;
    self.restoreButton.keyEquivalent=confirming?@"\033":@"";
    self.statusText.stringValue=self.controller.message;
    self.statusLabel.title=self.controller.state==ODSActive?self.controller.message:@"OpenDisplayScaling";
    self.statusItem.button.toolTip=self.controller.message;
    // Bring confirmation forward once, not on every countdown tick. Repeated
    // activation would steal focus from whatever the user is working on.
    if (confirming && self.previousControllerState!=ODSConfirming) [self showWindow:nil];
    self.previousControllerState=self.controller.state;
    [self updateLoginState];
}
- (void)menuWillOpen:(NSMenu *)menu { [self updateLoginState]; }
- (void)showWindow:(id)sender { [self.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES]; }
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag { [self showWindow:nil]; return YES; }
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return NO; }
- (void)willSleep:(NSNotification *)notification {
    // Never leave a confirmation countdown suspended through sleep.
    if (self.controller.state==ODSConfirming || self.controller.state==ODSApplying) [self restore:nil];
}
- (void)openGitHub:(id)sender { [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"https://github.com/colmecti/OpenDisplayScaling"]]; }
- (void)about:(id)sender {
    NSAlert *alert=[NSAlert new]; alert.messageText=@"OpenDisplayScaling 0.1.0";
    alert.informativeText=@"A free, MIT-licensed HiDPI scaling utility by colmecti.\n\nUses private macOS display APIs. This early release is for Apple silicon Macs running macOS 13 or later.\n\nNo analytics, accounts, or subscriptions.\n\nIncludes MIT-licensed API declarations and ideas from hidpi-mirror by Petr Baudis. See ThirdPartyNotices in the app Resources and source repository.";
    [alert runModal];
}
- (void)quit:(id)sender { [NSApp terminate:nil]; }
- (void)applicationWillTerminate:(NSNotification *)notification {
    [self.discoveryTimer invalidate]; self.controller.onChange=nil; [self.controller shutdown];
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc>1 && strcmp(argv[1],"--version")==0) { puts("OpenDisplayScaling 0.1.0"); return 0; }
        if (argc>1 && strcmp(argv[1],"--diagnostics")==0) {
            NSMutableArray *displays=[NSMutableArray new];
            for (ODSDisplay *d in ODSDisplayController.externalDisplays)
                [displays addObject:@{@"name":d.name,@"reportedWidth":@(d.nativeWidth),@"reportedHeight":@(d.nativeHeight),
                    @"refreshRate":@(d.refreshRate),@"mirrored":@(d.mirrored)}];
            NSDictionary *report=@{@"appVersion":@"0.1.0",@"macOS":NSProcessInfo.processInfo.operatingSystemVersionString,
                @"architecture":@"arm64",@"virtualDisplayAPIAvailable":@(NSClassFromString(@"CGVirtualDisplay")!=Nil),@"displays":displays};
            NSData *json=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil];
            fwrite(json.bytes,1,json.length,stdout); puts(""); return 0;
        }
        NSApplication *app=NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        ODSApp *delegate=[ODSApp new]; app.delegate=delegate;
        signal(SIGTERM,SIG_IGN); signal(SIGINT,SIG_IGN);
        dispatch_source_t term=dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL,SIGTERM,0,dispatch_get_main_queue());
        dispatch_source_t interrupt=dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL,SIGINT,0,dispatch_get_main_queue());
        dispatch_source_set_event_handler(term,^{ [NSApp terminate:nil]; });
        dispatch_source_set_event_handler(interrupt,^{ [NSApp terminate:nil]; });
        dispatch_resume(term); dispatch_resume(interrupt);
        [app run];
    }
    return 0;
}
