# Arrow, Finally.

把 iPadOS 17 在空白區域顯示的圓形指標，替換成接近 macOS 外觀的黑色箭頭與白色描邊。

此 tweak 只注入 `pointeruid`，不會注入每一個 App，也不會修改系統檔案。文字游標、按鈕吸附、App 圖示變形與 App 自訂指標會繼續使用 iPadOS 原生效果。

## 功能

- macOS 風格箭頭，點擊熱點位於箭頭左上角。
- 黑色填滿與沿箭頭路徑繪製的白色描邊。
- 箭頭會依各螢幕的介面方向旋轉（直向、橫向、上下顛倒）。
- 支援「輔助使用 → 指標控制 → 指標大小」。
- 支援「自動隱藏指標」，隱藏後不殘留模糊箭頭。
- 保留文字 I-beam、控制項 hover 與 App 自訂指標。
- Rootless 封裝，同時包含 `arm64` 與 `arm64e`。

## 相容性

已實機測試：

- iPad mini 6（`iPad14,1`／`iPad14,2`）
- iPadOS 17.0（`21A329`）
- Dopamine rootless jailbreak
- ElleKit
- 橫向外接螢幕上的箭頭方向

其他 iPadOS 15–17 版本具有相同的主要 private class，但尚未實機驗證。iPadOS 更新可能改變 private API，因此不保證跨版本相容。

## 安裝

最新版套件位於：

```text
release/com.andyching.ipadarrowcursor_0.2.7_iphoneos-arm64.deb
```

可以用 Sileo、Zebra 或 Filza 開啟 `.deb` 安裝，也可以複製到裝置後在 NewTerm 執行：

```sh
sudo dpkg -i /path/to/com.andyching.ipadarrowcursor_0.2.7_iphoneos-arm64.deb
sudo killall pointeruid
```

移動滑鼠後 `pointeruid` 應會自動重新啟動。若沒有恢復，請從 Dopamine 執行 userspace reboot。

## 設定

不需要額外的偏好設定頁面。請直接使用：

```text
設定 → 輔助使用 → 指標控制
```

目前支援原生「指標大小」與「自動隱藏指標」設定。

## 已知問題

- 在「設定」內拖動指標大小滑桿時，指標可能暫時消失；停止調整並再次移動滑鼠後會恢復。這不影響儲存後的尺寸或一般使用。
- 只有 iPad mini 6／iPadOS 17.0 經過實機驗證。
- 這是 private API tweak；升級 iPadOS 前應先停用或移除。

## 移除

在套件管理器移除 **Arrow, Finally.**，或執行：

```sh
sudo dpkg -r com.andyching.ipadarrowcursor
sudo killall pointeruid
```

移除後會恢復 iPadOS 原本的圓形指標，沒有系統檔案需要還原。

## 從原始碼編譯

需求：

- macOS 或 Linux
- Theos
- 可用的 iPhoneOS SDK

在專案根目錄執行：

```sh
THEOS=/path/to/theos make clean package FINALPACKAGE=1
```

產生的套件會位於 `packages/`。目前設定如下：

- Package ID：`com.andyching.ipadarrowcursor`
- Target：iOS 15.0 以上
- Scheme：rootless
- Architectures：`arm64 arm64e`
- Injection filter：`pointeruid`

## 專案結構

```text
.
├── Makefile                    Theos build 設定
├── Tweak.xm                    tweak 實作
├── ArrowFinally.plist          pointeruid 注入篩選器
├── control                     Debian 套件資訊
├── CHANGELOG.md                版本紀錄
├── LICENSE                     MIT License
├── RESEARCH.md                 iPadOS 17/26 指標管線研究
└── release/
    └── com.andyching.ipadarrowcursor_0.2.7_iphoneos-arm64.deb
```

## 0.2.7 發佈資訊

- SHA-256：`928c2f9457844eaccf6382d5e0076a6b5eb3ebf350da0c09ae2bafc19e35f76d`
- 套件架構：`iphoneos-arm64`
- 內含 Mach-O 架構：`arm64 arm64e`
- 安裝位置：`/var/jb/Library/MobileSubstrate/DynamicLibraries/`
- 依賴：`firmware (>= 15.0), ellekit`

### 發佈前已完成

- Release build 成功。
- `.deb` 結構與 rootless 安裝路徑已核對。
- dylib 包含 `arm64`、`arm64e` 並具有 code signature。
- iPad mini 6／iPadOS 17.0 已確認箭頭、指標大小與自動隱藏功能。
- iPad mini 6／iPadOS 17.0 已確認直向與橫向的箭頭方向。
- 橫向外接螢幕已實機確認不再被額外旋轉 90 度。

### 發佈頁建議說明

> Arrow, Finally. replaces the free-space circular pointer on jailbroken iPadOS 17 with a macOS-style arrow. It supports Accessibility pointer sizing and auto-hide while preserving native text and control hover effects. Built for rootless jailbreaks with ElleKit.

技術分析與實作依據請參閱 [RESEARCH.md](RESEARCH.md)。

## License

[MIT](LICENSE) © 2026 Andy Ching
