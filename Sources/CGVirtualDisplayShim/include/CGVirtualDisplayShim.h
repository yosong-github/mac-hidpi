#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const HDVirtualDisplayErrorDomain;
extern NSString *const HDVirtualModeWidthKey;
extern NSString *const HDVirtualModeHeightKey;
extern NSString *const HDVirtualModeRefreshKey;

typedef NS_ENUM(NSInteger, HDVirtualDisplayErrorCode) {
    HDVirtualDisplayErrorAPIUnavailable = 1,
    HDVirtualDisplayErrorInvalidMode = 2,
    HDVirtualDisplayErrorCreateFailed = 3,
    HDVirtualDisplayErrorApplyFailed = 4,
    HDVirtualDisplayErrorNoDisplayID = 5,
    HDVirtualDisplayErrorNotMainThread = 6,
};

/// Owns one private `CGVirtualDisplay`. Releasing the object removes the virtual display.
@interface HDVirtualDisplay : NSObject

@property (nonatomic, readonly) CGDirectDisplayID displayID;
@property (nonatomic, readonly, copy) NSString *name;

+ (BOOL)isAPIAvailable;

/// `modes` entries use `HDVirtualModeWidthKey`, `HDVirtualModeHeightKey`, and `HDVirtualModeRefreshKey`.
/// Width and height are passed through to `CGVirtualDisplayMode` unchanged.
- (nullable instancetype)initWithName:(NSString *)name
                         maxPixelsWide:(uint32_t)maxPixelsWide
                         maxPixelsHigh:(uint32_t)maxPixelsHigh
                      widthMillimeters:(double)widthMillimeters
                     heightMillimeters:(double)heightMillimeters
                              vendorID:(uint32_t)vendorID
                             productID:(uint32_t)productID
                             serialNum:(uint32_t)serialNum
                                 hiDPI:(BOOL)hiDPI
                                 modes:(NSArray<NSDictionary<NSString *, NSNumber *> *> *)modes
                                 error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END
