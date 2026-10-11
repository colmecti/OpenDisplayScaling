// SPDX-License-Identifier: MIT
#import "DisplayPreview.h"
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <CoreImage/CoreImage.h>
@interface ODSDisplayPreview () <SCStreamOutput,SCStreamDelegate,NSWindowDelegate>
@property(strong) NSWindow *window;
@property(strong) NSImageView *image;
@property(strong) NSTextField *status;
@property(strong) SCStream *stream;
@property(strong) CIContext *context;
@property NSUInteger generation;
@end
@implementation ODSDisplayPreview
- (void)showDisplay:(CGDirectDisplayID)display name:(NSString *)name {
    [self stop]; NSUInteger generation=++self.generation;
    self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,640,400) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    self.window.title=[@"Live preview · " stringByAppendingString:name]; self.window.level=NSFloatingWindowLevel; self.window.delegate=self; self.window.releasedWhenClosed=NO;
    self.image=[[NSImageView alloc] initWithFrame:self.window.contentView.bounds]; self.image.imageScaling=NSImageScaleProportionallyUpOrDown; self.image.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
    [self.window.contentView addSubview:self.image];
    self.status=[NSTextField wrappingLabelWithString:@"Starting local screen preview…"]; self.status.frame=NSMakeRect(20,20,590,45); self.status.autoresizingMask=NSViewWidthSizable; [self.window.contentView addSubview:self.status];
    [self.window center]; [self.window makeKeyAndOrderFront:nil];
    if(!CGPreflightScreenCaptureAccess()) {
        self.status.stringValue=@"Allow Screen Recording in macOS Privacy & Security, then close and reopen this preview. Frames stay on this Mac.";
        CGRequestScreenCaptureAccess(); return;
    }
    __weak typeof(self) weak=self;
    [SCShareableContent getShareableContentExcludingDesktopWindows:NO onScreenWindowsOnly:NO completionHandler:^(SCShareableContent *content,NSError *error){
        dispatch_async(dispatch_get_main_queue(),^{
            typeof(self) strong=weak; if(!strong || strong.generation!=generation) return;
            SCDisplay *selected=nil; for(SCDisplay *d in content.displays) if(d.displayID==display) selected=d;
            if(error || !selected) {strong.status.stringValue=error.localizedDescription ?: @"Display is no longer available."; return;}
            NSMutableArray *excluded=[NSMutableArray new]; for(SCRunningApplication *a in content.applications) if(a.processID==NSProcessInfo.processInfo.processIdentifier) [excluded addObject:a];
            SCContentFilter *filter=[[SCContentFilter alloc] initWithDisplay:selected excludingApplications:excluded exceptingWindows:@[]];
            SCStreamConfiguration *config=[SCStreamConfiguration new]; config.width=1280; config.height=MAX(1,1280*selected.height/MAX(1,selected.width)); config.minimumFrameInterval=CMTimeMake(1,15); config.queueDepth=3; config.capturesAudio=NO; config.showsCursor=YES;
            strong.context=[CIContext contextWithOptions:nil]; strong.stream=[[SCStream alloc] initWithFilter:filter configuration:config delegate:strong]; NSError *outputError=nil;
            if(![strong.stream addStreamOutput:strong type:SCStreamOutputTypeScreen sampleHandlerQueue:dispatch_get_main_queue() error:&outputError]) {strong.status.stringValue=outputError.localizedDescription ?: @"Could not attach screen capture output."; return;}
            [strong.stream startCaptureWithCompletionHandler:^(NSError *startError){dispatch_async(dispatch_get_main_queue(),^{if(weak.generation==generation && startError) weak.status.stringValue=startError.localizedDescription;});}];
        });
    }];
}
- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)buffer ofType:(SCStreamOutputType)type {
    if(stream!=self.stream || !CMSampleBufferIsValid(buffer)) return;
    CVPixelBufferRef pixels=CMSampleBufferGetImageBuffer(buffer); if(!pixels) return;
    CIImage *ci=[CIImage imageWithCVPixelBuffer:pixels]; CGImageRef cg=[self.context createCGImage:ci fromRect:ci.extent]; if(!cg) return;
    self.image.image=[[NSImage alloc] initWithCGImage:cg size:NSZeroSize]; CGImageRelease(cg); self.status.hidden=YES;
}
- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error {dispatch_async(dispatch_get_main_queue(),^{if(stream==self.stream) {self.status.hidden=NO;self.status.stringValue=error.localizedDescription;}});}
- (void)windowWillClose:(NSNotification *)note {[self stop];}
- (void)stop {self.generation++; [self.stream stopCaptureWithCompletionHandler:nil]; self.stream=nil; self.window.delegate=nil; [self.window close];self.window=nil;}
@end
