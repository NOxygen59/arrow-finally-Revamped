# iPadOS 17 system pointer research

## Scope

- Device firmware: iPad mini 6 (`iPad14,1` / `iPad14,2`)
- iPadOS: 17.0 (`21A329`)
- Source: `iPad_Fall_2021_17.0_21A329_Restore.ipsw`
- Comparison target: local Xcode iOS 26.3 Simulator runtime (`23D8133`)

The simulator binary is not identical to device arm64e firmware, but it is enough to identify the high-level implementation change. A device iPadOS 26 IPSW would still be needed before copying offsets or binary code.

## Confirmed iPadOS 17 pipeline

UIKit creates the default style with:

```objc
+[UIPointerStyle systemPointerStyle]
```

Its implementation allocates a `UIPointerStyle`, sets `type = 2`, and sets `options = 0x801`. It does not create the circular shape itself.

`_UIPointerArbiterCore_iOS` resolves the style through:

```objc
-[_UIPointerArbiterCore_iOS _pointerShapeForStyle:region:]
```

When the style has no explicit shape, this method falls back to:

```objc
+[PSPointerShape systemShape]
```

The shape is sent through `PointerUIServices` to the `pointeruid` daemon, where `PUIDPointerShapeView` renders it.

Relevant private APIs present in iPadOS 17:

```objc
+[PSPointerShape systemShape]
+[PSPointerShape customShapeWithPath:]
+[PSPointerShape customShapeWithPath:usesEvenOddFillRule:]
-[PUIDPointerShapeView setPointerShape:animated:completion:]
-[PUIDPointerShapeView expectedShapeBoundsForPointerShape:]
```

`PSPointerShape` type values found in the binaries:

```text
0 Unknown
1 System
2 Circle
3 RoundedRect
4 CustomPath
5 ElasticRect
```

## iPadOS 17 versus iPadOS 26

In iPadOS 17, `-[PUIDPointerShapeView expectedShapeBoundsForPointerShape:]` handles a System shape by taking `systemPointerSize` and returning a centered square. This is the circular free-space pointer.

In iOS 26.3, the same method has a new `_UIPlasmaEnabled()` branch. For a System shape it loads four different bounds values, applies a pointer-size multiplier, and selects different bounds according to interface orientation.

The iOS 26 renderer also adds a path setup branch in:

```objc
-[PUIDPointerShapeView _setupAndUnhidePointerViewForPointerShape:]
```

For a System shape with Plasma enabled, it loads a built-in `CGPath`, scales it, rotates it for the four interface orientations, and installs it as a layer mask. No new arrow image exists in `PointerUIServices.framework/Assets.car`; the path is code/data driven.

Therefore the iPadOS 26 arrow is not a renamed PNG and not merely a preference hidden in iPadOS 17. The relevant rendering branch and path data were added after iPadOS 17.

## Best backport design

The lowest-risk proof of concept is a rootless ElleKit tweak injected only into the `pointeruid` daemon.

Hook:

```objc
-[PUIDPointerShapeView setPointerShape:animated:completion:]
```

Behavior:

1. If `shape.shapeType == 1` (System), create a macOS-style arrow `CGPath` and replace the argument with `+[PSPointerShape customShapeWithPath:]`.
2. Pass all other shape types through unchanged.
3. Call the original implementation.

This preserves the existing iPadOS 17 custom-path renderer and keeps normal UIKit pointer regions:

- free space: arrow;
- text: native beam;
- controls and app icons: native rounded/morphing effects;
- custom app pointer styles: unchanged.

This is preferable to injecting a hook into every application process or patching UIKitCore. The first device test still needs to confirm daemon injection, landscape orientation, hotspot alignment, accessibility pointer settings, and pointer morph transitions.

## Alternative fallback

If `pointeruid` rejects daemon injection or its custom-path transition is visually wrong, hook `_UIPointerArbiterCore_iOS` in UIKit processes and replace only the result of `_pointerShapeForStyle:region:` when it resolves to the System shape. This is broader and more likely to interact with app jailbreak detection, so it should not be the first approach.

## Analysis artifacts

The IPSW, dyld shared cache, and extracted framework binaries were used only
for analysis and are intentionally excluded from the release repository. The
tweak does not contain or redistribute Apple firmware or framework binaries.
