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

// FrontBoardServices is already linked by pointeruid. This is the same
// orientation source iPadOS 26 uses from -[PUIDPointerShapeView
// _didUpdateToOrientation:duration:rotationDirection:].
@interface FBSOrientationUpdate : NSObject
@property (nonatomic, readonly) NSInteger orientation;
@property (nonatomic, readonly) double duration;
@end

@interface FBSOrientationObserver : NSObject
@property (nonatomic, copy) void (^handler)(FBSOrientationUpdate *update);
- (NSInteger)activeInterfaceOrientation;
- (void)invalidate;
@end

static const NSInteger PSPointerShapeTypeSystem = 1;
// 1.0 = the arrow's size on a Mac, in points (an iPad Pro point is about as big
// on screen as a Mac's: ~132 vs ~127 points per inch).
static const CGFloat ArrowBaseScale = 1.0;
// The white border around the black arrow, outside the arrow, as on macOS.
static const CGFloat ArrowOutlineWidth = 1.0;

static void *ArrowActiveKey = &ArrowActiveKey;
static void *ArrowScaleKey = &ArrowScaleKey;
static void *ArrowOutlineLayerKey = &ArrowOutlineLayerKey;
static void *PreviousReplacementColorKey = &PreviousReplacementColorKey;
static void *ArrowInterfaceOrientationKey = &ArrowInterfaceOrientationKey;
static void *ArrowRenderedOrientationKey = &ArrowRenderedOrientationKey;

// Pointer shape paths live in a coordinate space whose origin is the pointer
// hotspot and whose axes follow the display, not the interface. The circular
// system shape is rotation invariant, so iPadOS 17 never rotates anything; an
// arrow has to be rotated by hand or it keeps pointing at the physical top-left
// corner of the display in landscape.
static UIInterfaceOrientation ArrowFallbackInterfaceOrientation = UIInterfaceOrientationPortrait;
static FBSOrientationObserver *ArrowOrientationObserver = nil;
static NSHashTable<PUIDPointerShapeView *> *ArrowShapeViews = nil;

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

// Angles taken from the rotation table iPadOS 26 indexes by interface
// orientation when it transforms its built-in arrow path. Note that
// UIInterfaceOrientationLandscapeLeft is 4 and LandscapeRight is 3.
static CGFloat ArrowRotationForInterfaceOrientation(UIInterfaceOrientation orientation) {
    switch (orientation) {
        case UIInterfaceOrientationPortraitUpsideDown:  // 2
            return -M_PI;
        case UIInterfaceOrientationLandscapeRight:      // 3
            return M_PI_2;
        case UIInterfaceOrientationLandscapeLeft:       // 4
            return -M_PI_2;
        default:
            return 0.0;
    }
}

static UIInterfaceOrientation InterfaceOrientationForView(
    PUIDPointerShapeView *view) {
    UIScreen *screen = view.window.screen;
    if (screen && screen != UIScreen.mainScreen) {
        // External-display pointer geometry is already expressed in that
        // display's landscape-oriented coordinate space. Applying the iPad's
        // physical-panel correction here rotates the arrow a second time.
        return UIInterfaceOrientationPortrait;
    }

    NSNumber *orientation = objc_getAssociatedObject(
        view, ArrowInterfaceOrientationKey);
    return orientation
        ? (UIInterfaceOrientation)orientation.integerValue
        : ArrowFallbackInterfaceOrientation;
}

// A polygon with each corner rounded by its own radius (CGPathAddArcToPoint).
static void AddRoundedPolygon(CGMutablePathRef path, const CGPoint *points,
                              const CGFloat *radii, size_t count) {
    const CGPoint first = points[0];
    const CGPoint last = points[count - 1];
    CGPathMoveToPoint(path, NULL, (first.x + last.x) / 2.0, (first.y + last.y) / 2.0);
    for (size_t i = 0; i < count; i++) {
        const CGPoint corner = points[i];
        const CGPoint next = points[(i + 1) % count];
        CGPathAddArcToPoint(path, NULL, corner.x, corner.y, next.x, next.y, radii[i]);
    }
    CGPathCloseSubpath(path);
}

static CGPathRef CreateArrowCursorPath(
    CGFloat scale, UIInterfaceOrientation orientation) {
    CGMutablePathRef path = CGPathCreateMutable();

    // macOS 26/27's arrow (NSCursor.arrow), measured from its rendering on a
    // Mac in points, with its rounded corners: the black arrow only, the white
    // border is drawn outside it. (0, 0) is the tip and the click hotspot; the
    // fill and the border scale from that point.
    const CGPoint points[] = {
        {0.00 * scale, 0.00 * scale},    // tip
        {0.00 * scale, 11.80 * scale},   // bottom of the left edge
        {2.95 * scale, 9.75 * scale},    // notch, left of the tail
        {5.05 * scale, 14.65 * scale},   // tail, bottom left
        {7.05 * scale, 13.95 * scale},   // tail, bottom right
        {5.00 * scale, 8.95 * scale},    // notch, under the wing
        {8.35 * scale, 8.55 * scale},    // wing
    };
    const CGFloat radii[] = {
        0.35 * scale, 0.60 * scale, 0.30 * scale, 0.60 * scale,
        0.60 * scale, 0.30 * scale, 0.60 * scale,
    };
    AddRoundedPolygon(path, points, radii, sizeof(points) / sizeof(points[0]));

    CGFloat angle = ArrowRotationForInterfaceOrientation(orientation);
    if (angle == 0.0) {
        return path;
    }

    // Rotate around (0, 0) so the hotspot stays on the arrow tip.
    CGAffineTransform rotation = CGAffineTransformMakeRotation(angle);
    CGPathRef rotated = CGPathCreateCopyByTransformingPath(path, &rotation);
    CGPathRelease(path);
    return rotated;
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

static PSPointerShape *ArrowPointerShape(
    CGFloat scale, UIInterfaceOrientation orientation) {
    Class shapeClass = NSClassFromString(@"PSPointerShape");
    if (!shapeClass ||
        ![shapeClass respondsToSelector:@selector(customShapeWithPath:)]) {
        return nil;
    }

    CGPathRef path = CreateArrowCursorPath(scale, orientation);
    PSPointerShape *shape = [shapeClass customShapeWithPath:path];
    CGPathRelease(path);
    return shape;
}

// The arrow as macOS draws it, over pointeruid's own rendering of the shape:
// a white border (the outline layer: stroked twice the border width, filled
// white), the black arrow on top of it (a sublayer), and a soft shadow.
static CAShapeLayer *ArrowOutlineLayer(PUIDPointerShapeView *view) {
    CAShapeLayer *layer = objc_getAssociatedObject(view, ArrowOutlineLayerKey);
    if (!layer) {
        layer = [CAShapeLayer layer];
        layer.name = @"ArrowFinally.outline";
        layer.fillColor = UIColor.whiteColor.CGColor;
        layer.strokeColor = UIColor.whiteColor.CGColor;
        layer.lineJoin = kCALineJoinRound;
        layer.lineCap = kCALineCapRound;
        layer.zPosition = 1000.0;
        layer.shadowColor = UIColor.blackColor.CGColor;
        layer.shadowOpacity = 0.35;

        CAShapeLayer *fill = [CAShapeLayer layer];
        fill.name = @"ArrowFinally.fill";
        fill.fillColor = UIColor.blackColor.CGColor;
        fill.strokeColor = nil;
        [layer addSublayer:fill];

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
    UIScreen *screen = view.window.screen;
    CGFloat contentsScale = screen ? screen.scale : UIScreen.mainScreen.scale;
    UIInterfaceOrientation orientation = InterfaceOrientationForView(view);
    CGPathRef path = CreateArrowCursorPath(scale, orientation);
    layer.contentsScale = contentsScale;
    layer.frame = view.bounds;
    layer.path = path;
    layer.lineWidth = 2.0 * ArrowOutlineWidth * scale;

    // The shadow falls toward the bottom of the interface, whatever way the
    // display is turned (the path's space follows the display).
    CGFloat angle = ArrowRotationForInterfaceOrientation(orientation);
    CGFloat drop = 0.7 * scale;
    layer.shadowOffset = CGSizeMake(-sin(angle) * drop, cos(angle) * drop);
    layer.shadowRadius = 1.2 * scale;

    CAShapeLayer *fill = (CAShapeLayer *)layer.sublayers.firstObject;
    fill.contentsScale = contentsScale;
    fill.frame = layer.bounds;
    fill.path = path;
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

static NSHashTable<PUIDPointerShapeView *> *ActiveArrowShapeViews(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ArrowShapeViews = [NSHashTable weakObjectsHashTable];
    });
    return ArrowShapeViews;
}

static void RefreshArrowsUsingFallbackOrientation(void) {
    for (PUIDPointerShapeView *view in ActiveArrowShapeViews().allObjects) {
        // A display-specific update is authoritative. The global observer is
        // only a compatibility fallback for views that have not received one.
        if (!objc_getAssociatedObject(view, ArrowInterfaceOrientationKey)) {
            RefreshActiveArrow(view);
        }
    }
}

static BOOL IsSupportedInterfaceOrientation(NSInteger orientation) {
    switch (orientation) {
        case UIInterfaceOrientationPortrait:
        case UIInterfaceOrientationPortraitUpsideDown:
        case UIInterfaceOrientationLandscapeLeft:
        case UIInterfaceOrientationLandscapeRight:
            return YES;
        default:
            return NO;
    }
}

static void ApplyFallbackInterfaceOrientation(NSInteger orientation) {
    if (!IsSupportedInterfaceOrientation(orientation) ||
        orientation == ArrowFallbackInterfaceOrientation) {
        return;
    }
    ArrowFallbackInterfaceOrientation = (UIInterfaceOrientation)orientation;
    RefreshArrowsUsingFallbackOrientation();
}

static void StartObservingInterfaceOrientation(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class observerClass = NSClassFromString(@"FBSOrientationObserver");
        if (!observerClass) {
            return;
        }

        ArrowOrientationObserver = [[observerClass alloc] init];
        if ([ArrowOrientationObserver
                respondsToSelector:@selector(activeInterfaceOrientation)]) {
            NSInteger current = [ArrowOrientationObserver activeInterfaceOrientation];
            if (IsSupportedInterfaceOrientation(current)) {
                ArrowFallbackInterfaceOrientation =
                    (UIInterfaceOrientation)current;
            }
        }

        ArrowOrientationObserver.handler = ^(FBSOrientationUpdate *update) {
            NSInteger orientation = update.orientation;
            // The handler runs on FrontBoardServices' own queue.
            dispatch_async(dispatch_get_main_queue(), ^{
                ApplyFallbackInterfaceOrientation(orientation);
            });
        };
    });
}

%hook PUIDPointerShapeView

- (void)setPointerShape:(PSPointerShape *)shape
               animated:(BOOL)animated
             completion:(id)completion {
    BOOL isSystemShape = shape &&
        [shape respondsToSelector:@selector(shapeType)] &&
        shape.shapeType == PSPointerShapeTypeSystem;

    if (isSystemShape) {
        StartObservingInterfaceOrientation();

        if (!objc_getAssociatedObject(self, ArrowActiveKey)) {
            id priorColor = self.shapeMaterialReplacementColor ?: NSNull.null;
            objc_setAssociatedObject(self, PreviousReplacementColorKey,
                                     priorColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }

        CGFloat scale = ArrowScaleForView(self);
        PSPointerShape *replacement = ArrowPointerShape(
            scale, InterfaceOrientationForView(self));
        if (replacement) {
            UIInterfaceOrientation renderedOrientation =
                InterfaceOrientationForView(self);
            [ActiveArrowShapeViews() addObject:self];
            objc_setAssociatedObject(self, ArrowActiveKey, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(self, ArrowScaleKey, @(scale),
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(self, ArrowRenderedOrientationKey,
                                     @(renderedOrientation),
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
        objc_setAssociatedObject(self, ArrowRenderedOrientationKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        RemoveArrowOutline(self);
        [ActiveArrowShapeViews() removeObject:self];
    }

    %orig(shape, animated, completion);
}

- (void)_didUpdateToOrientation:(NSInteger)orientation
                       duration:(double)duration
              rotationDirection:(NSInteger)rotationDirection {
    %orig;
    if (!IsSupportedInterfaceOrientation(orientation)) {
        return;
    }

    // pointeruid owns one shape view per display context. Keeping this value
    // on the view prevents the built-in iPad and an external display from
    // overwriting each other's orientation.
    void (^applyOrientation)(void) = ^{
        objc_setAssociatedObject(self, ArrowInterfaceOrientationKey,
                                 @(orientation),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        RefreshActiveArrow(self);
    };
    if (NSThread.isMainThread) {
        applyOrientation();
    } else {
        dispatch_async(dispatch_get_main_queue(), applyOrientation);
    }
}

- (void)layoutSubviews {
    %orig;
    if (objc_getAssociatedObject(self, ArrowActiveKey)) {
        UIInterfaceOrientation effectiveOrientation =
            InterfaceOrientationForView(self);
        NSNumber *renderedOrientation = objc_getAssociatedObject(
            self, ArrowRenderedOrientationKey);
        if (!renderedOrientation ||
            renderedOrientation.integerValue != effectiveOrientation) {
            // A newly attached external-display view may not have a window
            // during its first shape update. Rebuild once its UIScreen is
            // known so both the fill and outline use the display coordinates.
            RefreshActiveArrow(self);
            return;
        }
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
