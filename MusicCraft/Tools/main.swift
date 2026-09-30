import Foundation
import ImageIO
import UniformTypeIdentifiers

// Генерирует иконку приложения 1024×1024.
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL,
                                           UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ArtKit.appIcon(size: 1024), nil)
CGImageDestinationFinalize(dest)
