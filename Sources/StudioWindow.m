// SPDX-License-Identifier: MIT
#import "StudioWindow.h"
#import "DisplayPreview.h"
#import "HardwareControls.h"
#import "HotKeys.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <ServiceManagement/ServiceManagement.h>

static NSTextField *Text(NSString *s,CGFloat size,BOOL bold) {
    NSTextField *v=[NSTextField wrappingLabelWithString:s ?: @""]; v.font=[NSFont systemFontOfSize:size weight:bold?NSFontWeightSemibold:NSFontWeightRegular]; return v;
}
static NSStackView *Column(NSArray *items,CGFloat gap) {NSStackView *s=[NSStackView stackViewWithViews:items];s.orientation=NSUserInterfaceLayoutOrientationVertical;s.alignment=NSLayoutAttributeLeading;s.spacing=gap;return s;}
static NSStackView *Row(NSArray *items,CGFloat gap) {NSStackView *s=[NSStackView stackViewWithViews:items];s.orientation=NSUserInterfaceLayoutOrientationHorizontal;s.alignment=NSLayoutAttributeCenterY;s.spacing=gap;return s;}
static NSButton *Action(NSString *title,id target,SEL selector) {return [NSButton buttonWithTitle:title target:target action:selector];}
static NSString *ModeTitle(NSDictionary *m) {return [NSString stringWithFormat:@"%@ × %@ · %@ · %@",m[@"width"],m[@"height"],[m[@"pixelWidth"] doubleValue]>[m[@"width"] doubleValue]?@"HiDPI":@"Standard",[m[@"refreshRate"] doubleValue]>0?[NSString stringWithFormat:@"%.1f Hz",[m[@"refreshRate"] doubleValue]]:@"Variable / unspecified Hz"];}

@interface ODSStudioWindow ()
@property(strong) NSWindow *window;
@property(strong) ODSDisplayManager *manager;
@property(strong) NSView *page;
@property(strong) NSStackView *body, *nav;
@property(strong) NSTextField *status;
@property(strong) NSButton *keepButton,*revertButton;
@property(copy) NSString *section,*selectedUUID;
@property(strong) NSPopUpButton *modePicker,*anchorPicker,*directionPicker,*mirrorPicker;
@property(strong) NSSlider *brightness,*warmth;
@property(strong) ODSDisplayPreview *capture;
@property(strong) ODSHardwareControls *hardware;
@property(strong) ODSHotKeys *hotKeys;
@property(strong) NSPopUpButton *hardwareFeature;
@property(strong) NSSlider *hardwareValue;
@property(strong) NSButton *hardwareApply;
@property(strong) NSTextField *hardwareStatus;
@property(copy) NSString *hardwareUUID,*verifiedFeature;
@property NSInteger verifiedMaximum;
@property BOOL autoBrightnessBusy;
@property(strong) NSTimer *timer;
@property(strong) NSArray *fingerprint;
@property BOOL readOnly;
@end
@implementation ODSStudioWindow
- (instancetype)initReadOnly:(BOOL)readOnly {
    if((self=[super init])) {
        _readOnly=readOnly; _manager=[ODSDisplayManager new]; _manager.readOnly=readOnly; _section=@"Displays"; _capture=[ODSDisplayPreview new];_hardware=[ODSHardwareControls new];_hardware.readOnly=readOnly;
        [self buildWindow]; __weak typeof(self) weak=self;
        _manager.onChange=^{[weak updateStatus];};
        _hotKeys=[ODSHotKeys new];_hotKeys.action=^(NSUInteger action){
            if(action==1){[weak show];return;}if(action==4){[NSUserDefaults.standardUserDefaults removeObjectForKey:@"ODSAutoBrightness"];[weak.manager resetAdjustments];return;}
            ODSManagedDisplay *target=[weak selected];if(!target)for(ODSManagedDisplay *d in weak.manager.displays)if(d.main)target=d;
            NSDictionary *values=[weak.manager adjustments:target];[weak.manager setDimming:[values[@"brightness"] doubleValue]+(action==2?-.05:.05) warmth:[values[@"warmth"] doubleValue] display:target];
        };
        if(!readOnly && [NSUserDefaults.standardUserDefaults boolForKey:@"ODSGlobalShortcuts"]) [_hotKeys setEnabled:YES];
        _timer=[NSTimer scheduledTimerWithTimeInterval:4 repeats:YES block:^(NSTimer *t){
            [weak syncBrightness];
            if(!weak.window.visible) return; [weak.manager refresh];
            NSArray *f=[weak displayFingerprint]; if(![f isEqual:weak.fingerprint] && !weak.manager.pending) [weak render];
        }];
        [self render];
    } return self;
}
- (NSArray *)displayFingerprint {NSMutableArray *f=[NSMutableArray new];for(ODSManagedDisplay *d in self.manager.displays) [f addObject:[NSString stringWithFormat:@"%@-%lu-%lu-%.2f-%@",d.uuid,d.width,d.height,d.refreshRate,NSStringFromRect(d.bounds)]];return f;}
- (void)buildWindow {
    self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,990,760) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable|NSWindowStyleMaskFullSizeContentView backing:NSBackingStoreBuffered defer:NO];
    self.window.title=self.readOnly?@"OpenDisplayScaling · Read-only preview":@"OpenDisplayScaling"; self.window.titlebarAppearsTransparent=YES; self.window.minSize=NSMakeSize(900,650); self.window.releasedWhenClosed=NO; [self.window center];
    NSView *content=self.window.contentView;
    NSVisualEffectView *sidebar=[NSVisualEffectView new]; sidebar.material=NSVisualEffectMaterialSidebar; sidebar.blendingMode=NSVisualEffectBlendingModeBehindWindow;sidebar.state=NSVisualEffectStateActive;sidebar.translatesAutoresizingMaskIntoConstraints=NO;[content addSubview:sidebar];
    self.nav=Column(@[],7);self.nav.translatesAutoresizingMaskIntoConstraints=NO;[sidebar addSubview:self.nav];
    NSTextField *brand=Text(@"OpenDisplayScaling",15,YES);[self.nav addArrangedSubview:brand];
    NSTextField *sub=Text(@"FREE & OPEN SOURCE",9,YES);sub.textColor=NSColor.secondaryLabelColor;[self.nav addArrangedSubview:sub];[self.nav setCustomSpacing:28 afterView:sub];
    NSArray *sections=@[@"Displays",@"Groups",@"Controls",@"Application",@"Menu",@"Keyboard",@"Features",@"About"];
    NSArray *symbols=@[@"display.2",@"square.grid.2x2",@"slider.horizontal.3",@"switch.2",@"menubar.rectangle",@"keyboard",@"checklist",@"info.circle"];
    for(NSUInteger i=0;i<sections.count;i++) {NSButton *b=Action(sections[i],self,@selector(navigate:));b.identifier=sections[i];b.image=[NSImage imageWithSystemSymbolName:symbols[i] accessibilityDescription:nil];b.imagePosition=NSImageLeft;b.alignment=NSTextAlignmentLeft;b.bezelStyle=NSBezelStyleRecessed;b.buttonType=NSButtonTypePushOnPushOff;b.contentTintColor=NSColor.controlAccentColor;[b.widthAnchor constraintEqualToConstant:170].active=YES;[b.heightAnchor constraintEqualToConstant:36].active=YES;[self.nav addArrangedSubview:b];}
    NSTextField *version=Text(@"0.2.0 Preview\nMade for your displays.",11,NO);version.textColor=NSColor.secondaryLabelColor;version.translatesAutoresizingMaskIntoConstraints=NO;[sidebar addSubview:version];
    self.page=[NSView new];self.page.translatesAutoresizingMaskIntoConstraints=NO;[content addSubview:self.page];
    NSView *footer=[NSView new];footer.translatesAutoresizingMaskIntoConstraints=NO;[content addSubview:footer];
    self.status=Text(@"",11,NO);self.status.textColor=NSColor.secondaryLabelColor;self.status.translatesAutoresizingMaskIntoConstraints=NO;[footer addSubview:self.status];
    self.keepButton=Action(@"Keep",self,@selector(keep:));self.keepButton.keyEquivalent=@"\r";
    self.revertButton=Action(@"Revert",self,@selector(revert:));self.revertButton.keyEquivalent=@"\033";
    NSStackView *actions=Row(@[self.revertButton,self.keepButton],8);actions.translatesAutoresizingMaskIntoConstraints=NO;[footer addSubview:actions];
    [NSLayoutConstraint activateConstraints:@[
        [sidebar.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],[sidebar.topAnchor constraintEqualToAnchor:content.topAnchor],[sidebar.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],[sidebar.widthAnchor constraintEqualToConstant:210],
        [self.nav.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:20],[self.nav.topAnchor constraintEqualToAnchor:sidebar.topAnchor constant:58],
        [version.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:24],[version.bottomAnchor constraintEqualToAnchor:sidebar.bottomAnchor constant:-24],
        [self.page.leadingAnchor constraintEqualToAnchor:sidebar.trailingAnchor],[self.page.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],[self.page.topAnchor constraintEqualToAnchor:content.topAnchor constant:32],[self.page.bottomAnchor constraintEqualToAnchor:footer.topAnchor],
        [footer.leadingAnchor constraintEqualToAnchor:sidebar.trailingAnchor],[footer.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],[footer.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],[footer.heightAnchor constraintEqualToConstant:58],
        [self.status.leadingAnchor constraintEqualToAnchor:footer.leadingAnchor constant:24],[self.status.centerYAnchor constraintEqualToAnchor:footer.centerYAnchor],[self.status.trailingAnchor constraintLessThanOrEqualToAnchor:actions.leadingAnchor constant:-14],
        [actions.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor constant:-24],[actions.centerYAnchor constraintEqualToAnchor:footer.centerYAnchor]]];
}
- (void)navigate:(NSButton *)sender {self.section=sender.identifier;self.selectedUUID=nil;[self render];}
- (ODSManagedDisplay *)selected {for(ODSManagedDisplay *d in self.manager.displays) if([d.uuid isEqual:self.selectedUUID]) return d;return nil;}
- (void)render {
    [self.manager refresh];self.fingerprint=[self displayFingerprint];
    if(!self.readOnly){NSMutableDictionary *known=[[NSUserDefaults.standardUserDefaults dictionaryForKey:@"ODSKnownDisplays"] mutableCopy] ?: [NSMutableDictionary new];for(ODSManagedDisplay *d in self.manager.displays)if(!d.ownedVirtual && CGDisplayVendorNumber(d.displayID)!=0x4F4453)known[d.uuid]=d.name;[NSUserDefaults.standardUserDefaults setObject:known forKey:@"ODSKnownDisplays"];}
    for(NSView *v in self.page.subviews.copy) [v removeFromSuperview];
    for(NSView *v in self.nav.arrangedSubviews) if([v isKindOfClass:NSButton.class]) {((NSButton *)v).state=[v.identifier isEqual:self.section]?NSControlStateValueOn:NSControlStateValueOff;((NSButton *)v).bordered=[v.identifier isEqual:self.section];}
    NSScrollView *scroll=[NSScrollView new];scroll.hasVerticalScroller=YES;scroll.drawsBackground=NO;scroll.translatesAutoresizingMaskIntoConstraints=NO;[self.page addSubview:scroll];
    NSView *document=[NSView new];document.translatesAutoresizingMaskIntoConstraints=NO;scroll.documentView=document;
    self.body=Column(@[],20);self.body.translatesAutoresizingMaskIntoConstraints=NO;[document addSubview:self.body];
    [NSLayoutConstraint activateConstraints:@[[scroll.leadingAnchor constraintEqualToAnchor:self.page.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:self.page.trailingAnchor],[scroll.topAnchor constraintEqualToAnchor:self.page.topAnchor],[scroll.bottomAnchor constraintEqualToAnchor:self.page.bottomAnchor],
        [document.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor],[self.body.leadingAnchor constraintEqualToAnchor:document.leadingAnchor constant:28],[self.body.trailingAnchor constraintEqualToAnchor:document.trailingAnchor constant:-28],[self.body.topAnchor constraintEqualToAnchor:document.topAnchor constant:24],[self.body.bottomAnchor constraintEqualToAnchor:document.bottomAnchor constant:-28]]];
    if([self.section isEqual:@"Displays"]) [self displayPage];
    else if([self.section isEqual:@"Groups"]) [self groupsPage];
    else if([self.section isEqual:@"Controls"]) [self controlsPage];
    else if([self.section isEqual:@"Application"]) [self applicationPage];
    else if([self.section isEqual:@"Menu"]) [self menuPage];
    else if([self.section isEqual:@"Keyboard"]) [self keyboardPage];
    else if([self.section isEqual:@"Features"]) [self featuresPage];
    else [self aboutPage];
    [self updateStatus];
}
- (void)add:(NSView *)v { [self.body addArrangedSubview:v];[v.widthAnchor constraintEqualToAnchor:self.body.widthAnchor].active=YES; }
- (void)heading:(NSString *)title subtitle:(NSString *)subtitle { [self add:Text(title,25,YES)];NSTextField *s=Text(subtitle,12,NO);s.textColor=NSColor.secondaryLabelColor;[self add:s]; }
- (NSView *)card:(NSArray *)views {
    NSBox *box=[NSBox new];box.boxType=NSBoxCustom;box.borderWidth=.5;box.cornerRadius=12;box.borderColor=[NSColor.separatorColor colorWithAlphaComponent:.3];box.fillColor=NSColor.controlBackgroundColor;box.contentViewMargins=NSMakeSize(16,14);
    NSStackView *stack=Column(views,12);stack.translatesAutoresizingMaskIntoConstraints=NO;[box.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:box.contentView.leadingAnchor],[stack.trailingAnchor constraintEqualToAnchor:box.contentView.trailingAnchor],[stack.topAnchor constraintEqualToAnchor:box.contentView.topAnchor],[stack.bottomAnchor constraintEqualToAnchor:box.contentView.bottomAnchor]]];
    for(NSView *v in views) [v.widthAnchor constraintLessThanOrEqualToAnchor:stack.widthAnchor].active=YES;return box;
}
- (NSButton *)displayButton:(ODSManagedDisplay *)d {
    NSButton *b=Action([NSString stringWithFormat:@"%@%@    %lu × %lu    ›",d.name,d.main?@" · Main":@"",d.width,d.height],self,@selector(selectDisplay:));b.identifier=d.uuid;b.image=[NSImage imageWithSystemSymbolName:d.builtIn?@"laptopcomputer":@"display" accessibilityDescription:nil];b.imagePosition=NSImageLeft;b.alignment=NSTextAlignmentLeft;b.bezelStyle=NSBezelStyleRecessed;[b.heightAnchor constraintEqualToConstant:38].active=YES;return b;
}
- (void)selectDisplay:(id)sender {self.section=@"Displays";self.selectedUUID=[sender isKindOfClass:NSMenuItem.class]?[sender representedObject]:[sender identifier];[self render];[self show];}
- (void)displayPage {
    ODSManagedDisplay *d=[self selected];
    if(d) { [self details:d];return; }
    [self heading:@"Displays" subtitle:@"A comfortable desktop, on every screen."];
    NSMutableArray *displayRows=[NSMutableArray new];for(ODSManagedDisplay *item in self.manager.displays) if(!item.ownedVirtual) [displayRows addObject:[self displayButton:item]];
    if(!displayRows.count) [displayRows addObject:Text(@"No connected displays found.",13,NO)];
    if([NSUserDefaults.standardUserDefaults boolForKey:@"ODSShowOffline"]){NSDictionary *known=[NSUserDefaults.standardUserDefaults dictionaryForKey:@"ODSKnownDisplays"];for(NSString *uuid in known)if(![self find:uuid]){NSTextField *offline=Text([NSString stringWithFormat:@"%@ · Offline",known[uuid]],12,NO);offline.textColor=NSColor.secondaryLabelColor;[displayRows addObject:offline];}}
    [self add:[self card:displayRows]];
    NSButton *offline=[NSButton checkboxWithTitle:@"Show previously connected displays" target:self action:@selector(offlinePreference:)];offline.identifier=@"ODSShowOffline";offline.state=[NSUserDefaults.standardUserDefaults boolForKey:offline.identifier];offline.enabled=!self.readOnly;[self add:offline];
    [self add:[self card:@[Text(@"Custom HiDPI scaling",15,YES),Text(@"Choose the desktop size you want. Render at 2× for finer text on an external monitor.",12,NO),Action(@"Configure custom scaling…",self,@selector(scaling:))]]];
    NSMutableArray *virtualRows=[NSMutableArray arrayWithArray:@[Text(@"Virtual screens",15,YES),Text(@"Create an additional desktop for mirroring or a local picture-in-picture preview. Virtual screens last for this app session.",12,NO)]];
    for(ODSManagedDisplay *v in self.manager.displays) if(v.ownedVirtual) [virtualRows addObject:[self displayButton:v]];
    NSButton *create=Action(@"Create virtual screen…",self,@selector(createVirtual:));create.enabled=!self.readOnly;[virtualRows addObject:create];[self add:[self card:virtualRows]];
    [self add:[self card:@[Text(@"Custom controls",15,YES),Text(@"Save a named hardware brightness, contrast, color-gain or volume value for one display.",12,NO),Action(@"Manage custom controls…",self,@selector(openControls:))]]];
    [self add:[self card:@[Text(@"Display connections",15,YES),Text(@"Connected screens are discovered automatically. Hardware power and disconnect controls are not available in this preview.",12,NO),Row(@[Action(@"Refresh displays",self,@selector(refresh:)),Action(@"macOS Displays settings…",self,@selector(systemDisplays:)),Action(@"Restore layout",self,@selector(restoreLayout:))],10)]]];
}
- (void)details:(ODSManagedDisplay *)d {
    [self add:Action(@"‹ All displays",self,@selector(allDisplays:))];
    [self heading:d.name subtitle:[NSString stringWithFormat:@"%@ · %lu × %lu desktop · %lu × %lu pixels · %@",d.builtIn?@"Built-in":d.ownedVirtual?@"Virtual":@"External",d.width,d.height,d.pixelWidth,d.pixelHeight,d.refreshRate>0?[NSString stringWithFormat:@"%.1f Hz",d.refreshRate]:@"Variable / unspecified refresh"]];
    self.modePicker=[NSPopUpButton new];self.modePicker.accessibilityLabel=@"Resolution and refresh rate";
    for(NSDictionary *m in d.modes) { [self.modePicker addItemWithTitle:ModeTitle(m)];self.modePicker.lastItem.representedObject=m;
        if([m[@"width"] unsignedIntegerValue]==d.width && [m[@"height"] unsignedIntegerValue]==d.height && [m[@"pixelWidth"] unsignedIntegerValue]==d.pixelWidth && fabs([m[@"refreshRate"] doubleValue]-d.refreshRate)<.1) [self.modePicker selectItem:self.modePicker.lastItem]; }
    NSButton *apply=Action(@"Apply mode",self,@selector(applyMode:));apply.enabled=!self.readOnly;
    [self add:[self card:@[Text(@"Resolution & refresh rate",15,YES),self.modePicker,Row(@[apply,Action(@"Custom HiDPI…",self,@selector(scaling:))],10),Text(@"Only modes reported by macOS are listed. Changes revert after 20 seconds unless kept.",11,NO)]]];
    self.hardwareFeature=[NSPopUpButton new];self.hardwareFeature.accessibilityLabel=@"Hardware control";
    for(NSArray *item in @[@[@"Brightness",@"luminance"],@[@"Contrast",@"contrast"],@[@"Red gain",@"red"],@[@"Green gain",@"green"],@[@"Blue gain",@"blue"],@[@"Speaker volume",@"volume"]]) {[self.hardwareFeature addItemWithTitle:item[0]];self.hardwareFeature.lastItem.representedObject=item[1];}
    self.hardwareFeature.target=self;self.hardwareFeature.action=@selector(hardwareFeatureChanged:);
    self.hardwareValue=[NSSlider sliderWithValue:50 minValue:0 maxValue:100 target:self action:@selector(hardwareValueChanged:)];self.hardwareValue.enabled=NO;self.hardwareValue.accessibilityLabel=@"Hardware value";[self.hardwareValue.widthAnchor constraintEqualToConstant:300].active=YES;
    self.hardwareApply=Action(@"Apply hardware value",self,@selector(writeHardware:));self.hardwareApply.enabled=NO;
    NSButton *probe=Action(@"Read from display",self,@selector(readHardware:));probe.enabled=!self.readOnly;
    self.hardwareStatus=Text(d.builtIn?@"Native Apple brightness. Read the current value before changing it.":@"DDC/CI via m1ddc. Read the supported range before changing a value.",11,NO);
    self.hardwareUUID=d.uuid;self.verifiedFeature=nil;self.verifiedMaximum=0;
    [self add:[self card:@[Text(@"Hardware controls",15,YES),Row(@[self.hardwareFeature,probe],10),Row(@[self.hardwareValue,self.hardwareApply],10),self.hardwareStatus,Action(@"Save as custom control…",self,@selector(saveControl:))]]];
    NSDictionary *image=[self.manager adjustments:d];self.brightness=[NSSlider sliderWithValue:[image[@"brightness"] doubleValue] minValue:.2 maxValue:1 target:self action:@selector(adjust:)];self.brightness.accessibilityLabel=@"Software brightness";self.brightness.continuous=YES;
    self.warmth=[NSSlider sliderWithValue:[image[@"warmth"] doubleValue] minValue:0 maxValue:1 target:self action:@selector(adjust:)];self.warmth.accessibilityLabel=@"Warm tint";self.warmth.continuous=YES;
    for(NSSlider *s in @[self.brightness,self.warmth]) {[s.widthAnchor constraintEqualToConstant:320].active=YES;s.enabled=!self.readOnly && !d.mirrored;}
    NSButton *sync=[NSButton checkboxWithTitle:@"Auto dim: follow built-in display brightness" target:self action:@selector(toggleAutoBrightness:)];sync.identifier=d.uuid;sync.state=[[[NSUserDefaults.standardUserDefaults dictionaryForKey:@"ODSAutoBrightness"] objectForKey:d.uuid] boolValue];sync.enabled=!self.readOnly && !d.builtIn && !d.mirrored;
    [self add:[self card:@[Text(@"Image adjustments",15,YES),Row(@[Text(@"Brightness",12,NO),self.brightness],20),Row(@[Text(@"Warm tint",12,NO),self.warmth],20),Text(@"Software overlay only: does not change the monitor’s backlight or measured nits. Unavailable for mirrored displays.",11,NO),sync,Action(@"Reset image adjustments",self,@selector(resetImage:))]]];
    self.mirrorPicker=[NSPopUpButton new];[self.mirrorPicker addItemWithTitle:@"Extended desktop (no mirror)"];
    self.anchorPicker=[NSPopUpButton new];
    for(ODSManagedDisplay *other in self.manager.displays) if(other.displayID!=d.displayID) {
        [self.mirrorPicker addItemWithTitle:[@"Mirror " stringByAppendingString:other.name]];self.mirrorPicker.lastItem.representedObject=other.uuid;
        if(CGDisplayMirrorsDisplay(d.displayID)==other.displayID) [self.mirrorPicker selectItem:self.mirrorPicker.lastItem];
        [self.anchorPicker addItemWithTitle:other.name];self.anchorPicker.lastItem.representedObject=other.uuid;
    }
    self.directionPicker=[NSPopUpButton new];[self.directionPicker addItemsWithTitles:@[@"Right",@"Left",@"Above",@"Below"]];
    NSButton *mirror=Action(@"Apply mirroring",self,@selector(mirror:));mirror.enabled=!self.readOnly;
    NSButton *move=Action(@"Move display",self,@selector(move:));move.enabled=!self.readOnly && !d.main && !d.mirrored && self.anchorPicker.numberOfItems>0;
    NSButton *main=Action(d.main?@"Main display":@"Set as main display",self,@selector(makeMain:));main.enabled=!self.readOnly && !d.main && !d.mirrored;
    [self add:[self card:@[Text(@"Arrangement & mirroring",15,YES),Row(@[self.mirrorPicker,mirror],10),Row(@[self.directionPicker,Text(@"of",12,NO),self.anchorPicker],8),Row(@[move,main],10)]]];
    NSButton *pip=Action(@"Open picture in picture…",self,@selector(picture:));pip.enabled=!self.readOnly;
    [self add:[self card:@[Text(@"Local display stream",15,YES),Text(@"A floating live preview on this Mac. Screen Recording permission is requested only when you open it. No audio, files, or network transmission.",12,NO),pip]]];
    NSButton *profile=Action(@"Choose ICC profile…",self,@selector(colorProfile:));profile.enabled=!self.readOnly;
    NSButton *factory=Action(@"Factory color profile",self,@selector(factoryProfile:));factory.enabled=!self.readOnly;
    [self add:[self card:@[Text(@"Color & hardware",15,YES),Text([NSString stringWithFormat:@"Color space: %@\nRotation: %.0f°",d.colorSpace ?: @"System default",d.rotation],12,NO),Row(@[profile,factory],10),Action(@"HDR, rotation & Apple presets in macOS…",self,@selector(systemDisplays:)),Text(@"ICC profiles persist after quitting. XDR brightness upscaling and notch modes are not implemented here.",11,NO)]]];
    if(d.ownedVirtual) {NSButton *remove=Action(@"Remove this virtual screen",self,@selector(removeVirtual:));remove.enabled=!self.readOnly;[self add:remove];}
}
- (void)groupsPage {
    [self heading:@"Groups" subtitle:@"Save a connected display layout and restore it together."];
    [self add:[self card:@[Text(@"Save this setup",15,YES),Text(@"Groups remember display identities, native modes, refresh rates, positions and mirroring. Applying a group requires every saved display to be connected.",12,NO),Action(@"Save current layout…",self,@selector(saveGroup:))]]];
    NSDictionary *groups=[NSUserDefaults.standardUserDefaults dictionaryForKey:@"ODSLayoutGroups"] ?: @{};
    for(NSString *name in [groups.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]) {
        NSButton *apply=Action(@"Apply group",self,@selector(applyGroup:));apply.identifier=name;apply.enabled=!self.readOnly;
        NSButton *remove=Action(@"Delete",self,@selector(deleteGroup:));remove.identifier=name;remove.enabled=!self.readOnly;
        [self add:[self card:@[Text(name,15,YES),Row(@[apply,remove],10)]]];
    }
    if(!groups.count) [self add:Text(@"No saved groups yet.",12,NO)];
}
- (void)openControls:(id)sender {self.section=@"Controls";self.selectedUUID=nil;[self render];}
- (void)controlsPage {
    [self heading:@"Custom controls" subtitle:@"Named hardware settings for a specific monitor."];
    [self add:Text(@"Open a display, read a hardware control, choose a value, then save it here. Each use rechecks the monitor’s supported range before sending a command.",12,NO)];
    NSDictionary *controls=[NSUserDefaults.standardUserDefaults dictionaryForKey:@"ODSCustomControls"] ?: @{};
    for(NSString *name in [controls.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]) {
        NSDictionary *c=controls[name];NSButton *run=Action(@"Run control",self,@selector(runControl:));run.identifier=name;run.enabled=!self.readOnly;
        NSButton *remove=Action(@"Delete",self,@selector(deleteControl:));remove.identifier=name;remove.enabled=!self.readOnly;
        [self add:[self card:@[Text(name,15,YES),Text([NSString stringWithFormat:@"%@ · %@ = %@",c[@"displayName"],c[@"feature"],c[@"value"]],12,NO),Row(@[run,remove],10)]]];
    }
    if(!controls.count)[self add:Text(@"No custom controls saved yet.",13,NO)];
}
- (void)saveControl:(id)sender {
    if(self.readOnly)return;
    ODSManagedDisplay *d=[self selected];if(!d || ![d.uuid isEqual:self.hardwareUUID] || !self.verifiedFeature || !self.verifiedMaximum){self.status.stringValue=@"Read a hardware control first, then choose the value to save.";return;}
    NSDictionary *control=@{@"uuid":d.uuid,@"displayName":d.name,@"feature":self.verifiedFeature,@"value":@(lround(self.hardwareValue.doubleValue))};
    NSAlert *alert=[NSAlert new];alert.messageText=@"Name this custom control";[alert addButtonWithTitle:@"Save"];[alert addButtonWithTitle:@"Cancel"];NSTextField *field=[NSTextField textFieldWithString:@"Reading brightness"];field.frame=NSMakeRect(0,0,320,24);alert.accessoryView=field;
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r){if(r!=NSAlertFirstButtonReturn)return;NSString *name=[field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];NSMutableDictionary *controls=[[NSUserDefaults.standardUserDefaults dictionaryForKey:@"ODSCustomControls"] mutableCopy] ?: [NSMutableDictionary new];if(!name.length || controls[name]){self.status.stringValue=@"Choose a unique, non-empty control name.";return;}controls[name]=control;[NSUserDefaults.standardUserDefaults setObject:controls forKey:@"ODSCustomControls"];self.status.stringValue=@"Custom control saved.";}];
}
- (void)runControl:(NSButton *)sender {
    if(self.readOnly)return;NSDictionary *c=[NSUserDefaults.standardUserDefaults dictionaryForKey:@"ODSCustomControls"][sender.identifier];[self.manager refresh];ODSManagedDisplay *d=[self find:c[@"uuid"]];if(!d){self.status.stringValue=@"Connect the saved monitor before running this control.";return;}
    self.status.stringValue=@"Checking monitor range…";sender.enabled=NO;
    [self.hardware read:c[@"feature"] display:d completion:^(NSNumber *value,NSNumber *maximum,NSString *error){if(error){self.status.stringValue=error;sender.enabled=YES;return;}[self.hardware write:c[@"feature"] value:[c[@"value"] integerValue] maximum:maximum.integerValue display:d completion:^(NSString *message){self.status.stringValue=message;sender.enabled=YES;}];}];
}
- (void)deleteControl:(NSButton *)sender {if(self.readOnly)return;NSMutableDictionary *c=[[NSUserDefaults.standardUserDefaults dictionaryForKey:@"ODSCustomControls"] mutableCopy];[c removeObjectForKey:sender.identifier];[NSUserDefaults.standardUserDefaults setObject:c forKey:@"ODSCustomControls"];[self render];}
- (void)toggleAutoBrightness:(NSButton *)sender {
    if(self.readOnly)return;NSMutableDictionary *values=[[NSUserDefaults.standardUserDefaults dictionaryForKey:@"ODSAutoBrightness"] mutableCopy] ?: [NSMutableDictionary new];values[sender.identifier]=@(sender.state==NSControlStateValueOn);[NSUserDefaults.standardUserDefaults setObject:values forKey:@"ODSAutoBrightness"];[self syncBrightness];
}
- (void)syncBrightness {
    if(self.readOnly || self.autoBrightnessBusy)return;
    NSDictionary *targets=[NSUserDefaults.standardUserDefaults dictionaryForKey:@"ODSAutoBrightness"];if(!targets.count)return;
    [self.manager refresh];ODSManagedDisplay *builtIn=nil;for(ODSManagedDisplay *d in self.manager.displays)if(d.builtIn)builtIn=d;if(!builtIn)return;
    self.autoBrightnessBusy=YES;
    [self.hardware read:@"luminance" display:builtIn completion:^(NSNumber *value,NSNumber *maximum,NSString *error){self.autoBrightnessBusy=NO;if(error || !maximum.doubleValue)return;for(ODSManagedDisplay *d in self.manager.displays)if(!d.builtIn && !d.mirrored && [targets[d.uuid] boolValue]){[self.manager setDimming:MAX(.2,value.doubleValue/maximum.doubleValue) warmth:[[self.manager adjustments:d][@"warmth"] doubleValue] display:d];}}];
}
- (void)applicationPage {
    [self heading:@"Application" subtitle:@"Quiet by default. Ready when you need it."];
    NSButton *login=[NSButton checkboxWithTitle:@"Launch at login" target:self action:@selector(login:)];login.state=SMAppService.mainAppService.status==SMAppServiceStatusEnabled?NSControlStateValueOn:SMAppService.mainAppService.status==SMAppServiceStatusRequiresApproval?NSControlStateValueMixed:NSControlStateValueOff;login.enabled=!self.readOnly;
    NSButton *reapply=[NSButton checkboxWithTitle:@"Reapply saved custom HiDPI size on launch" target:self action:@selector(preference:)];reapply.identifier=@"ODSReapplyOnLaunch";reapply.state=[NSUserDefaults.standardUserDefaults boolForKey:reapply.identifier];reapply.enabled=!self.readOnly;
    [self add:[self card:@[Text(@"Startup",15,YES),login,reapply,Action(@"Login Items settings…",self,@selector(loginSettings:)),Text(@"Native mode and arrangement changes last for this app session. Standalone virtual screens are never recreated automatically. Auto dimming resumes only for displays where you enabled it.",12,NO)]]];
    [self add:[self card:@[Text(@"Privacy",15,YES),Text(@"No accounts, analytics, subscriptions or background network requests. Screen capture starts only when you request a local preview. Settings and groups stay on this Mac.",12,NO)]]];
}
- (void)menuPage {
    [self heading:@"Menu" subtitle:@"Choose what appears under each display in the menu bar."];
    NSMutableArray *rows=[NSMutableArray new];
    for(NSArray *item in @[@[@"Show resolution and refresh rate",@"ODSMenuModes"],@[@"Show software dimming controls",@"ODSMenuDimming"],@[@"Show picture-in-picture shortcut",@"ODSMenuPreview"]]) {
        NSButton *box=[NSButton checkboxWithTitle:item[0] target:self action:@selector(preference:)];box.identifier=item[1];box.state=[NSUserDefaults.standardUserDefaults objectForKey:item[1]]?[NSUserDefaults.standardUserDefaults boolForKey:item[1]]:YES;box.enabled=!self.readOnly;[rows addObject:box];
    } [self add:[self card:rows]];[self add:Text(@"Changes appear the next time you open the menu.",12,NO)];
}
- (void)keyboardPage {
    [self heading:@"Keyboard" subtitle:@"Shortcuts while OpenDisplayScaling is active."];
    [self add:[self card:@[Text(@"⌘ ,     Open display manager\n⌘ ⇧ D     Open custom scaling\nReturn     Keep a pending display change\nEscape     Revert a pending display change\n⌘ Q     Quit and remove app-session changes",14,NO)]]];
    NSButton *global=[NSButton checkboxWithTitle:@"Enable global shortcuts" target:self action:@selector(toggleHotKeys:)];global.state=[NSUserDefaults.standardUserDefaults boolForKey:@"ODSGlobalShortcuts"];global.enabled=!self.readOnly;
    [self add:[self card:@[global,Text(@"⌃ ⌥ D     Open display manager\n⌃ ⌥ ↓     Dim selected display\n⌃ ⌥ ↑     Brighten selected display\n⌃ ⌥ R     Reset all software dimming",14,NO),Text(@"Dimming targets the selected display, or the main display if none is selected. These shortcuts do not intercept the keyboard’s hardware brightness keys.",12,NO)]]];
}
- (void)featuresPage {
    [self heading:@"Features" subtitle:@"Everything included is free. This is the current implementation status."];
    NSArray *entries=@[
        @[@"Implemented · display controls",@"Native resolution and refresh modes, custom external HiDPI, main display, four-way positioning, mirroring and timed revert."],
        @[@"Implemented · workspace",@"Standalone virtual screens, saved layout groups, menu preferences, launch at login and local picture-in-picture capture."],
        @[@"Implemented · hardware controls",@"Native built-in brightness, DDC brightness, contrast, RGB gain and volume through the bundled MIT-licensed m1ddc helper. Requires a compatible display and connection. ICC color profile selection and factory reset."],
        @[@"Implemented · software image controls",@"Brightness dimming, warm tint overlays and optional auto dimming that follows built-in brightness. These do not control the panel backlight, HDR or physical color settings."],
        @[@"Open in macOS",@"HDR, rotation, Apple presets and hardware options supported by macOS are available through the Displays settings shortcut."],
        @[@"Not implemented",@"Connect/disconnect, XDR upscaling, notch modes, direct Apple display presets, network streaming, arbitrary CLI/network controls and hardware brightness-key interception."],
        @[@"Verification",@"This 0.2 preview has build and read-only UI checks. New hardware-changing controls and capture still require hands-on testing. It is not BetterDisplay feature parity."]];
    for(NSArray *e in entries) [self add:[self card:@[Text(e[0],14,YES),Text(e[1],12,NO)]]];
}
- (void)aboutPage {
    [self heading:@"OpenDisplayScaling" subtitle:@"Your display. Your preferred size."];
    [self add:[self card:@[Text(@"0.2.0 Preview · Free & open source",16,YES),Text(@"A native macOS display manager by colmecti. MIT licensed, with no paid tier. Independently implemented; not affiliated with BetterDisplay.",13,NO),Action(@"Source code & support",self,@selector(github:)),Action(@"Check releases…",self,@selector(releases:))]]];
    [self add:Text(@"Apple silicon · macOS 13+\nVirtual displays use private macOS APIs. Preview builds are ad-hoc signed, not Apple-notarized. See the repository for testing notes and third-party notices.",12,NO)];
}
- (void)updateStatus {self.status.stringValue=self.readOnly?@"READ-ONLY PREVIEW · Your display configuration cannot change here.":self.manager.message;self.keepButton.hidden=self.revertButton.hidden=!self.manager.pending;if(self.manager.pending && !self.window.visible) [self show];}
- (void)show {[self.window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];}
- (void)allDisplays:(id)sender {self.selectedUUID=nil;[self render];}
- (void)refresh:(id)sender {[self render];}
- (void)scaling:(id)sender {if(self.openScaling) self.openScaling();else self.status.stringValue=@"Custom scaling is disabled in this read-only preview.";}
- (void)systemDisplays:(id)sender {[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.Displays-Settings.extension"]];}
- (void)loginSettings:(id)sender {[SMAppService openSystemSettingsLoginItems];}
- (void)login:(id)sender {if(self.toggleLogin) self.toggleLogin();[self render];}
- (void)toggleHotKeys:(NSButton *)sender {if(self.readOnly)return;BOOL requested=sender.state==NSControlStateValueOn;BOOL ok=[self.hotKeys setEnabled:requested];if(!ok){sender.state=NSControlStateValueOff;self.status.stringValue=@"A shortcut is already in use. Global shortcuts were not enabled.";}[NSUserDefaults.standardUserDefaults setBool:requested && ok forKey:@"ODSGlobalShortcuts"];}
- (void)offlinePreference:(NSButton *)sender {[self preference:sender];[self render];}
- (void)preference:(NSButton *)sender {if(!self.readOnly) [NSUserDefaults.standardUserDefaults setBool:sender.state==NSControlStateValueOn forKey:sender.identifier];}
- (void)restoreLayout:(id)sender {[self.manager restoreSessionLayout];[self render];}
- (void)hardwareFeatureChanged:(id)sender {self.verifiedFeature=nil;self.hardwareValue.enabled=NO;self.hardwareApply.enabled=NO;self.hardwareStatus.stringValue=@"Read this control from the display first.";}
- (void)hardwareValueChanged:(id)sender {self.hardwareStatus.stringValue=[NSString stringWithFormat:@"Requested value: %ld / %ld",(long)lround(self.hardwareValue.doubleValue),(long)self.verifiedMaximum];}
- (void)readHardware:(id)sender {
    ODSManagedDisplay *d=[self selected];NSString *feature=self.hardwareFeature.selectedItem.representedObject;NSString *uuid=d.uuid;
    self.hardwareStatus.stringValue=@"Reading display…";self.hardwareApply.enabled=NO;self.hardwareValue.enabled=NO;
    [self.hardware read:feature display:d completion:^(NSNumber *value,NSNumber *maximum,NSString *error){
        if(![self.hardwareUUID isEqual:uuid] || ![self.hardwareFeature.selectedItem.representedObject isEqual:feature])return;
        if(error){self.hardwareStatus.stringValue=error;return;}
        self.verifiedFeature=feature;self.verifiedMaximum=maximum.integerValue;self.hardwareValue.maxValue=maximum.doubleValue;self.hardwareValue.doubleValue=value.doubleValue;self.hardwareValue.enabled=YES;self.hardwareApply.enabled=YES;
        self.hardwareStatus.stringValue=[NSString stringWithFormat:@"Display reports %@ / %@. Changes affect the hardware and persist after quitting.",value,maximum];
    }];
}
- (void)writeHardware:(id)sender {
    ODSManagedDisplay *d=[self selected];if(![d.uuid isEqual:self.hardwareUUID] || ![self.verifiedFeature isEqual:self.hardwareFeature.selectedItem.representedObject])return;
    NSString *uuid=d.uuid;self.hardwareApply.enabled=NO;
    [self.hardware write:self.verifiedFeature value:lround(self.hardwareValue.doubleValue) maximum:self.verifiedMaximum display:d completion:^(NSString *message){if([self.hardwareUUID isEqual:uuid]){self.hardwareStatus.stringValue=message;self.hardwareApply.enabled=!self.readOnly;}}];
}
- (void)colorProfile:(id)sender {
    if(self.readOnly)return;ODSManagedDisplay *d=[self selected];NSOpenPanel *panel=[NSOpenPanel openPanel];panel.canChooseDirectories=NO;panel.allowsMultipleSelection=NO;panel.allowedContentTypes=@[[UTType typeWithFilenameExtension:@"icc"],[UTType typeWithFilenameExtension:@"icm"]];panel.message=@"Choose an ICC display profile. This changes the selected display’s saved color profile.";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result){if(result==NSModalResponseOK)[self.manager setColorProfile:panel.URL display:d];}];
}
- (void)factoryProfile:(id)sender {[self.manager setColorProfile:nil display:[self selected]];}
- (void)applyMode:(id)sender {[self.manager setMode:self.modePicker.selectedItem.representedObject display:[self selected]];}
- (void)keep:(id)sender {[self.manager keep];[self render];}
- (void)revert:(id)sender {[self.manager revert];[self render];}
- (void)adjust:(id)sender {[self.manager setDimming:self.brightness.doubleValue warmth:self.warmth.doubleValue display:[self selected]];}
- (void)resetImage:(id)sender {if(!self.readOnly) {[NSUserDefaults.standardUserDefaults removeObjectForKey:@"ODSAutoBrightness"];[self.manager resetAdjustments];}[self render];}
- (ODSManagedDisplay *)find:(NSString *)uuid {for(ODSManagedDisplay *d in self.manager.displays) if([d.uuid isEqual:uuid]) return d;return nil;}
- (void)mirror:(id)sender {[self.manager mirror:[self selected] source:[self find:self.mirrorPicker.selectedItem.representedObject]];}
- (void)move:(id)sender {[self.manager move:[self selected] relativeTo:[self find:self.anchorPicker.selectedItem.representedObject] direction:self.directionPicker.titleOfSelectedItem];}
- (void)makeMain:(id)sender {[self.manager makeMain:[self selected]];}
- (void)picture:(id)sender {ODSManagedDisplay *d=[self selected];if(!self.readOnly && d) [self.capture showDisplay:d.displayID name:d.name];}
- (void)removeVirtual:(id)sender {[self.manager removeVirtual:[self selected]];self.selectedUUID=nil;[self render];}
- (void)createVirtual:(id)sender {
    if(self.readOnly) return;NSAlert *alert=[NSAlert new];alert.messageText=@"Create virtual screen";alert.informativeText=@"Desktop size in pixels. A 2× backing surface is created at 60 Hz.";[alert addButtonWithTitle:@"Create"];[alert addButtonWithTitle:@"Cancel"];
    NSTextField *name=[NSTextField textFieldWithString:@"ODS Virtual Screen"],*w=[NSTextField textFieldWithString:@"1920"],*h=[NSTextField textFieldWithString:@"1080"];
    name.accessibilityLabel=@"Virtual screen name";w.accessibilityLabel=@"Virtual screen width";h.accessibilityLabel=@"Virtual screen height";
    NSStackView *fields=Column(@[name,Row(@[Text(@"Width",12,NO),w,Text(@"Height",12,NO),h],8)],10);fields.frame=NSMakeRect(0,0,380,64);[name.widthAnchor constraintEqualToConstant:380].active=YES;[w.widthAnchor constraintEqualToConstant:100].active=YES;[h.widthAnchor constraintEqualToConstant:100].active=YES;alert.accessoryView=fields;
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r){if(r==NSAlertFirstButtonReturn){[self.manager createVirtualWidth:w.stringValue height:h.stringValue name:name.stringValue];[self render];}}];
}
- (void)saveGroup:(id)sender {
    if(self.readOnly) {self.status.stringValue=@"Saving groups is disabled in preview mode.";return;}
    NSAlert *alert=[NSAlert new];alert.messageText=@"Save display group";alert.informativeText=@"Give this layout a unique name.";[alert addButtonWithTitle:@"Save"];[alert addButtonWithTitle:@"Cancel"];
    NSTextField *field=[NSTextField textFieldWithString:@"My workspace"];field.frame=NSMakeRect(0,0,320,24);alert.accessoryView=field;
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r){if(r!=NSAlertFirstButtonReturn)return;NSString *name=[field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];NSMutableDictionary *groups=[[NSUserDefaults.standardUserDefaults dictionaryForKey:@"ODSLayoutGroups"] mutableCopy] ?: [NSMutableDictionary new];if(!name.length || groups[name]){self.status.stringValue=@"Choose a non-empty, unique group name.";return;}groups[name]=[self.manager captureProfile];[NSUserDefaults.standardUserDefaults setObject:groups forKey:@"ODSLayoutGroups"];[self render];}];
}
- (void)applyGroup:(NSButton *)sender {[self.manager applyProfile:[NSUserDefaults.standardUserDefaults dictionaryForKey:@"ODSLayoutGroups"][sender.identifier]];}
- (void)deleteGroup:(NSButton *)sender {if(self.readOnly)return;NSMutableDictionary *g=[[NSUserDefaults.standardUserDefaults dictionaryForKey:@"ODSLayoutGroups"] mutableCopy];[g removeObjectForKey:sender.identifier];[NSUserDefaults.standardUserDefaults setObject:g forKey:@"ODSLayoutGroups"];[self render];}
- (void)github:(id)sender {[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"https://github.com/colmecti/OpenDisplayScaling"]];}
- (void)releases:(id)sender {[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"https://github.com/colmecti/OpenDisplayScaling/releases"]];}
- (BOOL)menuPreference:(NSString *)key {return [NSUserDefaults.standardUserDefaults objectForKey:key]?[NSUserDefaults.standardUserDefaults boolForKey:key]:YES;}
- (void)populateMenu:(NSMenu *)menu {
    [self.manager refresh];
    for(ODSManagedDisplay *d in self.manager.displays) {
        NSMenuItem *header=[[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%@%@",d.name,d.main?@" · Main":@""] action:nil keyEquivalent:@""];header.image=[NSImage imageWithSystemSymbolName:d.builtIn?@"laptopcomputer":@"display" accessibilityDescription:nil];[menu addItem:header];NSMenu *sub=[NSMenu new];header.submenu=sub;
        sub.autoenablesItems=NO;
        if([self menuPreference:@"ODSMenuDimming"]) {
            NSMenuItem *summary=[NSMenuItem new];NSView *view=[[NSView alloc] initWithFrame:NSMakeRect(0,0,310,65)];
            NSTextField *resolution=Text([NSString stringWithFormat:@"%lu × %lu · %@",d.width,d.height,d.refreshRate>0?[NSString stringWithFormat:@"%.1f Hz",d.refreshRate]:@"Variable refresh"],11,NO);resolution.frame=NSMakeRect(18,40,274,18);[view addSubview:resolution];
            NSSlider *slider=[NSSlider sliderWithValue:[[self.manager adjustments:d][@"brightness"] doubleValue] minValue:.2 maxValue:1 target:self action:@selector(menuSlider:)];slider.identifier=d.uuid;slider.frame=NSMakeRect(18,12,225,20);slider.accessibilityLabel=[@"Software brightness for " stringByAppendingString:d.name];slider.continuous=YES;slider.enabled=!self.readOnly && !d.mirrored;[view addSubview:slider];
            NSTextField *label=Text(@"Dim",10,NO);label.frame=NSMakeRect(255,12,38,18);label.textColor=NSColor.secondaryLabelColor;[view addSubview:label];summary.view=view;[menu addItem:summary];
        }
        NSMenuItem *settings=[sub addItemWithTitle:@"Display settings…" action:@selector(selectDisplay:) keyEquivalent:@""];settings.target=self;settings.representedObject=d.uuid;
        if([self menuPreference:@"ODSMenuModes"]) {
            NSMenuItem *modes=[sub addItemWithTitle:[NSString stringWithFormat:@"Resolution · %lu × %lu",d.width,d.height] action:nil keyEquivalent:@""];modes.submenu=[NSMenu new];modes.submenu.autoenablesItems=NO;
            for(NSDictionary *mode in d.modes) {NSMenuItem *m=[modes.submenu addItemWithTitle:ModeTitle(mode) action:@selector(menuMode:) keyEquivalent:@""];m.target=self;m.representedObject=@{@"uuid":d.uuid,@"mode":mode};m.enabled=!self.readOnly;}
        }
        if([self menuPreference:@"ODSMenuDimming"]) for(NSNumber *value in @[@1,@.8,@.6,@.4]) {NSMenuItem *m=[sub addItemWithTitle:[NSString stringWithFormat:@"Software brightness · %.0f%%",value.doubleValue*100] action:@selector(menuDim:) keyEquivalent:@""];m.target=self;m.representedObject=@{@"uuid":d.uuid,@"brightness":value};m.enabled=!self.readOnly && !d.mirrored;}
        if([self menuPreference:@"ODSMenuPreview"]) {NSMenuItem *m=[sub addItemWithTitle:@"Picture in picture…" action:@selector(menuPicture:) keyEquivalent:@""];m.target=self;m.representedObject=d.uuid;m.enabled=!self.readOnly;}
    }[menu addItem:NSMenuItem.separatorItem];
}
- (void)menuSlider:(NSSlider *)sender {ODSManagedDisplay *d=[self find:sender.identifier];[self.manager setDimming:sender.doubleValue warmth:[[self.manager adjustments:d][@"warmth"] doubleValue] display:d];}
- (void)menuMode:(NSMenuItem *)sender {[self.manager setMode:sender.representedObject[@"mode"] display:[self find:sender.representedObject[@"uuid"]]];[self show];}
- (void)menuDim:(NSMenuItem *)sender {ODSManagedDisplay *d=[self find:sender.representedObject[@"uuid"]];[self.manager setDimming:[sender.representedObject[@"brightness"] doubleValue] warmth:[[self.manager adjustments:d][@"warmth"] doubleValue] display:d];}
- (void)menuPicture:(NSMenuItem *)sender {ODSManagedDisplay *d=[self find:sender.representedObject];if(!self.readOnly && d)[self.capture showDisplay:d.displayID name:d.name];}
- (void)shutdown {[self.hotKeys setEnabled:NO];[self.timer invalidate];[self.capture stop];[self.manager shutdown];}
@end
