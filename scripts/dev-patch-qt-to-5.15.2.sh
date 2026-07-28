#!/bin/bash -e
# Downgrades Buildroot Qt from 5.15.8 to 5.15.2
# Uses KDE Qt patch collection commits matching v5.15.2 tag
BR="/home/kevin/primemixxx/buildroot/2023.02.11/package/qt5"

# qt5.mk: change version
sed -i 's/^QT5_VERSION = $(QT5_VERSION_MAJOR)\.8$/QT5_VERSION = $(QT5_VERSION_MAJOR).2/' "$BR/qt5.mk"

# qt5base
sed -i 's/^QT5BASE_VERSION = 2ffb7ad8a1079a0444b9c72affe3d19b089b60de$/QT5BASE_VERSION = 40143c189b7c1bf3c2058b77d00ea5c4e3be8b28/' "$BR/qt5base/qt5base.mk"

# qt5declarative
sed -i 's/^QT5DECLARATIVE_VERSION = 51efb2ed2f071beda188270a23ac450fe4b318f7$/QT5DECLARATIVE_VERSION = 104eae5b17b0ec700391e9539ee3a4f638588194/' "$BR/qt5declarative/qt5declarative.mk"

# qt5script
sed -i 's/^QT5SCRIPT_VERSION = 5cec94b2c1503f106f4ef4778d016410ebb86211$/QT5SCRIPT_VERSION = 5da7de1800eee3d604eb7e787b114b47961bffc93/' "$BR/qt5script/qt5script.mk"

# qt5svg
sed -i 's/^QT5SVG_VERSION = 23b8cf7d833c335d7735855570c05e9e0893a9b7$/QT5SVG_VERSION = 52d3788c7b0116ea3db232dccca5f1e3f1e229ac/' "$BR/qt5svg/qt5svg.mk"

# qt5xmlpatterns
sed -i 's/^QT5XMLPATTERNS_VERSION = dfcae10dec8c1c2c544ad0cd303cea113b0af51d$/QT5XMLPATTERNS_VERSION = 50421402f05b3ee3c76c6cff455a69efaf576b6d/' "$BR/qt5xmlpatterns/qt5xmlpatterns.mk"

# qt5tools
sed -i 's/^QT5TOOLS_VERSION = 53ee43a51b5a3de2877dafffc78e71ff55926708$/QT5TOOLS_VERSION = cc52debd905e0ed061290d6fd00a5f1ab67478a5/' "$BR/qt5tools/qt5tools.mk"

# qt5imageformats
sed -i 's/^QT5IMAGEFORMATS_VERSION = b43e31b9f31ec482ddea2066fda7ca9315512815$/QT5IMAGEFORMATS_VERSION = 74a5bc4a45195b876454e596e76cb23aeb365410/' "$BR/qt5imageformats/qt5imageformats.mk"

echo "Qt 5.15.2 patches applied successfully."
echo "Changed:"
grep 'QT5_VERSION\|QT5BASE_VERSION\|QT5DECLARATIVE_VERSION\|QT5SCRIPT_VERSION\|QT5SVG_VERSION\|QT5XMLPATTERNS_VERSION\|QT5TOOLS_VERSION\|QT5IMAGEFORMATS_VERSION' \
  "$BR/qt5.mk" \
  "$BR/qt5base/qt5base.mk" \
  "$BR/qt5declarative/qt5declarative.mk" \
  "$BR/qt5script/qt5script.mk" \
  "$BR/qt5svg/qt5svg.mk" \
  "$BR/qt5xmlpatterns/qt5xmlpatterns.mk" \
  "$BR/qt5tools/qt5tools.mk" \
  "$BR/qt5imageformats/qt5imageformats.mk" | grep -E 'VERSION.*='
