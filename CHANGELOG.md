# Changelog

## 0.2.5 - 2026-08-11

- 修正橫向與上下顛倒時箭頭不會跟著介面旋轉的問題。指標路徑現在依照
  `FBSOrientationObserver` 回報的介面方向，繞著點擊熱點旋轉，與 iPadOS 26
  對內建箭頭路徑套用的角度一致。

## 0.2.4 - 2026-08-10

Initial public release as **Arrow, Finally.**

- Replaces the iPadOS 17 free-space circular pointer with a macOS-style arrow.
- Adds a black fill and path-matched white outline.
- Follows the Accessibility pointer-size preference.
- Fully hides the custom cursor when auto-hide is enabled.
- Preserves native text, control-hover, icon-morphing, and custom pointer shapes.
- Supports rootless `arm64` and `arm64e` jailbreaks through ElleKit.
