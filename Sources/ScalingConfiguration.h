// SPDX-License-Identifier: MIT
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Logical desktop dimensions. Rendering uses a 2× framebuffer.
@interface ODSConfiguration : NSObject
@property(nonatomic) NSUInteger width;
@property(nonatomic) NSUInteger height;
@property(nonatomic) double refreshRate;
+ (nullable instancetype)configurationWithWidth:(NSString *)width
                                        height:(NSString *)height
                                   refreshRate:(double)refreshRate
                                         error:(NSString * _Nullable * _Nullable)error;
/// Ordered physical-pixel sizes for the virtual display, preferred mode first.
- (NSArray<NSArray<NSNumber *> *> *)backingModes;
- (NSDictionary *)dictionaryRepresentation;
+ (nullable instancetype)fromDictionary:(NSDictionary *)dictionary;
@end

BOOL ODSModeMatches(NSUInteger width, NSUInteger height, NSUInteger pixelsWide,
                    NSUInteger pixelsHigh, double refresh, NSDictionary *saved);

NS_ASSUME_NONNULL_END
