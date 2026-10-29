// SVG を正方形の PNG に書き出す（アプリアイコンの元データの書き出しに使う）。
//
//   swiftc -O Tools/render_svg.swift -o render_svg && ./render_svg [--opaque] <入力.svg> <出力.png> <一辺の px>
//
// macOS の NSImage で SVG を描く。<text>・フィルター・CSS は描けないことがあるので、元データは図形だけで描く。
// --opaque を付けると、アルファの無い RGB の PNG にする（App Store はアルファ付きのアイコンを受け付けない）。
// そのとき塗られていない（透けている）画素があれば止める（背景の描き忘れが黒い面になって書き出されるのを防ぐ）。
// 付けないと、透過を残した RGBA の PNG にする（ダーク・ティントの外観は背景を透過にする）。

import AppKit
import UniformTypeIdentifiers

var arguments = Array(CommandLine.arguments.dropFirst())
let opaque = arguments.first == "--opaque"
if opaque {
    arguments.removeFirst()
}
guard arguments.count == 3, let size = Int(arguments[2]), size > 0 else {
    FileHandle.standardError.write(Data("使い方: render_svg [--opaque] <入力.svg> <出力.png> <一辺の px>\n".utf8))
    exit(2)
}
let input = arguments[0]
let output = URL(fileURLWithPath: arguments[1])

guard let image = NSImage(contentsOfFile: input), image.isValid else {
    FileHandle.standardError.write(Data("\(input) を読めませんでした\n".utf8))
    exit(1)
}
guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write(Data("\(size)px の描画先を作れませんでした\n".utf8))
    exit(1)
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()

guard var rendered = context.makeImage() else {
    FileHandle.standardError.write(Data("\(input) を描けませんでした\n".utf8))
    exit(1)
}
if opaque {
    // 描いた画素のアルファがすべて 255 か確かめてから、アルファの無い画像に描き直す
    let pixels = UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self), count: context.bytesPerRow * size)
    for row in 0..<size {
        for column in 0..<size where pixels[row * context.bytesPerRow + column * 4 + 3] != 255 {
            FileHandle.standardError.write(Data("\(input) に塗られていない画素があります（\(column), \(row)）。背景を描いてください\n".utf8))
            exit(1)
        }
    }
    guard let opaqueContext = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        FileHandle.standardError.write(Data("\(size)px の描画先を作れませんでした\n".utf8))
        exit(1)
    }
    opaqueContext.draw(rendered, in: CGRect(x: 0, y: 0, width: size, height: size))
    rendered = opaqueContext.makeImage()!
}
guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    FileHandle.standardError.write(Data("\(output.path) に書き出せませんでした\n".utf8))
    exit(1)
}
CGImageDestinationAddImage(destination, rendered, nil)
guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write(Data("\(output.path) を保存できませんでした\n".utf8))
    exit(1)
}
