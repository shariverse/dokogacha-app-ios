// アプリアイコンの PNG の下端に、構成の目印の帯（「DEV」「STG」などの文字）を重ねる（Debug・Stg のアイコンに使う）。
//
//   swiftc -O Tools/render_icon_badge.swift -o render_icon_badge
//   ./render_icon_badge [--opaque] <入力.png> <出力.png> <文字> <帯の色> <線の色> <文字の色> <フォント.ttf>
//
// 色は #RRGGBB。帯は横幅いっぱいで、上端に線を引く（ライト・ダークは `ink`、ティントはその灰色）。文字はフォントのファイル（Dokogacha/Resources/Fonts/）で描く
// （SVG の <text> は NSImage で描けないことがあるので、文字だけはここで描く）。
// --opaque を付けると、アルファの無い RGB の PNG にする（ライトの外観。App Store はアルファ付きのアイコンを受け付けない）。

import AppKit
import CoreText
import UniformTypeIdentifiers

/// 帯の高さ・上端の線の太さ・文字の大きさ（1024px のときの値。入力の大きさに合わせて伸び縮みする）
let bandHeight: CGFloat = 232
let borderWidth: CGFloat = 20
let fontSize: CGFloat = 150
let tracking: CGFloat = 12

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func color(_ hex: String) -> CGColor {
    guard hex.count == 7, hex.hasPrefix("#"), let value = Int(hex.dropFirst(), radix: 16) else {
        fail("色は #RRGGBB で指定してください: \(hex)")
    }
    return CGColor(
        srgbRed: CGFloat(value >> 16 & 0xFF) / 255,
        green: CGFloat(value >> 8 & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: 1
    )
}

var arguments = Array(CommandLine.arguments.dropFirst())
let opaque = arguments.first == "--opaque"
if opaque {
    arguments.removeFirst()
}
guard arguments.count == 7 else {
    FileHandle.standardError.write(Data("使い方: render_icon_badge [--opaque] <入力.png> <出力.png> <文字> <帯の色> <線の色> <文字の色> <フォント.ttf>\n".utf8))
    exit(2)
}
let (input, output, text) = (arguments[0], URL(fileURLWithPath: arguments[1]), arguments[2])
let (bandColor, borderColor, textColor) = (color(arguments[3]), color(arguments[4]), color(arguments[5]))
let fontFile = URL(fileURLWithPath: arguments[6])

guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: input) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fail("\(input) を読めませんでした")
}
guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fontFile as CFURL) as? [CTFontDescriptor],
      let descriptor = descriptors.first else {
    fail("\(fontFile.path) のフォントを読めませんでした")
}

let size = image.width
let scale = CGFloat(size) / 1024
guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fail("\(size)px の描画先を作れませんでした")
}
let canvas = CGRect(x: 0, y: 0, width: size, height: size)
context.draw(image, in: canvas)

// 帯（CGContext は左下が原点なので、下端は y = 0）
let band = CGRect(x: 0, y: 0, width: CGFloat(size), height: bandHeight * scale)
context.setFillColor(bandColor)
context.fill(band)
context.setFillColor(borderColor)
context.fill(CGRect(x: 0, y: band.maxY - borderWidth * scale, width: CGFloat(size), height: borderWidth * scale))

// 文字（帯の線より下の面の中央に、字形の外接矩形で合わせる）
let font = CTFontCreateWithFontDescriptor(descriptor, fontSize * scale, nil)
let attributed = NSAttributedString(string: text, attributes: [
    NSAttributedString.Key(kCTFontAttributeName as String): font,
    NSAttributedString.Key(kCTForegroundColorAttributeName as String): textColor,
    NSAttributedString.Key(kCTKernAttributeName as String): tracking * scale
])
let line = CTLineCreateWithAttributedString(attributed)
let glyphBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
let face = CGRect(x: 0, y: 0, width: CGFloat(size), height: band.height - borderWidth * scale)
context.textPosition = CGPoint(
    x: face.midX - glyphBounds.midX,
    y: face.midY - glyphBounds.midY
)
CTLineDraw(line, context)

guard let rendered = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fail("\(output.path) に書き出せませんでした")
}
CGImageDestinationAddImage(destination, rendered, nil)
guard CGImageDestinationFinalize(destination) else {
    fail("\(output.path) を保存できませんでした")
}
