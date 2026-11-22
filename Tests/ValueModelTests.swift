import CoreGraphics
import CoreImage
import XCTest

/// 明度・座標変換・フィルタの確認。
/// アプリ本体とは別に `Sources/ValueModel.swift` を取り込んで動かす（カメラ不要）。
final class ValueModelTests: XCTestCase {

    // MARK: 明度

    func testLuminanceOfPrimaryColors() {
        let pipeline = ValuePipeline()
        let red = solid(red: 1, green: 0, blue: 0)
        let green = solid(red: 0, green: 1, blue: 0)
        let blue = solid(red: 0, green: 0, blue: 1)

        XCTAssertEqual(pipeline.luminance(at: CGPoint(x: 2, y: 2), in: red) ?? -1,
                       0.2126, accuracy: 0.02)
        XCTAssertEqual(pipeline.luminance(at: CGPoint(x: 2, y: 2), in: green) ?? -1,
                       0.7152, accuracy: 0.02)
        XCTAssertEqual(pipeline.luminance(at: CGPoint(x: 2, y: 2), in: blue) ?? -1,
                       0.0722, accuracy: 0.02)
    }

    func testLuminanceOfExtremes() {
        let pipeline = ValuePipeline()
        XCTAssertEqual(pipeline.luminance(at: CGPoint(x: 1, y: 1), in: solid(red: 1, green: 1, blue: 1)) ?? -1,
                       1.0, accuracy: 0.01)
        XCTAssertEqual(pipeline.luminance(at: CGPoint(x: 1, y: 1), in: solid(red: 0, green: 0, blue: 0)) ?? -1,
                       0.0, accuracy: 0.01)
    }

    func testLuminanceOutsideImageIsNil() {
        let pipeline = ValuePipeline()
        let image = solid(red: 1, green: 1, blue: 1)
        XCTAssertNil(pipeline.luminance(at: CGPoint(x: -10, y: -10), in: image))
    }

    // MARK: 表示

    func testPercentText() {
        XCTAssertEqual(ValuePipeline.percentText(nil), "—")
        XCTAssertEqual(ValuePipeline.percentText(0.299), "30%")
        XCTAssertEqual(ValuePipeline.percentText(0.745), "75%")
        XCTAssertEqual(ValuePipeline.percentText(1.0), "100%")
        XCTAssertEqual(ValuePipeline.percentText(0.0), "0%")
    }

    // MARK: 座標変換

    func testCenterOfViewMapsToCenterOfImage() {
        let geometry = PreviewGeometry(imageSize: CGSize(width: 1920, height: 1080),
                                       viewSize: CGSize(width: 390, height: 700))
        let point = geometry.imagePoint(forViewPoint: CGPoint(x: 195, y: 350), mirrored: false)
        XCTAssertEqual(point.x, 960, accuracy: 0.5)
        XCTAssertEqual(point.y, 540, accuracy: 0.5)
    }

    func testMirrorReflectsX() {
        let geometry = PreviewGeometry(imageSize: CGSize(width: 1920, height: 1080),
                                       viewSize: CGSize(width: 390, height: 700))
        let plain = geometry.imagePoint(forViewPoint: CGPoint(x: 20, y: 400), mirrored: false)
        let flipped = geometry.imagePoint(forViewPoint: CGPoint(x: 20, y: 400), mirrored: true)
        XCTAssertEqual(flipped.x, 1920 - plain.x, accuracy: 0.5)
        XCTAssertEqual(flipped.y, plain.y, accuracy: 0.5)
    }

    func testTopOfViewMapsToTopOfImage() {
        let geometry = PreviewGeometry(imageSize: CGSize(width: 1920, height: 1080),
                                       viewSize: CGSize(width: 390, height: 700))
        let top = geometry.imagePoint(forViewPoint: CGPoint(x: 195, y: 0), mirrored: false)
        let bottom = geometry.imagePoint(forViewPoint: CGPoint(x: 195, y: 700), mirrored: false)
        XCTAssertEqual(top.y, 1080, accuracy: 1.0)
        XCTAssertEqual(bottom.y, 0, accuracy: 1.0)
    }

    func testClampKeepsPointInsideView() {
        let clamped = PreviewGeometry.clamped(CGPoint(x: -40, y: 900),
                                             in: CGSize(width: 390, height: 700))
        XCTAssertEqual(clamped.x, 16, accuracy: 0.01)
        XCTAssertEqual(clamped.y, 684, accuracy: 0.01)
    }

    func testFillTransformCoversTarget() {
        let imageSize = CGSize(width: 1920, height: 1080)
        let target = CGSize(width: 390, height: 700)
        let transform = PreviewLayout.fillTransform(imageSize: imageSize, targetSize: target)
        let origin = CGPoint(x: 0, y: 0).applying(transform)
        let far = CGPoint(x: imageSize.width, y: imageSize.height).applying(transform)
        XCTAssertLessThanOrEqual(origin.x, 0.001)
        XCTAssertLessThanOrEqual(origin.y, 0.001)
        XCTAssertGreaterThanOrEqual(far.x, target.width - 0.001)
        XCTAssertGreaterThanOrEqual(far.y, target.height - 0.001)
    }

    // MARK: フィルタ

    func testValueModeKeepsExtentAndGreysOut() {
        let pipeline = ValuePipeline()
        let image = solid(red: 1, green: 0, blue: 0)
        let filtered = pipeline.filtered(image, mode: .value, levels: 3)
        XCTAssertEqual(filtered.extent, image.extent)
        XCTAssertEqual(pipeline.luminance(at: CGPoint(x: 2, y: 2), in: filtered) ?? -1,
                       0.2126, accuracy: 0.02)
    }

    func testPosterizeKeepsExtent() {
        let pipeline = ValuePipeline()
        let image = solid(red: 0.3, green: 0.5, blue: 0.7)
        let filtered = pipeline.filtered(image, mode: .posterize, levels: 4)
        XCTAssertEqual(filtered.extent, image.extent)
    }

    func testMirrorResetsExtent() {
        let image = solid(red: 0.5, green: 0.5, blue: 0.5)
            .transformed(by: CGAffineTransform(translationX: 12, y: 7))
        let mirrored = ValuePipeline.mirrored(image)
        XCTAssertEqual(mirrored.extent.origin.x, 0, accuracy: 0.001)
        XCTAssertEqual(mirrored.extent.origin.y, 0, accuracy: 0.001)
        XCTAssertEqual(mirrored.extent.width, image.extent.width, accuracy: 0.001)
        XCTAssertEqual(mirrored.extent.height, image.extent.height, accuracy: 0.001)
    }

    func testComposedMirrorSwapsHalves() {
        let pipeline = ValuePipeline()
        let leftHalf = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 4, height: 8))
        let rightHalf = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1))
            .cropped(to: CGRect(x: 4, y: 0, width: 4, height: 8))
        let image = leftHalf.composited(over: rightHalf)

        let leftBefore = pipeline.luminance(at: CGPoint(x: 1, y: 4), in: image) ?? -1
        let rightBefore = pipeline.luminance(at: CGPoint(x: 6, y: 4), in: image) ?? -1
        XCTAssertEqual(leftBefore, 1.0, accuracy: 0.02)
        XCTAssertEqual(rightBefore, 0.0, accuracy: 0.02)

        let flipped = pipeline.composed(image, mode: .color, levels: 3, mirrored: true)
        let leftAfter = pipeline.luminance(at: CGPoint(x: 1, y: 4), in: flipped) ?? -1
        let rightAfter = pipeline.luminance(at: CGPoint(x: 6, y: 4), in: flipped) ?? -1
        XCTAssertEqual(leftAfter, rightBefore, accuracy: 0.02)
        XCTAssertEqual(rightAfter, leftBefore, accuracy: 0.02)
    }

    // MARK: 補助

    private func solid(red: CGFloat, green: CGFloat, blue: CGFloat) -> CIImage {
        CIImage(color: CIColor(red: red, green: green, blue: blue, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
    }
}
