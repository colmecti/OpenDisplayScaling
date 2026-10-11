// SPDX-License-Identifier: MIT
#import <Foundation/Foundation.h>
#import "ScalingConfiguration.h"
#import <math.h>
static NSUInteger assertions = 0;
#define CHECK(...) do { assertions++; if (!(__VA_ARGS__)) { fprintf(stderr,"FAIL line %d: %s\n",__LINE__,#__VA_ARGS__); exit(1); } } while(0)

int main(void) {
    @autoreleasepool {
        NSString *error=nil;
        ODSConfiguration *c=[ODSConfiguration configurationWithWidth:@"2560" height:@"1080" refreshRate:165 error:&error];
        CHECK(c != nil && error == nil);
        CHECK(c.width==2560 && c.height==1080 && c.refreshRate==165);
        CHECK(([c.backingModes.firstObject isEqual:@[@5120,@2160]]));
        CHECK(c.backingModes.count >= 5);
        NSMutableSet *seen=[NSMutableSet new];
        for (NSArray *size in c.backingModes) {
            CHECK(![seen containsObject:size]); [seen addObject:size];
            CHECK([size[0] unsignedIntegerValue] <= 5120 && [size[1] unsignedIntegerValue] <= 2160);
            CHECK([size[0] unsignedIntegerValue] % 2 == 0 && [size[1] unsignedIntegerValue] % 2 == 0);
        }
        for (NSString *bad in @[@"",@"-20",@"2560px",@"2560.0",@"1e3",@"+2560",@"999999999999",@"NaN",@"25 60",@"０１２３",@"2559",@"639",@"3074"]) {
            CHECK([ODSConfiguration configurationWithWidth:bad height:@"1080" refreshRate:60 error:&error]==nil);
            CHECK(error.length>0);
        }
        CHECK([ODSConfiguration configurationWithWidth:@" 2560\n" height:@"1080" refreshRate:59.94 error:nil]!=nil);
        CHECK([ODSConfiguration configurationWithWidth:@"1080" height:@"1920" refreshRate:60 error:nil]!=nil);
        CHECK([ODSConfiguration configurationWithWidth:@"3072" height:@"3072" refreshRate:60 error:nil]==nil);
        CHECK([ODSConfiguration configurationWithWidth:@"2560" height:@"1079" refreshRate:60 error:nil]==nil);
        CHECK([ODSConfiguration configurationWithWidth:@"2560" height:@"480" refreshRate:NAN error:nil]==nil);
        CHECK([ODSConfiguration configurationWithWidth:@"2560" height:@"480" refreshRate:INFINITY error:nil]==nil);
        CHECK([ODSConfiguration configurationWithWidth:@"2560" height:@"480" refreshRate:241 error:nil]==nil);
        CHECK([ODSConfiguration configurationWithWidth:@"2560" height:@"480" refreshRate:0 error:nil]==nil);
        CHECK([[ODSConfiguration fromDictionary:c.dictionaryRepresentation].dictionaryRepresentation isEqual:c.dictionaryRepresentation]);
        CHECK([ODSConfiguration fromDictionary:@{@"width":@2560,@"height":@1080}]==nil);
        CHECK([ODSConfiguration fromDictionary:@{@"width":@"2560",@"height":@1080,@"refreshRate":@60}]==nil);
        CHECK([ODSConfiguration fromDictionary:@{@"width":@2560.5,@"height":@1080,@"refreshRate":@60}]==nil);
        NSDictionary *saved=@{@"width":@2560,@"height":@1080,@"pixelWidth":@5120,@"pixelHeight":@2160,@"refreshRate":@60};
        CHECK(ODSModeMatches(2560,1080,5120,2160,59.94,saved));
        CHECK(!ODSModeMatches(2560,1080,2560,1080,60,saved));
        CHECK(!ODSModeMatches(2560,1080,5120,2160,30,saved));
        CHECK(!ODSModeMatches(1920,1080,3840,2160,60,saved));
        CHECK(!ODSModeMatches(2560,1080,5120,2160,60,@{}));
        // Exercise supported boundaries and ladder invariants, not only one monitor.
        for (NSUInteger w=640;w<=3072;w+=128) for (NSUInteger h=480;h<=2160;h+=120) {
            ODSConfiguration *grid=[ODSConfiguration configurationWithWidth:[@(w) stringValue] height:[@(h) stringValue] refreshRate:60 error:nil];
            if (!grid) continue;
            CHECK([grid.backingModes.firstObject[0] unsignedIntegerValue]==w*2);
            CHECK([grid.backingModes.firstObject[1] unsignedIntegerValue]==h*2);
            CHECK(grid.backingModes.count>=5);
        }
        printf("Passed %lu configuration and mode-matching assertions.\n",(unsigned long)assertions);
    }
    return 0;
}
