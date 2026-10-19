> [!WARNING]
> **Personal "vibe-coded" project.** Every change in this fork was written by **Claude** (Anthropic, through Claude Code) at the specific request of [@NOxygen59](https://github.com/NOxygen59), for **one specific device**:
>
> **12.9" iPad Pro, 5th generation (M1) — 512 GB storage, 8 GB RAM — iOS 16.6.1, Dopamine (rootless) jailbreak + TrollStore.**
>
> Nothing is tested on, or meant for, any other device. No support, no roadmap: this is a personal repository, published so the work can be picked up again later.

**Fork** of [andyching168/arrow-finally](https://github.com/andyching168/arrow-finally) by Andy Ching. **License:** the original one, MIT (see [LICENSE](LICENSE)). No license is added.

[Français](README.md) · [中文（原始說明）](README.zh-TW.md)

# Arrow, Finally. Revamped

Replaces iPadOS's round pointer with **macOS 26/27's arrow**, **at the Mac's size**, on a jailbroken iPad. Native shapes are kept: the text cursor, snapping to buttons, morphing over icons, and pointers that apps set themselves.

The tweak is injected into `pointeruid` only, not into apps or system files.

## What changed from the original

| | Arrow, Finally. (original) | Revamped |
|---|---|---|
| **Arrow** | Shape of the older macOS cursor, sharp corners | Shape of **macOS 26/27**, measured on a Mac: stubbier, rounded corners |
| **Size** | ×1.40, about 26 pt tall | **×1.15, a little larger than on a Mac**, about 17 pt tall including the border |
| **Border** | White, straddling the edge (covers part of the black) | White, **outside** the arrow, 1 pt, as on macOS |
| **Shadow** | None | **Soft shadow**, always toward the bottom of the interface, landscape included |
| **Minimum iOS** | iPadOS 17 | **iPadOS 16** (tested on 16.6.1) |

On size: an iPad Pro point is about as large on screen as a Mac point (roughly 132 vs 127 points per inch), so at ×1.0 the arrow would have the same physical size as on a MacBook; it is 15% larger, since an iPad is seen from further away. iPadOS's Pointer Size setting still applies on top.

Apple's artwork isn't copied: the shape is redrawn as vectors from measurements of the cursor as a Mac renders it (macOS's images can't be redistributed).

## Compatibility

- **The original 0.2.7 works** on a 12.9" iPad Pro (M1), iPadOS 16.6.1, Dopamine rootless, ElleKit: installing and rebooting was all it took. Revamped 0.3.0 is confirmed working on this iPad.
- **Tested by the original author (version 0.2.7):** iPad mini 6, iPadOS 17.0.
- **Declared minimum:** iPadOS 16.0. Other versions are untested.

## Install

### With Sileo (recommended)

Add the source:

```text
https://noxygen59.github.io/sileo-repo/
```

or open [sileo://source/https://noxygen59.github.io/sileo-repo/](sileo://source/https://noxygen59.github.io/sileo-repo/) on the iPad. Then install **Arrow, Finally. Revamped** and accept the **userspace reboot** Sileo offers at the end. Updates show up in Sileo on their own.

### By hand

Get the `.deb` from the [Releases](https://github.com/NOxygen59/arrow-finally-Revamped/releases), open it with Sileo or Filza, then:

```sh
sudo killall pointeruid
```

If the cursor doesn't change, do a userspace reboot from Dopamine.

## Settings

**Settings › Arrow, Finally.** has one option per thing the cursor does. Everything applies at once, without a reboot.

| Setting | What it does | Default |
|---|---|---|
| **macOS arrow** | Turns the arrow on or off (iPadOS's circle comes back) | On |
| **Size** | 0.80 to 2.00; 1.00 = the cursor's size on a Mac | 1.15 |
| **Shadow** | Soft shadow under the arrow | On |
| **Shake to locate** | Shaking the mouse or trackpad quickly makes the arrow grow until you find it, as on a Mac | On |
| **Hide while typing** | The arrow disappears when iPadOS hides the pointer while you type, and comes back when the mouse moves | On |

The page also links to **Accessibility › Pointer Control** (iPadOS's own size and auto-hide, which apply on top) and has a **Reset settings** button.

## Uninstall

Remove **Arrow, Finally. Revamped** in Sileo, or:

```sh
sudo dpkg -r com.andyching.ipadarrowcursor
sudo killall pointeruid
```

## Build

You need macOS, [Theos](https://theos.dev) and an iPhoneOS SDK.

```sh
THEOS=~/theos make clean package FINALPACKAGE=1    # → packages/*.deb
scripts/publish.sh                                   # builds, then publishes to the Sileo source
```

`scripts/publish.sh` copies the `.deb` into [NOxygen59/sileo-repo](https://github.com/NOxygen59/sileo-repo) and pushes it. GitHub rebuilds the source's index there, and Sileo sees the update.

| | |
|---|---|
| Identifier | `com.andyching.ipadarrowcursor` (the original's: Revamped replaces it) |
| Target | iOS 16.0 and later, rootless, `arm64` + `arm64e` |
| Injection | `pointeruid` only (plus the settings page in the Settings app) |
| Dependencies | ElleKit, PreferenceLoader |

## Versions

| Revamped | Based on | What's new |
|---|---|---|
| 0.4.0 | Arrow, Finally. 0.2.7 | Settings page, shake to locate, hide while typing, adjustable size and shadow |
| 0.3.2 | Arrow, Finally. 0.2.7 | Sileo offers a userspace reboot after installing, as ElleKit does |
| 0.3.1 | Arrow, Finally. 0.2.7 | Arrow 15% larger (×1.15) |
| 0.3.0 | Arrow, Finally. 0.2.7 | macOS 26/27 arrow, Mac size, outside border, shadow, iOS 16 |

The original author's technical notes are in [RESEARCH.md](RESEARCH.md) (in Chinese).
