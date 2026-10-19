# Changelog

## 0.4.1 (Revamped) - 2026-10-19

Plus réactif et plus léger :

- Plus aucune animation implicite sur le contour blanc et la flèche : Core
  Animation animait chaque changement pendant 0,25 s, et le contour traînait
  derrière le pointeur à chaque redimensionnement ou morphing.
- L'ombre a une forme fournie (`shadowPath`) : plus de rendu hors écran à
  chaque image pour la calculer.
- Le contour n'est reconstruit que si son apparence change (taille,
  orientation, écran, ombre, cadre), au lieu de l'être à chaque mise en page,
  qui a lieu à chaque mouvement du pointeur. La comparaison n'alloue rien.
- La couche n'est remise au premier plan que si elle ne l'est plus.
- Le masquage du pointeur ne touche UIKit que s'il change.
- Les capacités de l'état du pointeur et les ivars sont cherchées une seule
  fois, au lieu de l'être à chaque mouvement.

## 0.4.0 (Revamped) - 2026-10-19

- **Page de réglages** (Réglages › Arrow, Finally.), une option par fonction
  du curseur, appliquée tout de suite (notification Darwin vers pointeruid) :
  flèche macOS on/off, taille de 0,80 à 2,00 (1,15 par défaut), ombre, secouer
  pour localiser, masquer pendant la frappe, raccourci vers Contrôle du
  pointeur et réinitialisation.
- **Secouer pour localiser** : quatre changements de direction rapides en
  0,8 s font grossir la flèche jusqu'à ×3, puis elle reprend sa taille. Sur
  les iPadOS qui ont leur propre « secouer pour trouver », la flèche suit le
  multiplicateur du système.
- **Masquer pendant la frappe** : la flèche suit aussi les masquages demandés
  par iPadOS (frappe au clavier), plus seulement le masquage automatique
  d'Accessibilité.
- Dépend de PreferenceLoader ; compilé avec le SDK iOS 16.5.

## 0.3.2 (Revamped) - 2026-10-19

- Après installation, mise à jour ou suppression, Sileo (ou Zebra) propose un
  redémarrage partiel (userspace reboot), comme ElleKit : `postinst` et `postrm`
  envoient `finish:usreboot` au gestionnaire de paquets.

## 0.3.1 (Revamped) - 2026-10-19

- Flèche 15 % plus grande (échelle ×1,15, environ 17 pt de haut) : à la
  taille exacte du Mac, elle paraissait un peu petite sur l'iPad 12,9".

## 0.3.0 (Revamped) - 2026-10-19

Fork par NOxygen59, modifications écrites par Claude.

- La flèche de **macOS 26/27** : forme mesurée sur un Mac (plus trapue, coins
  arrondis), à la place de celle de l'ancien macOS.
- **Taille du Mac** : échelle ×1,0 au lieu de ×1,40 (environ 15 pt de haut
  au lieu de 26).
- Contour blanc de 1 pt **à l'extérieur** de la flèche noire, comme sur macOS,
  et **ombre douce** orientée vers le bas de l'interface.
- iPadOS **16** minimum (`firmware (>= 16.0)`, cible Theos 16.0) : l'original
  fonctionne déjà sur iPadOS 16.6.1.
- README en français et en anglais ; l'original chinois est dans
  README.zh-TW.md.

## 0.2.7 - 2026-08-13

- 修正 0.2.6 在橫向外接螢幕多旋轉 90 度的問題。外接 display 的 pointer
  geometry 本身已使用該螢幕的橫向座標，因此現在只對 iPad 內建螢幕套用
  interface-orientation 旋轉；已通過實機外接螢幕驗證。

## 0.2.6 - 2026-08-13

- 修正外接螢幕上的箭頭方向。每個 `PUIDPointerShapeView` 現在各自保存
  pointeruid 回報的 display orientation，不再讓 iPad 主螢幕的全域方向覆蓋
  外接 display；白色外框也改用所屬螢幕的 scale。

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
