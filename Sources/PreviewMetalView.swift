import CoreImage
import MetalKit
import SwiftUI
import UIKit

/// Metal で CIImage をそのまま描くプレビュー。
/// 画面の更新は新しい映像が届いたときだけ（isPaused + setNeedsDisplay）にして、発熱を抑える。
struct PreviewMetalView: UIViewRepresentable {
    let image: CIImage?

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.autoResizeDrawable = true
        view.isOpaque = true
        view.clearColor = MTLClearColor(red: 0.102, green: 0.102, blue: 0.106, alpha: 1)
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.image = image
        view.setNeedsDisplay()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        var image: CIImage?

        private let ciContext = RenderContext.shared.ciContext
        private let commandQueue = RenderContext.shared.commandQueue

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            view.setNeedsDisplay()
        }

        func draw(in view: MTKView) {
            let size = view.drawableSize
            guard size.width >= 1, size.height >= 1,
                  let drawable = view.currentDrawable,
                  let commandBuffer = commandQueue?.makeCommandBuffer() else { return }

            let target = CGRect(origin: .zero, size: size)
            let background = CIImage(color: CIColor(red: 0.102, green: 0.102, blue: 0.106))
                .cropped(to: target)

            let content: CIImage
            if let image, image.extent.width > 0, image.extent.height > 0 {
                content = PreviewLayout.fitted(image, to: size).composited(over: background)
            } else {
                content = background
            }

            ciContext.render(content,
                             to: drawable.texture,
                             commandBuffer: commandBuffer,
                             bounds: target,
                             colorSpace: CGColorSpaceCreateDeviceRGB())
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
