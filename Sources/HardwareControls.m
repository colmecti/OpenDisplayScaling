// SPDX-License-Identifier: MIT
#import "HardwareControls.h"
#import <dlfcn.h>
#import <signal.h>

typedef int (*ODSGetBrightness)(CGDirectDisplayID,float *);
typedef int (*ODSSetBrightness)(CGDirectDisplayID,float);
@interface ODSHardwareControls ()
@property(strong) dispatch_queue_t queue;
@end
@implementation ODSHardwareControls
- (instancetype)init {if((self=[super init]))_queue=dispatch_queue_create("io.github.colmecti.ods.ddc",DISPATCH_QUEUE_SERIAL);return self;}
- (BOOL)validFeature:(NSString *)feature {return [@[@"luminance",@"contrast",@"red",@"green",@"blue",@"volume"] containsObject:feature];}
- (NSString *)run:(NSArray<NSString *> *)arguments error:(NSString **)error {
    NSString *path=[NSBundle.mainBundle pathForResource:@"m1ddc" ofType:nil];
    if(!path) {*error=@"The bundled DDC helper is missing.";return nil;}
    NSTask *task=[NSTask new];task.executableURL=[NSURL fileURLWithPath:path];task.arguments=arguments;
    NSPipe *pipe=NSPipe.pipe;task.standardOutput=pipe;task.standardError=pipe;
    NSError *launch=nil;if(![task launchAndReturnError:&launch]){*error=launch.localizedDescription;return nil;}
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,4*NSEC_PER_SEC),dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{if(task.running){[task terminate];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{if(task.running)kill(task.processIdentifier,SIGKILL);});}});
    NSData *data=[pipe.fileHandleForReading readDataToEndOfFile];[task waitUntilExit];
    NSString *output=[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(task.terminationStatus!=0){*error=@"This display or connection did not respond to DDC. Enable DDC/CI in the monitor menu and try a direct cable.";return nil;}return output;
}
- (NSNumber *)number:(NSString *)s {NSScanner *scan=[NSScanner scannerWithString:s ?: @""];NSInteger n=0;if(![scan scanInteger:&n] || !scan.isAtEnd || n<0 || n>65535)return nil;return @(n);}
- (void)read:(NSString *)feature display:(ODSManagedDisplay *)display completion:(void (^)(NSNumber *,NSNumber *,NSString *))completion {
    if(self.readOnly || !display.uuid.length || ![self validFeature:feature]) {completion(nil,nil,@"Hardware controls are unavailable in preview mode or for this selection.");return;}
    if(display.builtIn) {
        void *handle=dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",RTLD_LAZY|RTLD_LOCAL);
        ODSGetBrightness get=handle?(ODSGetBrightness)dlsym(handle,"DisplayServicesGetBrightness"):NULL;float value=0;
        if([feature isEqual:@"luminance"] && get && get(display.displayID,&value)==0 && isfinite(value)) completion(@(lroundf(value*100)),@100,nil);
        else completion(nil,nil,@"This hardware control is unavailable for the built-in display.");if(handle)dlclose(handle);return;
    }
    dispatch_async(self.queue,^{NSString *error=nil;NSNumber *value=[self number:[self run:@[@"display",display.uuid,@"get",feature] error:&error]];NSNumber *max=value?[self number:[self run:@[@"display",display.uuid,@"max",feature] error:&error]]:nil;
        if(!value || !max || max.integerValue<1 || value.integerValue>max.integerValue) error=error ?: @"The monitor returned an invalid DDC range.";
        dispatch_async(dispatch_get_main_queue(),^{completion(error?nil:value,error?nil:max,error);});});
}
- (void)write:(NSString *)feature value:(NSInteger)value maximum:(NSInteger)maximum display:(ODSManagedDisplay *)display completion:(void (^)(NSString *))completion {
    if(self.readOnly || !display.uuid.length || ![self validFeature:feature] || maximum<1 || maximum>65535 || value<0 || value>maximum){completion(@"The hardware value is outside the verified range.");return;}
    if(display.builtIn) {
        void *handle=dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",RTLD_LAZY|RTLD_LOCAL);
        ODSSetBrightness set=handle?(ODSSetBrightness)dlsym(handle,"DisplayServicesSetBrightness"):NULL;
        int error=([feature isEqual:@"luminance"] && set)?set(display.displayID,(float)value/maximum):-1;if(handle)dlclose(handle);
        completion(error?@"macOS could not change hardware brightness.":@"Hardware brightness updated.");return;
    }
    dispatch_async(self.queue,^{NSString *error=nil;[self run:@[@"display",display.uuid,@"set",feature,[NSString stringWithFormat:@"%ld",(long)value]] error:&error];
        NSNumber *actual=error?nil:[self number:[self run:@[@"display",display.uuid,@"get",feature] error:&error]];
        NSString *message=error ?: (actual.integerValue==value && actual?@"Monitor confirmed the hardware value.":@"Command sent, but the monitor did not confirm the requested value.");
        dispatch_async(dispatch_get_main_queue(),^{completion(message);});});
}
@end
