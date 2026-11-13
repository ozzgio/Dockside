#import "NativeVirtualDisplay.h"
// Runtime lookup lets unsupported macOS versions fall back to the companion driver.
@interface DSDescriptor : NSObject
@property unsigned int vendorID, productID, serialNum, serialNumber, maxPixelsWide, maxPixelsHigh;
@property(strong) NSString *name;
@property CGSize sizeInMillimeters;
@property CGPoint redPrimary, greenPrimary, bluePrimary, whitePoint;
@property(strong) dispatch_queue_t queue;
@end
@interface DSMode : NSObject
- (id)initWithWidth:(unsigned int)width height:(unsigned int)height refreshRate:(double)rate;
@end
@interface DSSettings : NSObject
@property(strong) NSArray *modes;
@property unsigned int hiDPI;
@end
@interface DSDisplay : NSObject
- (id)initWithDescriptor:(id)descriptor;
- (BOOL)applySettings:(id)settings;
@property(readonly) unsigned int displayID;
@end
NSObject *DSCreateVirtualDisplay(unsigned int width, unsigned int height) {
    if (width < 1 || height < 1 || width > 4096 || height > 4096) return nil;
    @try {
        DSDescriptor *descriptor = [NSClassFromString(@"CGVirtualDisplayDescriptor") new];
        DSSettings *settings = [NSClassFromString(@"CGVirtualDisplaySettings") new];
        Class modeClass = NSClassFromString(@"CGVirtualDisplayMode");
        Class displayClass = NSClassFromString(@"CGVirtualDisplay");
        if (!descriptor || !settings || !modeClass || !displayClass) return nil;
        descriptor.name = @"Dockside Native USB";
        descriptor.vendorID = 0x4453; descriptor.productID = 1;
        descriptor.serialNum = 0x44534E31; descriptor.serialNumber = 0x44534E31;
        descriptor.maxPixelsWide = width; descriptor.maxPixelsHigh = height;
        // A nominal 100-DPI desktop avoids macOS rejecting tiny high-density virtual panels.
        descriptor.sizeInMillimeters = CGSizeMake(325, 183);
        descriptor.redPrimary = CGPointMake(.64, .33);
        descriptor.greenPrimary = CGPointMake(.30, .60);
        descriptor.bluePrimary = CGPointMake(.15, .06);
        descriptor.whitePoint = CGPointMake(.3127, .3290);
        descriptor.queue = dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0);
        DSMode *mode = [[modeClass alloc] initWithWidth:width height:height refreshRate:60];
        if (!mode) return nil;
        settings.modes = @[mode]; settings.hiDPI = 0;
        DSDisplay *display = [[displayClass alloc] initWithDescriptor:descriptor];
        if (!display || ![display applySettings:settings] || !display.displayID) return nil;
        return display;
    } @catch (NSException *exception) { return nil; }
}
unsigned int DSVirtualDisplayID(NSObject *display) {
    @try { return [(DSDisplay *)display displayID]; } @catch (NSException *exception) { return 0; }
}
