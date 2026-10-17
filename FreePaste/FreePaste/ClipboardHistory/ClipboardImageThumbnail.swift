import AppKit
import ImageIO

struct ClipboardImagePreview {
    let data: Data
    let originalPixelSize: CGSize
}

enum ClipboardImageThumbnail {
    static let storedMaximumPixelDimension = 512
    static let previewMaximumPixelDimension = 1_600

    static func makePreview(
        from data: Data,
        maximumPixelDimension: Int = storedMaximumPixelDimension
    ) -> ClipboardImagePreview? {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, [
                kCGImageSourceShouldCache: false,
            ] as CFDictionary),
            let originalPixelSize = pixelSize(of: source),
            let image = makeCGImage(from: source, maximumPixelDimension: maximumPixelDimension),
            let encodedData = jpegData(from: image)
        else {
            return nil
        }

        return ClipboardImagePreview(
            data: encodedData,
            originalPixelSize: originalPixelSize
        )
    }

    static func makeNSImage(
        from data: Data,
        maximumPixelDimension: Int
    ) -> NSImage? {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, [
                kCGImageSourceShouldCache: false,
            ] as CFDictionary),
            let image = makeCGImage(from: source, maximumPixelDimension: maximumPixelDimension)
        else {
            return nil
        }
        return NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )
    }

    private static func makeCGImage(
        from source: CGImageSource,
        maximumPixelDimension: Int
    ) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maximumPixelDimension),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func pixelSize(of source: CGImageSource) -> CGSize? {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
            let height = properties[kCGImagePropertyPixelHeight] as? NSNumber
        else {
            return nil
        }
        return CGSize(width: width.doubleValue, height: height.doubleValue)
    }

    private static func jpegData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            "public.jpeg" as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.72] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

@MainActor
final class ClipboardThumbnailCache {
    static let shared = ClipboardThumbnailCache()

    private let cache = NSCache<NSUUID, NSImage>()

    private init() {
        cache.countLimit = 128
        cache.totalCostLimit = 64 * 1_048_576
    }

    func image(for id: UUID, data: Data) -> NSImage? {
        let key = id as NSUUID
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let image = ClipboardImageThumbnail.makeNSImage(
            from: data,
            maximumPixelDimension: ClipboardImageThumbnail.storedMaximumPixelDimension
        ) else {
            return nil
        }
        let cost = max(1, Int(image.size.width * image.size.height * 4))
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }

    func removeImage(for id: UUID) {
        cache.removeObject(forKey: id as NSUUID)
    }
}
