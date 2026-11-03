#import "CGVirtualDisplayShim.h"

NSString *const HDVirtualDisplayErrorDomain = @"HDVirtualDisplayErrorDomain";
NSString *const HDVirtualModeWidthKey = @"width";
NSString *const HDVirtualModeHeightKey = @"height";
NSString *const HDVirtualModeRefreshKey = @"refreshRate";

// Private CoreGraphics classes. Selectors match the class-dump used by Chromium's
// virtual_display_mac_util.mm and have stayed stable from macOS 12 through macOS 26.
@interface CGVirtualDisplayMode : NSObject
@property (readonly, nonatomic) unsigned int width;
@property (readonly, nonatomic) unsigned int height;
@property (readonly, nonatomic) double refreshRate;
- (instancetype)initWithWidth:(unsigned int)width
                       height:(unsigned int)height
                  refreshRate:(double)refreshRate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property (retain, nonatomic) NSArray *modes;
@property (nonatomic) unsigned int hiDPI;
@end

@interface CGVirtualDisplayDescriptor : NSObject
@property (nonatomic) unsigned int maxPixelsWide;
@property (nonatomic) unsigned int maxPixelsHigh;
@property (nonatomic) CGSize sizeInMillimeters;
@property (nonatomic) unsigned int vendorID;
@property (nonatomic) unsigned int productID;
@property (nonatomic) unsigned int serialNum;
@property (retain, nonatomic) NSString *name;
@property (nonatomic) CGPoint redPrimary;
@property (nonatomic) CGPoint greenPrimary;
@property (nonatomic) CGPoint bluePrimary;
@property (nonatomic) CGPoint whitePoint;
@property (retain, nonatomic) dispatch_queue_t queue;
@end

@interface CGVirtualDisplay : NSObject
@property (readonly, nonatomic) unsigned int displayID;
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@end

@implementation HDVirtualDisplay {
    CGVirtualDisplay *_display;
    NSString *_name;
}

+ (BOOL)isAPIAvailable {
    return NSClassFromString(@"CGVirtualDisplay") != Nil &&
           NSClassFromString(@"CGVirtualDisplayDescriptor") != Nil &&
           NSClassFromString(@"CGVirtualDisplaySettings") != Nil &&
           NSClassFromString(@"CGVirtualDisplayMode") != Nil;
}

- (CGDirectDisplayID)displayID {
    return _display.displayID;
}

- (NSString *)name {
    return _name;
}

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
                                 error:(NSError *_Nullable *_Nullable)error {
    self = [super init];
    if (!self) {
        return nil;
    }
    if (![NSThread isMainThread]) {
        [self fail:HDVirtualDisplayErrorNotMainThread
           message:@"CGVirtualDisplay must be created on the main thread."
             error:error];
        return nil;
    }
    if (![HDVirtualDisplay isAPIAvailable]) {
        [self fail:HDVirtualDisplayErrorAPIUnavailable
           message:@"CGVirtualDisplay is not available in this CoreGraphics."
             error:error];
        return nil;
    }
    if (maxPixelsWide == 0 || maxPixelsHigh == 0 || modes.count == 0) {
        [self fail:HDVirtualDisplayErrorInvalidMode message:@"Virtual display mode list is empty." error:error];
        return nil;
    }

    CGVirtualDisplayDescriptor *descriptor = [[CGVirtualDisplayDescriptor alloc] init];
    if (!descriptor) {
        [self fail:HDVirtualDisplayErrorCreateFailed message:@"CGVirtualDisplayDescriptor init failed." error:error];
        return nil;
    }
    descriptor.name = name;
    descriptor.maxPixelsWide = maxPixelsWide;
    descriptor.maxPixelsHigh = maxPixelsHigh;
    descriptor.sizeInMillimeters = CGSizeMake(widthMillimeters, heightMillimeters);
    descriptor.vendorID = vendorID;
    descriptor.productID = productID;
    descriptor.serialNum = serialNum;
    descriptor.queue = dispatch_get_main_queue();
    // sRGB-ish primaries. Leaving these at (0, 0) makes WindowServer reject the display.
    descriptor.redPrimary = CGPointMake(0.6797, 0.3203);
    descriptor.greenPrimary = CGPointMake(0.2559, 0.6983);
    descriptor.bluePrimary = CGPointMake(0.1494, 0.0557);
    descriptor.whitePoint = CGPointMake(0.3125, 0.3291);

    NSMutableArray *modeObjects = [NSMutableArray arrayWithCapacity:modes.count];
    for (NSDictionary<NSString *, NSNumber *> *entry in modes) {
        unsigned int width = entry[HDVirtualModeWidthKey].unsignedIntValue;
        unsigned int height = entry[HDVirtualModeHeightKey].unsignedIntValue;
        double refresh = entry[HDVirtualModeRefreshKey].doubleValue;
        if (width == 0 || height == 0 || width > maxPixelsWide || height > maxPixelsHigh) {
            [self fail:HDVirtualDisplayErrorInvalidMode
               message:[NSString stringWithFormat:@"Mode %ux%u exceeds the %ux%u framebuffer.", width, height,
                                                  maxPixelsWide, maxPixelsHigh]
                 error:error];
            return nil;
        }
        if (refresh < 1) {
            refresh = 60;
        }
        CGVirtualDisplayMode *mode = [[CGVirtualDisplayMode alloc] initWithWidth:width
                                                                          height:height
                                                                     refreshRate:refresh];
        if (!mode) {
            [self fail:HDVirtualDisplayErrorInvalidMode message:@"CGVirtualDisplayMode init failed." error:error];
            return nil;
        }
        [modeObjects addObject:mode];
    }

    CGVirtualDisplay *display = [[CGVirtualDisplay alloc] initWithDescriptor:descriptor];
    if (!display) {
        [self fail:HDVirtualDisplayErrorCreateFailed message:@"CGVirtualDisplay initWithDescriptor returned nil." error:error];
        return nil;
    }
    CGVirtualDisplaySettings *settings = [[CGVirtualDisplaySettings alloc] init];
    settings.hiDPI = hiDPI ? 1 : 0;
    settings.modes = modeObjects;
    if (![display applySettings:settings]) {
        [self fail:HDVirtualDisplayErrorApplyFailed message:@"CGVirtualDisplay applySettings returned NO." error:error];
        return nil;
    }
    if (display.displayID == 0) {
        [self fail:HDVirtualDisplayErrorNoDisplayID message:@"Virtual display ID is 0." error:error];
        return nil;
    }

    _display = display;
    _name = [name copy];
    return self;
}

- (void)fail:(HDVirtualDisplayErrorCode)code message:(NSString *)message error:(NSError **)error {
    if (error) {
        *error = [NSError errorWithDomain:HDVirtualDisplayErrorDomain
                                      code:code
                                  userInfo:@{NSLocalizedDescriptionKey : message}];
    }
}

@end
