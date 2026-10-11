// SPDX-License-Identifier: MIT
#import "ScalingConfiguration.h"
#import <math.h>

static BOOL ODSParseDimension(NSString *text, NSUInteger *out) {
    if (![text isKindOfClass:NSString.class]) return NO;
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!trimmed.length || trimmed.length > 5) return NO;
    if ([trimmed rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet]].location != NSNotFound) return NO;
    *out = trimmed.integerValue;
    return YES;
}

@implementation ODSConfiguration
+ (instancetype)configurationWithWidth:(NSString *)width height:(NSString *)height
                            refreshRate:(double)refreshRate error:(NSString **)error {
    NSUInteger w = 0, h = 0;
    NSString *problem = nil;
    if (!ODSParseDimension(width, &w) || !ODSParseDimension(height, &h))
        problem = @"Enter whole numbers for width and height.";
    else if (w < 640 || h < 480 || w > 3072 || h > 3072)
        problem = @"Choose a width from 640–3072 and a height from 480–3072.";
    else if (w % 2 || h % 2)
        problem = @"Use even numbers for both dimensions.";
    else if (w * h * 4 > 24000000)
        problem = @"That size exceeds this release’s 24-million-pixel rendering limit. Try a smaller desktop.";
    else if (!isfinite(refreshRate) || refreshRate < 24 || refreshRate > 240)
        problem = @"Choose a refresh rate between 24 and 240 Hz.";
    if (problem) { if (error) *error = problem; return nil; }
    ODSConfiguration *c = [self new]; c.width = w; c.height = h; c.refreshRate = refreshRate;
    return c;
}
- (NSArray<NSArray<NSNumber *> *> *)backingModes {
    // macOS needs a rich list to synthesize HiDPI variants. A single mode can
    // silently become LoDPI. The preferred, exact backing size MUST come first.
    NSMutableArray *result = [NSMutableArray arrayWithObject:@[@(self.width * 2), @(self.height * 2)]];
    const double ratios[] = {0.90, 0.80, 0.75, 2.0/3.0, 0.50};
    for (NSUInteger i = 0; i < sizeof(ratios)/sizeof(ratios[0]); i++) {
        NSUInteger w = (NSUInteger)(self.width * 2 * ratios[i]) / 8 * 8;
        NSUInteger h = (NSUInteger)(self.height * 2 * ratios[i]) / 2 * 2;
        NSArray *mode = @[@(w), @(h)];
        if (w >= 320 && h >= 240 && ![result containsObject:mode]) [result addObject:mode];
    }
    return result;
}
- (NSDictionary *)dictionaryRepresentation {
    return @{@"width": @(self.width), @"height": @(self.height), @"refreshRate": @(self.refreshRate)};
}
+ (instancetype)fromDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:NSDictionary.class]) return nil;
    id w = dictionary[@"width"], h = dictionary[@"height"], r = dictionary[@"refreshRate"];
    if (![w isKindOfClass:NSNumber.class] || ![h isKindOfClass:NSNumber.class] || ![r isKindOfClass:NSNumber.class]) return nil;
    return [self configurationWithWidth:[w stringValue] height:[h stringValue] refreshRate:[r doubleValue] error:nil];
}
@end

BOOL ODSModeMatches(NSUInteger width, NSUInteger height, NSUInteger pixelsWide,
                    NSUInteger pixelsHigh, double refresh, NSDictionary *saved) {
    if (![saved isKindOfClass:NSDictionary.class]) return NO;
    for (NSString *key in @[@"width", @"height", @"pixelWidth", @"pixelHeight", @"refreshRate"])
        if (![saved[key] isKindOfClass:NSNumber.class]) return NO;
    double expected = [saved[@"refreshRate"] doubleValue];
    return width == [saved[@"width"] unsignedIntegerValue] && height == [saved[@"height"] unsignedIntegerValue]
        && pixelsWide == [saved[@"pixelWidth"] unsignedIntegerValue] && pixelsHigh == [saved[@"pixelHeight"] unsignedIntegerValue]
        && (expected == 0 || fabs(refresh - expected) < 1);
}
