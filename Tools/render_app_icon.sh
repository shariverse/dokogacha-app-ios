#!/bin/bash
set -euo pipefail

# アプリアイコンの元データ（SVG）を PNG に書き出す。
#
#   Tools/render_app_icon.sh             採用した案（docs/design/app-icon/）から、Release・Debug・Stg のアイコンセットを書き出す
#   Tools/render_app_icon.sh candidates  候補（docs/design/app-icon/candidates/<案>/）の PNG を書き出す
#
# 元データは外観ごとに 1 枚ずつの SVG（light.svg・dark.svg・tinted.svg）。
# ライトは背景あり・アルファなし（App Store はアルファ付きのアイコンを受け付けない）、
# ダーク・ティントは背景を透過にする（OS が暗い背景を敷き、ティントは明るさに応じて色を乗せる）。
# 書き出しには Tools/render_svg.swift（macOS の NSImage）を使うので、SVG は図形だけで描く。
# Debug・Stg のアイコンは、Release の PNG の下端に構成の目印の帯（文字）を Tools/render_icon_badge.swift で重ねる。
# どのアイコンセットを使うかは Configs/<構成>.xcconfig の DG_APP_ICON_NAME で決まる（AppIconConfigurationTests が突き合わせる）。
# 書き出したら PNG を開いて見た目を確かめ、差分をコミットする。

ROOT_DIR="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

SOURCE_DIR="docs/design/app-icon"
ASSETS_DIR="Dokogacha/Assets.xcassets"
SIZE=1024

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
RENDER_SVG="$WORK/render_svg"
xcrun swiftc -O Tools/render_svg.swift -o "$RENDER_SVG"
RENDER_BADGE="$WORK/render_icon_badge"

# ライトの PNG にアルファが残っていたら止める（審査で拒まれる）
assert_opaque() {
    if [ "$(sips -g hasAlpha "$1" | awk '/hasAlpha/ { print $2 }')" != "no" ]; then
        echo "$1 にアルファチャンネルが残っています。" >&2
        exit 1
    fi
}

# <元データのフォルダ> <出力先のフォルダ> <ファイル名の接頭辞>
# light.svg → <接頭辞>.png・dark.svg → <接頭辞>-Dark.png・tinted.svg → <接頭辞>-Tinted.png
render_appearances() {
    local source="$1" output="$2" prefix="$3"
    for appearance in light dark tinted; do
        if [ ! -f "$source/$appearance.svg" ]; then
            echo "$source/$appearance.svg がありません。" >&2
            exit 1
        fi
    done
    mkdir -p "$output"
    "$RENDER_SVG" --opaque "$source/light.svg" "$output/$prefix.png" "$SIZE"
    "$RENDER_SVG" "$source/dark.svg" "$output/$prefix-Dark.png" "$SIZE"
    "$RENDER_SVG" "$source/tinted.svg" "$output/$prefix-Tinted.png" "$SIZE"
    assert_opaque "$output/$prefix.png"
}

# <アイコンセットのフォルダ>
# 外観ごとの 3 枚（AppIcon.png・AppIcon-Dark.png・AppIcon-Tinted.png）を指す Contents.json を書く
write_contents_json() {
    cat > "$1/Contents.json" <<'JSON'
{
  "images" : [
    {
      "filename" : "AppIcon.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "filename" : "AppIcon-Dark.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "tinted"
        }
      ],
      "filename" : "AppIcon-Tinted.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON
}

# <アイコンセットの名前> <元データのフォルダ>
# アセットカタログの <名前>.appiconset に、外観ごとの 3 枚と Contents.json を書き出す
render_icon_set() {
    local name="$1" source="$2"
    local output="$ASSETS_DIR/$name.appiconset"
    render_appearances "$source" "$output" AppIcon
    write_contents_json "$output"
    echo "$output に書き出しました"
}

# 目印の文字のフォント（見出しの書体。Dokogacha/Resources/Fonts/）
BADGE_FONT="Dokogacha/Resources/Fonts/MochiyPopOne-Regular.ttf"

# <アイコンセットの名前> <元のアイコンセットの名前> <文字> <ライトとダークの帯の色> <文字の色> <ティントの帯の色> <ティントの文字の色>
# 元のアイコンセットの 3 枚の下端に目印の帯を重ねて、<名前>.appiconset に書き出す。
# 色は docs/spec/design/tokens.json の値。帯の上端の線は ink（ティントは墨線と同じ灰色 #222222）
render_badged_icon_set() {
    local name="$1" base="$ASSETS_DIR/$2.appiconset" text="$3"
    local band="$4" foreground="$5" tinted_band="$6" tinted_foreground="$7"
    local output="$ASSETS_DIR/$name.appiconset"
    if [ ! -x "$RENDER_BADGE" ]; then
        xcrun swiftc -O Tools/render_icon_badge.swift -o "$RENDER_BADGE"
    fi
    mkdir -p "$output"
    "$RENDER_BADGE" --opaque "$base/AppIcon.png" "$output/AppIcon.png" "$text" "$band" "#2B2118" "$foreground" "$BADGE_FONT"
    "$RENDER_BADGE" "$base/AppIcon-Dark.png" "$output/AppIcon-Dark.png" "$text" "$band" "#2B2118" "$foreground" "$BADGE_FONT"
    "$RENDER_BADGE" "$base/AppIcon-Tinted.png" "$output/AppIcon-Tinted.png" "$text" "$tinted_band" "#222222" "$tinted_foreground" "$BADGE_FONT"
    assert_opaque "$output/AppIcon.png"
    write_contents_json "$output"
    echo "$output に書き出しました"
}

case "${1:-}" in
    candidates)
        found=0
        for candidate in "$SOURCE_DIR"/candidates/*/; do
            [ -d "$candidate" ] || continue
            render_appearances "${candidate%/}" "${candidate%/}" icon
            echo "${candidate%/} に書き出しました"
            found=1
        done
        if [ "$found" = 0 ]; then
            echo "$SOURCE_DIR/candidates/ に案がありません。" >&2
            exit 1
        fi
        ;;
    "")
        # Release（App Store）のアイコン。AppStore/app.json の appIcon が AppIcon.appiconset/AppIcon.png を指す
        render_icon_set AppIcon "$SOURCE_DIR"
        # Debug（開発・Emulator）: 墨色（ink）の帯に黄（accent.secondary）の「DEV」
        render_badged_icon_set AppIcon-Debug AppIcon DEV "#2B2118" "#FFC93C" "#222222" "#FFFFFF"
        # Stg（TestFlight）: 黄（accent.secondary）の帯に墨色（ink）の「STG」
        render_badged_icon_set AppIcon-Stg AppIcon STG "#FFC93C" "#2B2118" "#CACACA" "#222222"
        ;;
    *)
        echo "使い方: $0 [candidates]" >&2
        exit 2
        ;;
esac
