#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <math.h>
#import <objc/runtime.h>

// Private classes confirmed in iPadOS 17.0 (21A329). Keeping the declarations
// local avoids shipping copied Apple headers.
@interface PSPointerShape : NSObject
@property (nonatomic, readonly) NSInteger shapeType;
+ (instancetype)systemShape;
+ (instancetype)customShapeWithPath:(CGPathRef)path;
@end

@interface PUIDPointerShapeView : UIView
@property (nonatomic, strong) UIColor *shapeMaterialReplacementColor;
- (void)setPointerShape:(PSPointerShape *)shape
               animated:(BOOL)animated
             completion:(id)completion;
- (CGFloat)_axPointerZoomScaleFactor;
- (void)_handleAccessibilityPointerPreferencesDidChange;
@end

@interface PUIDPointerState : NSObject
@property (nonatomic, readonly, getter=isPointerAutoHidden) BOOL pointerAutoHidden;
@end

@interface PUIDPointerRenderingRootViewController : UIViewController
- (BOOL)setPointerState:(PUIDPointerState *)state
                options:(NSUInteger)options
updateHandlerCollection:(id)updateHandlerCollection
                  error:(NSError **)error;
- (void)hidePointerAnimated:(BOOL)animated;
@end

@interface PUIDDisplayContext : NSObject
@property (nonatomic, strong) PUIDPointerRenderingRootViewController *pointerRenderingController;
@end

@interface PUIDPointerController : NSObject
@property (nonatomic, strong) PUIDDisplayContext *activeDisplayContext;
- (void)_handleAccessibilityPointerSizePreferencesDidChange;
@end

static const NSInteger PSPointerShapeTypeSystem = 1;
static const CGFloat ArrowBaseScale = 1.40;

static void *ArrowActiveKey = &ArrowActiveKey;
static void *ArrowScaleKey = &ArrowScaleKey;
static void *ArrowOutlineLayerKey = &ArrowOutlineLayerKey;
static void *PreviousReplacementColorKey = &PreviousReplacementColorKey;

// libAccessibility returns the pointer multiplier as a 32-bit float on
// arm64. Declaring this as CGFloat (double) makes valid values look invalid.
typedef float (*AXPointerSizeMultiplierFunction)(void);
typedef BOOL (*AXPointerAutoHideEnabledFunction)(void);

static CGFloat AccessibilityPointerSizeMultiplier(void) {
    static AXPointerSizeMultiplierFunction function;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        function = reinterpret_cast<AXPointerSizeMultiplierFunction>(
            dlsym(RTLD_DEFAULT, "_AXSPointerSizeMultiplier"));
    });

    CGFloat multiplier = function ? (CGFloat)function() : 1.0;
    if (!isfinite(multiplier) || multiplier < 0.5 || multiplier > 5.0) {
        return 1.0;
    }
    return multiplier;
}

static BOOL AccessibilityPointerAutoHideEnabled(void) {
    static AXPointerAutoHideEnabledFunction function;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        function = reinterpret_cast<AXPointerAutoHideEnabledFunction>(
            dlsym(RTLD_DEFAULT, "_AXSPointerAutoHideEnabled"));
    });
    return function ? function() : NO;
}

static CGPathRef CreateArrowCursorPath(CGFloat scale) {
    CGMutablePathRef path = CGPathCreateMutable();

    // Geometry traced from macOS's NSCursor.arrow. (0, 0) remains the click
    // hotspot while both the fill and outline scale from that same point.
    CGPathMoveToPoint(path, NULL, 0.0, 0.0);
    CGPathAddLineToPoint(path, NULL, 0.0 * scale, 16.1 * scale);
    CGPathAddLineToPoint(path, NULL, 3.5 * scale, 12.7 * scale);
    CGPathAddLineToPoint(path, NULL, 5.4 * scale, 18.5 * scale);
    CGPathAddLineToPoint(path, NULL, 8.9 * scale, 17.1 * scale);
    CGPathAddLineToPoint(path, NULL, 6.8 * scale, 11.7 * scale);
    CGPathAddLineToPoint(path, NULL, 11.6 * scale, 11.7 * scale);
    CGPathCloseSubpath(path);
    return path;
}

static CGFloat ArrowScaleForView(PUIDPointerShapeView *view) {
    CGFloat zoomScale = 1.0;
    if ([view respondsToSelector:@selector(_axPointerZoomScaleFactor)]) {
        zoomScale = [view _axPointerZoomScaleFactor];
    }
    if (!isfinite(zoomScale) || zoomScale <= 0.0) {
        zoomScale = 1.0;
    }
    return ArrowBaseScale * AccessibilityPointerSizeMultiplier() * zoomScale;
}

static PSPointerShape *ArrowPointerShape(CGFloat scale) {
    Class shapeClass = NSClassFromString(@"PSPointerShape");
    if (!shapeClass ||
        ![shapeClass respondsToSelector:@selector(customShapeWithPath:)]) {
        return nil;
    }

    CGPathRef path = CreateArrowCursorPath(scale);
    PSPointerShape *shape = [shapeClass customShapeWithPath:path];
    CGPathRelease(path);
    return shape;
}

static CAShapeLayer *ArrowOutlineLayer(PUIDPointerShapeView *view) {
    CAShapeLayer *layer = objc_getAssociatedObject(view, ArrowOutlineLayerKey);
    if (!layer) {
        layer = [CAShapeLayer layer];
        layer.name = @"ArrowFinally.outline";
        layer.fillColor = UIColor.clearColor.CGColor;
        layer.strokeColor = UIColor.whiteColor.CGColor;
        layer.lineJoin = kCALineJoinMiter;
        layer.lineCap = kCALineCapSquare;
        layer.miterLimit = 8.0;
        layer.zPosition = 1000.0;
        layer.contentsScale = UIScreen.mainScreen.scale;
        [view.layer addSublayer:layer];
        objc_setAssociatedObject(view, ArrowOutlineLayerKey, layer,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return layer;
}

static void UpdateArrowOutline(PUIDPointerShapeView *view) {
    NSNumber *scaleNumber = objc_getAssociatedObject(view, ArrowScaleKey);
    if (!scaleNumber) {
        return;
    }

    CGFloat scale = scaleNumber.doubleValue;
    CAShapeLayer *layer = ArrowOutlineLayer(view);
    CGPathRef path = CreateArrowCursorPath(scale);
    layer.frame = view.bounds;
    layer.path = path;
    layer.lineWidth = MAX(1.25, scale);
    CGPathRelease(path);

    // Internal pointer layers can be reordered during morph animations.
    [view.layer addSublayer:layer];
}

static void RemoveArrowOutline(PUIDPointerShapeView *view) {
    CAShapeLayer *layer = objc_getAssociatedObject(view, ArrowOutlineLayerKey);
    [layer removeFromSuperlayer];
    objc_setAssociatedObject(view, ArrowOutlineLayerKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static UIView *PointerRootViewForController(id controller) {
    Ivar ivar = class_getInstanceVariable([controller class], "_pointerRootView");
    return ivar ? object_getIvar(controller, ivar) : nil;
}

static PUIDPointerShapeView *PointerShapeViewForController(id controller) {
    Ivar ivar = class_getInstanceVariable([controller class], "_pointerShapeView");
    return ivar ? object_getIvar(controller, ivar) : nil;
}

static void SetPointerActuallyHidden(
    PUIDPointerRenderingRootViewController *controller, BOOL hidden) {
    // Use both levels: pointeruid can replace or reconfigure the composition
    // beneath its view controller while an auto-hide animation is running.
    PointerRootViewForController(controller).hidden = hidden;
    controller.view.hidden = hidden;
}

static void RefreshActiveArrow(PUIDPointerShapeView *view) {
    if (!view || !objc_getAssociatedObject(view, ArrowActiveKey)) {
        return;
    }
    Class shapeClass = NSClassFromString(@"PSPointerShape");
    if ([shapeClass respondsToSelector:@selector(systemShape)]) {
        PSPointerShape *systemShape = [shapeClass systemShape];
        [view setPointerShape:systemShape animated:NO completion:nil];
    }
}

%hook PUIDPointerShapeView

- (void)setPointerShape:(PSPointerShape *)shape
               animated:(BOOL)animated
             completion:(id)completion {
    BOOL isSystemShape = shape &&
        [shape respondsToSelector:@selector(shapeType)] &&
        shape.shapeType == PSPointerShapeTypeSystem;

    if (isSystemShape) {
        if (!objc_getAssociatedObject(self, ArrowActiveKey)) {
            id priorColor = self.shapeMaterialReplacementColor ?: NSNull.null;
            objc_setAssociatedObject(self, PreviousReplacementColorKey,
                                     priorColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }

        CGFloat scale = ArrowScaleForView(self);
        PSPointerShape *replacement = ArrowPointerShape(scale);
        if (replacement) {
            objc_setAssociatedObject(self, ArrowActiveKey, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(self, ArrowScaleKey, @(scale),
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            %orig(replacement, animated, completion);
            self.shapeMaterialReplacementColor = UIColor.blackColor;
            UpdateArrowOutline(self);
            return;
        }
    }

    if (objc_getAssociatedObject(self, ArrowActiveKey)) {
        id priorColor = objc_getAssociatedObject(self, PreviousReplacementColorKey);
        self.shapeMaterialReplacementColor = priorColor == NSNull.null ? nil : priorColor;
        objc_setAssociatedObject(self, ArrowActiveKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, ArrowScaleKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, PreviousReplacementColorKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        RemoveArrowOutline(self);
    }

    %orig(shape, animated, completion);
}

- (void)layoutSubviews {
    %orig;
    if (objc_getAssociatedObject(self, ArrowActiveKey)) {
        UpdateArrowOutline(self);
    }
}

- (void)_handleAccessibilityPointerPreferencesDidChange {
    BOOL wasArrowActive =
        objc_getAssociatedObject(self, ArrowActiveKey) != nil;
    %orig;
    if (wasArrowActive) {
        RefreshActiveArrow(self);
    }
}

%end

%hook PUIDPointerRenderingRootViewController

- (BOOL)setPointerState:(PUIDPointerState *)state
                options:(NSUInteger)options
updateHandlerCollection:(id)updateHandlerCollection
                  error:(NSError **)error {
    BOOL succeeded = %orig(state, options, updateHandlerCollection, error);
    if (succeeded &&
        [state respondsToSelector:@selector(isPointerAutoHidden)]) {
        // iPadOS's native auto-hide leaves a scaled, blurred pointer behind.
        // Hide the complete pointer composition only while the authoritative
        // auto-hidden state is active; normal movement clears it again.
        BOOL shouldFullyHide = state.isPointerAutoHidden &&
            AccessibilityPointerAutoHideEnabled();
        SetPointerActuallyHidden(self, shouldFullyHide);
    }
    return succeeded;
}

%end


%hook PUIDPointerController

- (void)_handleAccessibilityPointerSizePreferencesDidChange {
    %orig;
    // This is the notification actually used for Pointer Size on iPadOS 17.
    // Rebuild the custom path because custom shapes do not receive Apple's
    // automatic system-shape scaling.
    dispatch_async(dispatch_get_main_queue(), ^{
        PUIDPointerRenderingRootViewController *controller =
            self.activeDisplayContext.pointerRenderingController;
        // Changing the Accessibility slider can transiently reuse the hidden
        // state while pointeruid rebuilds its geometry. Make the freshly sized
        // pointer visible; the normal auto-hide timer remains authoritative
        // after this preference update has completed.
        SetPointerActuallyHidden(controller, NO);
        RefreshActiveArrow(PointerShapeViewForController(controller));
    });
}

%end

%ctor {
    @autoreleasepool {
        if (![NSProcessInfo.processInfo.processName isEqualToString:@"pointeruid"] ||
            !NSClassFromString(@"PUIDPointerShapeView") ||
            !NSClassFromString(@"PUIDPointerRenderingRootViewController") ||
            !NSClassFromString(@"PUIDPointerController")) {
            return;
        }
        %init;
    }
}
