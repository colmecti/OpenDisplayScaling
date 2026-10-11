// SPDX-License-Identifier: MIT
#import "HotKeys.h"
#import <Carbon/Carbon.h>
@interface ODSHotKeys ()
@property EventHandlerRef handler;
@property EventHotKeyRef showKey, dimKey, brightenKey, resetKey;
@end
static OSStatus ODSHandleHotKey(EventHandlerCallRef next,EventRef event,void *context) {
    EventHotKeyID key={0};OSStatus status=GetEventParameter(event,kEventParamDirectObject,typeEventHotKeyID,NULL,sizeof(key),NULL,&key);
    if(status!=noErr || key.signature!='ODSK')return eventNotHandledErr;
    ODSHotKeys *owner=(__bridge ODSHotKeys *)context;if(owner.action)owner.action(key.id);return noErr;
}
@implementation ODSHotKeys
- (BOOL)setEnabled:(BOOL)enabled {
    for(NSValue *value in @[[NSValue valueWithPointer:self.showKey],[NSValue valueWithPointer:self.dimKey],[NSValue valueWithPointer:self.brightenKey],[NSValue valueWithPointer:self.resetKey]]) if(value.pointerValue)UnregisterEventHotKey(value.pointerValue);
    self.showKey=NULL;self.dimKey=NULL;self.brightenKey=NULL;self.resetKey=NULL;
    if(self.handler){RemoveEventHandler(self.handler);self.handler=NULL;}if(!enabled)return YES;
    EventTypeSpec type={kEventClassKeyboard,kEventHotKeyPressed};EventHandlerRef handler=NULL;
    if(InstallEventHandler(GetApplicationEventTarget(),ODSHandleHotKey,1,&type,(__bridge void *)self,&handler)!=noErr)return NO;self.handler=handler;
    UInt32 codes[]={kVK_ANSI_D,kVK_DownArrow,kVK_UpArrow,kVK_ANSI_R};EventHotKeyRef refs[4]={NULL};
    for(NSUInteger i=0;i<4;i++) if(RegisterEventHotKey(codes[i],controlKey|optionKey,(EventHotKeyID){'ODSK',(UInt32)i+1},GetApplicationEventTarget(),0,&refs[i])!=noErr){for(NSUInteger j=0;j<i;j++)UnregisterEventHotKey(refs[j]);RemoveEventHandler(self.handler);self.handler=NULL;return NO;}
    self.showKey=refs[0];self.dimKey=refs[1];self.brightenKey=refs[2];self.resetKey=refs[3];return YES;
}
- (void)dealloc {[self setEnabled:NO];}
@end
