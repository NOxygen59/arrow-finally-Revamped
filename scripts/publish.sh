#!/usr/bin/env bash
# Builds the tweak and publishes it to the Sileo source (NOxygen59/sileo-repo, GitHub Pages).
#
#   scripts/publish.sh
#
# The .deb goes into the source's debs/ folder and is pushed; a GitHub Action there rebuilds
# Packages and Release, and Sileo sees the new version at its next refresh. Needs Theos
# (THEOS, default ~/theos) and git access to the source repository (gh auth login).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="${SILEO_REPO_DIR:-$ROOT/../sileo-repo}"
export THEOS="${THEOS:-$HOME/theos}"

cd "$ROOT"
make clean package FINALPACKAGE=1 >/dev/null
DEB="$(ls -t packages/*.deb | head -1)"
echo "Paquet : $DEB"

[ -d "$REPO_DIR/.git" ] || git clone https://github.com/NOxygen59/sileo-repo.git "$REPO_DIR"
git -C "$REPO_DIR" pull -q --rebase
cp "$DEB" "$REPO_DIR/debs/"
git -C "$REPO_DIR" add debs
git -C "$REPO_DIR" commit -q -m "$(basename "$DEB")" || { echo "Déjà publié."; exit 0; }
git -C "$REPO_DIR" push -q
echo "Publié : Sileo verra la mise à jour dans une minute environ."
