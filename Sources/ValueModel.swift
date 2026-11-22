import CoreGraphics
import CoreImage
import Foundation
import Metal

// MARK: - 表示モード

enum DisplayMode: String, CaseIterable, Identifiable {
    case color
    case value
    case posterize

    var id: String { rawValue }

    var label: String {
        switch self {
        case .color:
            return "カラー"
        case .value:
            return "明度"
        case .posterize:
            return "階調"
        }
    }

    var summary: String {
        switch self {
        case .color:
            return "色をそのまま見る"
        case .value:
            return "色味を落として明暗だけを見る"
        case .posterize:
            return "明暗を数段に整理して大きな形を見る"
        }
    }
}

// MARK: - 描画コンテキスト

/// プレビューの描画と明度の読み取りで同じ CIContext を共有する。
/// 色管理は行わず、カメラの画素値をそのまま扱う（明度フィルタと % 表示を同じ土台に揃えるため）。
final class RenderContext {
    static let shared = RenderContext()

    let ciContext: CIContext
    let commandQueue: MTLCommandQueue?

    private init() {
        let options: [CIContextOption: Any] = [
            .workingColorSpace: NSNull(),
            .cacheIntermediates: false
        ]
        if let device = MTLCreateSystemDefaultDevice() {
            ciContext = CIContext(mtlDevice: device, options: options)
            commandQueue = device.makeCommandQueue()
        } else {
            ciContext = CIContext(options: options)
            commandQueue = nil
        }
    }
}

// MARK: - 画面への当てはめ

/// プレビュー領域いっぱいに映像を広げる（アスペクトフィル）。
/// 表示位置と、画面上の点から画素への変換をここに集約する。
struct PreviewGeometry {
    let imageSize: CGSize
    let viewSize: CGSize

    var scale: CGFloat {
        guard imageSize.width > 0, imageSize.height > 0,
              viewSize.width > 0, viewSize.height > 0 else { return 1 }
        return max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
    }

    var displayedSize: CGSize {
        CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    var offset: CGPoint {
        CGPoint(x: (viewSize.width - displayedSize.width) / 2,
                y: (viewSize.height - displayedSize.height) / 2)
    }

    /// 画面内に収める（照準が枠外へ出ないように）。
    func clampedViewPoint(_ point: CGPoint, margin: CGFloat = 16) -> CGPoint {
        PreviewGeometry.clamped(point, in: viewSize, margin: margin)
    }

    static func clamped(_ point: CGPoint, in size: CGSize, margin: CGFloat = 16) -> CGPoint {
        let minX = min(margin, size.width / 2)
        let maxX = max(size.width - margin, size.width / 2)
        let minY = min(margin, size.height / 2)
        let maxY = max(size.height - margin, size.height / 2)
        return CGPoint(x: min(max(point.x, minX), maxX),
                       y: min(max(point.y, minY), maxY))
    }

    /// 画面上の点（左上原点）→ 元画像の画素座標（CI の左下原点）。
    func imagePoint(forViewPoint point: CGPoint, mirrored: Bool) -> CGPoint {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let s = max(scale, 0.0001)
        let p = clampedViewPoint(point, margin: 0)
        var x = (p.x - offset.x) / s
        let distanceFromTop = (p.y - offset.y) / s
        if mirrored {
            x = imageSize.width - x
        }
        let y = imageSize.height - distanceFromTop
        return CGPoint(x: min(max(x, 0.5), max(imageSize.width - 0.5, 0.5)),
                       y: min(max(y, 0.5), max(imageSize.height - 0.5, 0.5)))
    }

    /// 元画像の画素座標 → 画面上の点（初期位置の決定に使う）。
    func viewPoint(forImagePoint point: CGPoint, mirrored: Bool) -> CGPoint {
        var x = point.x
        if mirrored {
            x = imageSize.width - x
        }
        let distanceFromTop = imageSize.height - point.y
        return CGPoint(x: x * scale + offset.x, y: distanceFromTop * scale + offset.y)
    }
}

enum PreviewLayout {
    static func fillTransform(imageSize: CGSize, targetSize: CGSize) -> CGAffineTransform {
        guard imageSize.width > 0, imageSize.height > 0,
              targetSize.width > 0, targetSize.height > 0 else { return .identity }
        let scale = max(targetSize.width / imageSize.width, targetSize.height / imageSize.height)
        let dx = (targetSize.width - imageSize.width * scale) / 2
        let dy = (targetSize.height - imageSize.height * scale) / 2
        return CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: dx, y: dy))
    }

    /// 映像を目標サイズへアスペクトフィルで当てはめ、その矩形に切り抜く。
    static func fitted(_ image: CIImage, to targetSize: CGSize) -> CIImage {
        let target = CGRect(origin: .zero, size: targetSize)
        let base = ValuePipeline.normalized(image)
        guard base.extent.width > 0, base.extent.height > 0,
              targetSize.width > 0, targetSize.height > 0 else {
            return CIImage(color: CIColor(red: 0.102, green: 0.102, blue: 0.106)).cropped(to: target)
        }
        let placed = base.transformed(by: fillTransform(imageSize: base.extent.size, targetSize: targetSize))
        return placed.cropped(to: target)
    }
}

// MARK: - フィルタと明度

struct ValuePipeline {
    /// Rec.709 の輝度係数。
    static let redWeight: CGFloat = 0.2126
    static let greenWeight: CGFloat = 0.7152
    static let blueWeight: CGFloat = 0.0722

    private var context: CIContext { RenderContext.shared.ciContext }

    /// フィルタを適用する（左右反転は含めない）。画素の範囲は元映像のまま。
    func filtered(_ image: CIImage, mode: DisplayMode, levels: Int) -> CIImage {
        let base = ValuePipeline.normalized(image)
        switch mode {
        case .color:
            return base
        case .value:
            return ValuePipeline.valueOnly(base)
        case .posterize:
            return ValuePipeline.posterized(ValuePipeline.valueOnly(base), levels: levels)
        }
    }

    /// プレビュー・保存の両方で使う最終画像（フィルタ＋左右反転）。
    func composed(_ image: CIImage, mode: DisplayMode, levels: Int, mirrored: Bool) -> CIImage {
        let base = filtered(image, mode: mode, levels: levels)
        return mirrored ? ValuePipeline.mirrored(base) : base
    }

    // MARK: 変換

    static func normalized(_ image: CIImage) -> CIImage {
        let extent = image.extent
        guard extent.origin != .zero else { return image }
        return image.transformed(by: CGAffineTransform(translationX: -extent.origin.x,
                                                       y: -extent.origin.y))
    }

    /// Rec.709 の輝度だけを残した灰色画像。
    static func valueOnly(_ image: CIImage) -> CIImage {
        let luma = CIVector(x: redWeight, y: greenWeight, z: blueWeight, w: 0)
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": luma,
            "inputGVector": luma,
            "inputBVector": luma
        ])
    }

    /// 明暗を段階に丸める（境界線は引かない）。
    static func posterized(_ image: CIImage, levels: Int) -> CIImage {
        let clamped = CGFloat(min(max(levels, 2), 8))
        return image.applyingFilter("CIColorPosterize", parameters: [
            "inputLevels": clamped
        ])
    }

    /// 左右反転。画素の範囲は (0, 0, 幅, 高さ) に戻す。
    static func mirrored(_ image: CIImage) -> CIImage {
        let base = normalized(image)
        let width = base.extent.width
        let transform = CGAffineTransform(scaleX: -1, y: 1)
            .concatenating(CGAffineTransform(translationX: width, y: 0))
        return base.transformed(by: transform)
    }

    // MARK: 明度の読み取り

    /// 指定した画素（左下原点）の明度を 0...1 で返す。
    /// 1×1 ピクセルを RGBA8 として書き出し、Rec.709 の係数で重みづけする。
    func luminance(at pixel: CGPoint, in image: CIImage) -> Double? {
        guard image.extent.width > 0, image.extent.height > 0 else { return nil }
        let rect = CGRect(x: pixel.x.rounded(.down), y: pixel.y.rounded(.down), width: 1, height: 1)
        let clipped = rect.intersection(image.extent)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }

        var bytes = [UInt8](repeating: 0, count: 4)
        let result: Double? = bytes.withUnsafeMutableBytes { raw -> Double? in
            guard let base = raw.baseAddress else { return nil }
            context.render(image,
                           toBitmap: base,
                           rowBytes: 4,
                           bounds: clipped,
                           format: .RGBA8,
                           colorSpace: nil)
            let pointer = base.assumingMemoryBound(to: UInt8.self)
            let red = Double(pointer[0])
            let green = Double(pointer[1])
            let blue = Double(pointer[2])
            let value = (Double(ValuePipeline.redWeight) * red
                         + Double(ValuePipeline.greenWeight) * green
                         + Double(ValuePipeline.blueWeight) * blue) / 255.0
            return min(max(value, 0), 1)
        }
        return result
    }

    /// 0...1 を「30%」の形にする。
    static func percentText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int((value * 100).rounded()))%"
    }
}
