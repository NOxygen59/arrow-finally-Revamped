> [!WARNING]
> **Projet personnel « vibecodé ».** Toutes les modifications de ce fork ont été écrites par **Claude** (Anthropic, via Claude Code), à la demande spécifique de [@NOxygen59](https://github.com/NOxygen59), pour **son appareil précis** :
>
> **iPad Pro 12,9" 5ᵉ génération (puce M1) — 512 Go de stockage, 8 Go de RAM — iOS 16.6.1, jailbreak Dopamine (rootless) + TrollStore.**
>
> Rien n'est testé ni prévu pour un autre appareil. Pas de support, pas de feuille de route : c'est un dépôt personnel, publié pour pouvoir reprendre le travail plus tard.

**Fork** de [andyching168/arrow-finally](https://github.com/andyching168/arrow-finally) par Andy Ching. **Licence :** celle d'origine, MIT (voir [LICENSE](LICENSE)). Aucune licence n'est ajoutée.

[English](README.en.md) · [中文（原始說明）](README.zh-TW.md)

# Arrow, Finally. Revamped

Remplace le pointeur rond d'iPadOS par la **flèche de macOS 26/27**, **à la taille du Mac**, sur un iPad jailbreaké. Les formes natives sont conservées : curseur texte, aimantation sur les boutons, déformation sur les icônes, pointeurs propres aux apps.

Le tweak n'est injecté que dans `pointeruid`, ni dans les apps ni dans les fichiers système.

## Différences avec l'original

| | Arrow, Finally. (original) | Revamped |
|---|---|---|
| **Flèche** | Forme de l'ancien curseur macOS, coins vifs | Forme de **macOS 26/27**, mesurée sur un Mac : plus trapue, coins arrondis |
| **Taille** | ×1,40, environ 26 pt de haut | **×1,15, un peu plus que sur Mac**, environ 17 pt de haut, contour compris |
| **Contour** | Blanc, à cheval sur le bord (mange le noir) | Blanc, **à l'extérieur** de la flèche, 1 pt, comme sur macOS |
| **Ombre** | Aucune | **Ombre douce**, toujours vers le bas de l'interface, même en paysage |
| **iOS minimum** | iPadOS 17 | **iPadOS 16** (testé sur 16.6.1) |

Pour la taille, un point d'iPad Pro est presque aussi grand à l'écran qu'un point de Mac (environ 132 contre 127 points par pouce). À ×1,0 la flèche aurait la même taille physique que sur un MacBook ; elle est 15 % plus grande, car on regarde l'iPad de plus loin. Le réglage « Taille du pointeur » d'iPadOS s'applique toujours par-dessus.

Le dessin d'Apple n'est pas copié : la forme est redessinée en vecteurs à partir de mesures du curseur affiché sur un Mac (les images de macOS ne sont pas redistribuables).

## Compatibilité

- **L'original 0.2.7 marche** sur iPad Pro 12,9" (M1), iPadOS 16.6.1, Dopamine rootless, ElleKit : il a suffi de l'installer puis de redémarrer. Revamped 0.3.0 est validé sur cet iPad.
- **Testé par l'auteur d'origine (version 0.2.7) :** iPad mini 6, iPadOS 17.0.
- **Minimum déclaré :** iPadOS 16.0. Les autres versions ne sont pas testées.

## Installer

### Avec Sileo (recommandé)

Ajouter la source :

```text
https://noxygen59.github.io/sileo-repo/
```

ou ouvrir [sileo://source/https://noxygen59.github.io/sileo-repo/](sileo://source/https://noxygen59.github.io/sileo-repo/) depuis l'iPad. Installer ensuite **Arrow, Finally. Revamped**, puis accepter le **redémarrage partiel** que Sileo propose à la fin. Les mises à jour arrivent toutes seules dans Sileo.

### À la main

Prendre le `.deb` dans les [Releases](https://github.com/NOxygen59/arrow-finally-Revamped/releases), l'ouvrir avec Sileo ou Filza, puis :

```sh
sudo killall pointeruid
```

Si le curseur ne change pas, faire un userspace reboot depuis Dopamine.

## Réglages

**Réglages › Arrow, Finally.** propose une option par fonction du curseur. Tout s'applique immédiatement, sans redémarrage.

| Réglage | Effet | Par défaut |
|---|---|---|
| **Flèche macOS** | Active ou désactive la flèche (le rond d'iPadOS revient) | Activé |
| **Taille** | De 0,80 à 2,00 ; 1,00 = la taille du curseur sur Mac | 1,15 |
| **Ombre** | Ombre douce sous la flèche | Activé |
| **Secouer pour localiser** | Secouer vite la souris ou le trackpad fait grossir la flèche le temps de la retrouver, comme sur Mac | Activé |
| **Masquer pendant la frappe** | La flèche disparaît quand iPadOS masque le pointeur pendant la frappe, et revient quand la souris bouge | Activé |
| **Curseur texte › Toujours vertical** | Redresse la barre de texte quand iPadOS l'affiche couchée (Live Text dans les images) | Activé |

La page contient aussi un raccourci vers **Accessibilité › Contrôle du pointeur** (taille et masquage automatique d'iPadOS, qui s'ajoutent aux réglages du tweak) et un bouton **Réinitialiser les réglages**.

## Désinstaller

Supprimer **Arrow, Finally. Revamped** dans Sileo, ou :

```sh
sudo dpkg -r com.andyching.ipadarrowcursor
sudo killall pointeruid
```

## Compiler

Prérequis : macOS, [Theos](https://theos.dev) et un SDK iPhoneOS.

```sh
THEOS=~/theos make clean package FINALPACKAGE=1    # → packages/*.deb
scripts/publish.sh                                   # compile, et publie dans la source Sileo
```

`scripts/publish.sh` copie le `.deb` dans [NOxygen59/sileo-repo](https://github.com/NOxygen59/sileo-repo) et le pousse. GitHub y régénère l'index de la source, et Sileo voit la mise à jour.

| | |
|---|---|
| Identifiant | `com.andyching.ipadarrowcursor` (celui de l'original : la version Revamped le remplace) |
| Cible | iOS 16.0 et plus, rootless, `arm64` + `arm64e` |
| Injection | `pointeruid` seulement (et la page de réglages dans l'app Réglages) |
| Dépendances | ElleKit, PreferenceLoader |

## Versions

| Revamped | Basé sur | Contenu |
|---|---|---|
| 0.4.2 | Arrow, Finally. 0.2.7 | Barre de texte redressée sur Live Text (texte des images), réglage « Toujours vertical » |
| 0.4.1 | Arrow, Finally. 0.2.7 | Plus réactif et plus léger : plus d'animations parasites, ombre sans rendu hors écran, contour reconstruit seulement quand il change |
| 0.4.0 | Arrow, Finally. 0.2.7 | Page de réglages, secouer pour localiser, masquer pendant la frappe, taille et ombre réglables |
| 0.3.2 | Arrow, Finally. 0.2.7 | Sileo propose le redémarrage partiel après installation, comme ElleKit |
| 0.3.1 | Arrow, Finally. 0.2.7 | Flèche 15 % plus grande (×1,15) |
| 0.3.0 | Arrow, Finally. 0.2.7 | Flèche de macOS 26/27, taille du Mac, contour extérieur, ombre, iOS 16 |

L'analyse technique de l'auteur d'origine est dans [RESEARCH.md](RESEARCH.md) (en chinois).
