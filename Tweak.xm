#import <notify.h>
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
@property (nonatomic, readonly) CGPoint modelPointerReferencePosition;
@property (nonatomic, readonly) double shakeToFindPointerSizeMultiplier;
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
// Settings (Réglages › Arrow, Finally. Revamped), read at launch and whenever the
// settings page posts ArrowPrefsChanged; pointeruid runs as mobile, like Settings.
static NSString *const ArrowPrefsDomain = @"com.andyching.ipadarrowcursor";
static const char *const ArrowPrefsChanged = "com.andyching.ipadarrowcursor/reload";
static BOOL ArrowEnabled = YES;
// 1.0 = the arrow's size on a Mac, in points (an iPad Pro point is about as big
// on screen as a Mac's: ~132 vs ~127 points per inch). Default slightly larger
// on the iPad, whose screen is seen from further away than a laptop's.
static const CGFloat ArrowDefaultScale = 1.15;
static CGFloat ArrowUserScale = ArrowDefaultScale;
static BOOL ArrowShadowEnabled = YES;
static BOOL ArrowShakeToLocate = YES;
static BOOL ArrowHideWhileTyping = YES;

// Shake to locate, as on macOS: a quick back-and-forth of the pointer makes the
// arrow grow until the shaking stops. ArrowLocateBoost multiplies the scale.
static CGFloat ArrowLocateBoost = 1.0;
static const CGFloat ArrowLocateMaxBoost = 3.0;
// The white border around the black arrow, outside the arrow, as on macOS.
static const CGFloat ArrowOutlineWidth = 1.0;

static void *ArrowActiveKey = &ArrowActiveKey;
static void *ArrowScaleKey = &ArrowScaleKey;
static void *ArrowOutlineLayerKey = &ArrowOutlineLayerKey;
static void *PreviousReplacementColorKey = &PreviousReplacementColorKey;
static void *ArrowInterfaceOrientationKey = &ArrowInterfaceOrientationKey;
static void *ArrowRenderedOrientationKey = &ArrowRenderedOrientationKey;
static void *ArrowLastShapeWasSystemKey = &ArrowLastShapeWasSystemKey;
static void *ArrowOutlineStateKey = &ArrowOutlineStateKey;

// Pointer shape paths live in a coordinate space whose origin is the pointer
// hotspot and whose axes follow the display, not the interface. The circular
// system shape is rotation invariant, so iPadOS 17 never rotates anything; an
// arrow has to be rotated by hand or it keeps pointing at the physical top-left
// corner of the display in landscape.
static UIInterfaceOrientation ArrowFallbackInterfaceOrientation = UIInterfaceOrientationPortrait;
static FBSOrientationObserver *ArrowOrientationObserver = nil;
static NSHashTable<PUIDPointerShapeView *> *ArrowShapeViews = nil;
// Every shape view that last showed the system shape (enabled or not), so turning
// the arrow back on applies at once.
static NSHashTable<PUIDPointerShapeView *> *ArrowSystemShapeViews = nil;

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
    return ArrowUserScale * ArrowLocateBoost * AccessibilityPointerSizeMultiplier() * zoomScale;
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

        CAShapeLayer *fill = [CAShapeLayer layer];
        fill.name = @"ArrowFinally.fill";
        fill.fillColor = UIColor.blackColor.CGColor;
        fill.strokeColor = nil;
        [layer addSublayer:fill];

        // Standalone layers animate every property change for 0.25 s by default: the white
        // border then trailed behind the arrow on every resize and morph. Never animate.
        NSNull *none = NSNull.null;
        NSDictionary *still = @{@"path": none, @"frame": none, @"bounds": none, @"position": none,
                                @"shadowPath": none, @"shadowOffset": none, @"shadowRadius": none,
                                @"shadowOpacity": none, @"lineWidth": none, @"contentsScale": none,
                                @"hidden": none, @"sublayers": none, @"onOrderIn": none, @"onOrderOut": none};
        layer.actions = still;
        fill.actions = still;

        [view.layer addSublayer:layer];
        objc_setAssociatedObject(view, ArrowOutlineLayerKey, layer,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return layer;
}

/// What the outline was last built for.
typedef struct {
    CGFloat scale;
    NSInteger orientation;
    CGFloat contentsScale;
    BOOL shadow;
    CGRect bounds;
} ArrowOutlineState;

static void UpdateArrowOutline(PUIDPointerShapeView *view) {
    NSNumber *scaleNumber = objc_getAssociatedObject(view, ArrowScaleKey);
    if (!scaleNumber) {
        return;
    }

    CAShapeLayer *layer = ArrowOutlineLayer(view);
    // Internal pointer layers can be reordered during morph animations: keep ours on top,
    // without re-inserting it (which redoes the layer tree) when it already is.
    if (view.layer.sublayers.lastObject != layer) {
        [view.layer addSublayer:layer];
    }

    CGFloat scale = scaleNumber.doubleValue;
    UIScreen *screen = view.window.screen;
    CGFloat contentsScale = screen ? screen.scale : UIScreen.mainScreen.scale;
    UIInterfaceOrientation orientation = InterfaceOrientationForView(view);
    CGRect bounds = view.bounds;

    // layoutSubviews runs on every pointer update: rebuild only when what the arrow looks like
    // actually changed (size, orientation, display, shadow, bounds). The comparison reads
    // the stored state in place, allocating nothing.
    ArrowOutlineState current;
    memset(&current, 0, sizeof current); // padding included, for memcmp
    current.scale = scale;
    current.orientation = (NSInteger)orientation;
    current.contentsScale = contentsScale;
    current.shadow = ArrowShadowEnabled;
    current.bounds = bounds;
    NSValue *stored = objc_getAssociatedObject(view, ArrowOutlineStateKey);
    if (stored) {
        ArrowOutlineState previous;
        [stored getValue:&previous size:sizeof previous];
        if (memcmp(&previous, &current, sizeof current) == 0) {
            return;
        }
    }
    objc_setAssociatedObject(view, ArrowOutlineStateKey,
                             [NSValue valueWithBytes:&current objCType:@encode(ArrowOutlineState)],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    CGPathRef path = CreateArrowCursorPath(scale, orientation);
    CGFloat lineWidth = 2.0 * ArrowOutlineWidth * scale;
    layer.contentsScale = contentsScale;
    layer.frame = bounds;
    layer.path = path;
    layer.lineWidth = lineWidth;

    // The shadow falls toward the bottom of the interface, whatever way the display is turned
    // (the path's space follows the display). Its shape is given (the arrow and its border),
    // so Core Animation doesn't render the layer offscreen to find it on every frame.
    CGFloat angle = ArrowRotationForInterfaceOrientation(orientation);
    CGFloat drop = 0.7 * scale;
    layer.shadowOffset = CGSizeMake(-sin(angle) * drop, cos(angle) * drop);
    layer.shadowRadius = 1.2 * scale;
    layer.shadowOpacity = ArrowShadowEnabled ? 0.35 : 0.0;
    if (ArrowShadowEnabled) {
        CGPathRef border = CGPathCreateCopyByStrokingPath(path, NULL, lineWidth, kCGLineCapRound, kCGLineJoinRound, 0);
        CGMutablePathRef shadow = CGPathCreateMutableCopy(path);
        CGPathAddPath(shadow, NULL, border);
        layer.shadowPath = shadow;
        CGPathRelease(shadow);
        CGPathRelease(border);
    } else {
        layer.shadowPath = NULL;
    }

    CAShapeLayer *fill = (CAShapeLayer *)layer.sublayers.firstObject;
    fill.contentsScale = contentsScale;
    fill.frame = layer.bounds;
    fill.path = path;
    CGPathRelease(path);
}

static void RemoveArrowOutline(PUIDPointerShapeView *view) {
    CAShapeLayer *layer = objc_getAssociatedObject(view, ArrowOutlineLayerKey);
    [layer removeFromSuperlayer];
    objc_setAssociatedObject(view, ArrowOutlineLayerKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, ArrowOutlineStateKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static UIView *PointerRootViewForController(id controller) {
    // Looked up once: this runs on every pointer update.
    static Ivar ivar;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ ivar = class_getInstanceVariable([controller class], "_pointerRootView"); });
    return ivar ? object_getIvar(controller, ivar) : nil;
}

static PUIDPointerShapeView *PointerShapeViewForController(id controller) {
    static Ivar ivar;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ ivar = class_getInstanceVariable([controller class], "_pointerShapeView"); });
    return ivar ? object_getIvar(controller, ivar) : nil;
}

static void SetPointerActuallyHidden(
    PUIDPointerRenderingRootViewController *controller, BOOL hidden) {
    // Use both levels: pointeruid can replace or reconfigure the composition
    // beneath its view controller while an auto-hide animation is running.
    // Called on every pointer update: only touch UIKit when the state actually changes.
    UIView *root = PointerRootViewForController(controller);
    if (root.hidden != hidden) {
        root.hidden = hidden;
    }
    if (controller.view.hidden != hidden) {
        controller.view.hidden = hidden;
    }
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

static NSHashTable<PUIDPointerShapeView *> *SystemShapeViews(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ArrowSystemShapeViews = [NSHashTable weakObjectsHashTable];
    });
    return ArrowSystemShapeViews;
}

/// Asks every view that shows the system shape for it again, so the arrow (or
/// the native circle, when turned off) is rebuilt with the current settings.
static void RefreshAllArrows(void) {
    Class shapeClass = NSClassFromString(@"PSPointerShape");
    if (![shapeClass respondsToSelector:@selector(systemShape)]) {
        return;
    }
    PSPointerShape *systemShape = [shapeClass systemShape];
    for (PUIDPointerShapeView *view in SystemShapeViews().allObjects) {
        [view setPointerShape:systemShape animated:NO completion:nil];
    }
}

static BOOL PreferenceBool(NSString *key, BOOL fallback) {
    id value = CFBridgingRelease(CFPreferencesCopyAppValue(
        (__bridge CFStringRef)key, (__bridge CFStringRef)ArrowPrefsDomain));
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : fallback;
}

static void LoadPreferences(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)ArrowPrefsDomain);
    ArrowEnabled = PreferenceBool(@"enabled", YES);
    ArrowShadowEnabled = PreferenceBool(@"shadow", YES);
    ArrowShakeToLocate = PreferenceBool(@"shakeToLocate", YES);
    ArrowHideWhileTyping = PreferenceBool(@"hideWhileTyping", YES);
    id size = CFBridgingRelease(CFPreferencesCopyAppValue(
        CFSTR("size"), (__bridge CFStringRef)ArrowPrefsDomain));
    CGFloat scale = [size respondsToSelector:@selector(doubleValue)]
        ? [size doubleValue] : ArrowDefaultScale;
    ArrowUserScale = isfinite(scale) ? MIN(MAX(scale, 0.6), 2.5) : ArrowDefaultScale;
}

// MARK: Shake to locate

static CADisplayLink *ArrowLocateLink = nil;
static CFTimeInterval ArrowLastShake = 0.0;

@interface ArrowLocateTicker : NSObject
@end

@implementation ArrowLocateTicker
- (void)tick:(CADisplayLink *)link {
    // Grow while shaking, shrink back half a second after it stops.
    BOOL shaking = CACurrentMediaTime() - ArrowLastShake < 0.5;
    CGFloat target = shaking ? ArrowLocateMaxBoost : 1.0;
    CGFloat step = MIN(1.0, link.duration * (shaking ? 12.0 : 7.0));
    CGFloat next = ArrowLocateBoost + (target - ArrowLocateBoost) * step;
    if (!shaking && next < 1.01) {
        next = 1.0;
        [ArrowLocateLink invalidate];
        ArrowLocateLink = nil;
    }
    if (fabs(next - ArrowLocateBoost) < 0.001) {
        return;
    }
    ArrowLocateBoost = next;
    for (PUIDPointerShapeView *view in ActiveArrowShapeViews().allObjects) {
        RefreshActiveArrow(view);
    }
}
@end

/// Feeds the pointer's position; four quick changes of horizontal direction
/// within 0.8 s, each after at least 30 pt of travel, count as a shake.
static void TrackPointerForShake(CGPoint position) {
    static CGPoint last;
    static BOOL hasLast = NO;
    static int direction = 0;
    static CGFloat travel = 0.0;
    static CFTimeInterval reversals[6];
    static int count = 0;

    if (!ArrowShakeToLocate || !isfinite(position.x) || !isfinite(position.y)) {
        hasLast = NO;
        return;
    }
    if (!hasLast) {
        last = position;
        hasLast = YES;
        return;
    }
    CGFloat dx = position.x - last.x;
    last = position;
    if (fabs(dx) < 1.0) {
        return;
    }
    int now = dx > 0 ? 1 : -1;
    if (now == direction) {
        travel += fabs(dx);
        return;
    }
    CFTimeInterval t = CACurrentMediaTime();
    if (direction != 0 && travel >= 30.0) {
        reversals[count % 6] = t;
        count++;
    }
    direction = now;
    travel = fabs(dx);

    int recent = 0;
    for (int i = 0; i < MIN(count, 6); i++) {
        if (t - reversals[i] < 0.8) {
            recent++;
        }
    }
    if (recent >= 4) {
        ArrowLastShake = t;
        if (!ArrowLocateLink) {
            static ArrowLocateTicker *ticker;
            ticker = [ArrowLocateTicker new];
            ArrowLocateLink = [CADisplayLink displayLinkWithTarget:ticker
                                                          selector:@selector(tick:)];
            [ArrowLocateLink addToRunLoop:NSRunLoop.mainRunLoop
                                  forMode:NSRunLoopCommonModes];
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
        [SystemShapeViews() addObject:self];
    } else {
        [SystemShapeViews() removeObject:self];
    }

    if (isSystemShape && ArrowEnabled) {
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
    // This runs on every pointer move: what the state class offers is looked up once.
    static BOOL hasAutoHidden, hasShakeMultiplier, hasPosition;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class cls = [state class];
        hasAutoHidden = [cls instancesRespondToSelector:@selector(isPointerAutoHidden)];
        hasShakeMultiplier = [cls instancesRespondToSelector:@selector(shakeToFindPointerSizeMultiplier)];
        hasPosition = [cls instancesRespondToSelector:@selector(modelPointerReferencePosition)];
    });
    if (succeeded && hasAutoHidden) {
        // iPadOS's native auto-hide leaves a scaled, blurred pointer behind.
        // Hide the complete pointer composition only while the authoritative
        // auto-hidden state is active; normal movement clears it again.
        // iPadOS also auto-hides the pointer on its own while you type; with
        // "Masquer pendant la frappe" the arrow follows every such request.
        BOOL shouldFullyHide = state.isPointerAutoHidden &&
            (ArrowHideWhileTyping || AccessibilityPointerAutoHideEnabled());
        SetPointerActuallyHidden(self, shouldFullyHide);
    }
    // Shake to locate. iPadOS releases with their own shake-to-find put a size
    // multiplier in the state: the arrow (a custom path, which that multiplier
    // doesn't reach) follows it. Elsewhere the tweak detects the shake itself.
    if (succeeded && ArrowEnabled && ArrowShakeToLocate) {
        if (hasShakeMultiplier) {
            CGFloat native = state.shakeToFindPointerSizeMultiplier;
            native = isfinite(native) ? MIN(MAX(native, 1.0), ArrowLocateMaxBoost) : 1.0;
            if (fabs(native - ArrowLocateBoost) > 0.01) {
                ArrowLocateBoost = native;
                for (PUIDPointerShapeView *view in ActiveArrowShapeViews().allObjects) {
                    RefreshActiveArrow(view);
                }
            }
        } else if (hasPosition) {
            TrackPointerForShake(state.modelPointerReferencePosition);
        }
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

        // Settings: read now, and again whenever the settings page changes one.
        LoadPreferences();
        int token;
        notify_register_dispatch(ArrowPrefsChanged, &token, dispatch_get_main_queue(), ^(int t) {
            (void)t;
            LoadPreferences();
            RefreshAllArrows();
        });
    }
}
