import CoreImage
import Photos
import SwiftUI
import UIKit

// MARK: - 色

enum Palette {
    static let ivory = Color(red: 249.0 / 255.0, green: 248.0 / 255.0, blue: 245.0 / 255.0)
    static let sumi = Color(red: 26.0 / 255.0, green: 26.0 / 255.0, blue: 27.0 / 255.0)
    static let accent = Color(red: 176.0 / 255.0, green: 124.0 / 255.0, blue: 66.0 / 255.0)
}

// MARK: - 画面

@MainActor
struct ContentView: View {
    @StateObject private var camera = CameraController()
    @StateObject private var pro = ProStore()

    @Environment(\.scenePhase) private var scenePhase

    private let pipeline = ValuePipeline()

    @State private var mode: DisplayMode = .color
    @State private var levels: Int = 3
    @State private var mirrored = false
    @State private var comparisonOn = false
    @State private var pointA: CGPoint?
    @State private var pointB: CGPoint?
    @State private var readingA: Double?
    @State private var readingB: Double?
    @State private var previewSize: CGSize = .zero
    @State private var readingTask: Task<Void, Never>?
    @State private var toast: String?
    @State private var toastToken = 0
    @State private var isSaving = false
    @State private var showAbout = false

    var body: some View {
        ZStack {
            Palette.sumi.ignoresSafeArea()
            VStack(spacing: 0) {
                previewArea
                controlPanel
                adArea
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { camera.start() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                camera.refreshPermission()
            case .inactive, .background:
                camera.suspend()
            @unknown default:
                break
            }
        }
        .onChange(of: camera.frameID) { _, _ in scheduleReadings() }
        .onChange(of: comparisonOn) { _, isOn in
            if isOn {
                placeDefaultPoints()
            } else {
                readingA = nil
                readingB = nil
            }
            scheduleReadings()
        }
        .onChange(of: mirrored) { _, _ in scheduleReadings() }
        .onChange(of: pointA) { _, _ in scheduleReadings() }
        .onChange(of: pointB) { _, _ in scheduleReadings() }
        .onChange(of: previewSize) { _, _ in scheduleReadings() }
        .sheet(isPresented: $showAbout) {
            AboutSheet(pro: pro)
        }
    }

    // MARK: プレビュー

    private var composition: CIImage? {
        guard let frame = camera.frame else { return nil }
        return pipeline.composed(frame, mode: mode, levels: levels, mirrored: mirrored)
    }

    private var previewArea: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Palette.sumi
                PreviewMetalView(image: composition)
                if camera.permission == .authorized {
                    if comparisonOn {
                        comparisonLayer(viewSize: size)
                    }
                    if camera.isPaused {
                        pausedBadge
                    }
                }
                topBar
                if camera.permission != .authorized {
                    permissionPanel
                }
                toastLayer
            }
            .clipped()
            .coordinateSpace(name: "preview")
            .onAppear { updatePreviewSize(size) }
            .onChange(of: size) { _, newValue in updatePreviewSize(newValue) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var topBar: some View {
        VStack {
            HStack {
                Text("明暗")
                    .font(.system(size: 12, weight: .medium))
                    .tracking(3)
                    .foregroundStyle(Palette.ivory.opacity(0.75))
                Spacer()
                Button {
                    showAbout = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.ivory.opacity(0.7))
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("このアプリについて")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 2)
    }

    private var pausedBadge: some View {
        VStack(spacing: 5) {
            Text("静止中")
                .font(.system(size: 11, weight: .medium))
                .tracking(4)
                .foregroundStyle(Palette.ivory.opacity(0.85))
            Text("保存できます")
                .font(.system(size: 10))
                .foregroundStyle(Palette.ivory.opacity(0.45))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Palette.sumi.opacity(0.32), in: Capsule())
        .allowsHitTesting(false)
    }

    // MARK: 二点比較

    private func comparisonLayer(viewSize: CGSize) -> some View {
        ZStack {
            if let a = pointA, let b = pointB {
                Path { path in
                    path.move(to: a)
                    path.addLine(to: b)
                }
                .stroke(Palette.ivory.opacity(0.36),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                differenceLabel(between: a, and: b)
            }
            if let a = pointA {
                crosshair(letter: "A", value: readingA, at: a, viewSize: viewSize)
            }
            if let b = pointB {
                crosshair(letter: "B", value: readingB, at: b, viewSize: viewSize)
            }
        }
    }

    private func crosshair(letter: String, value: Double?, at point: CGPoint, viewSize: CGSize) -> some View {
        ZStack {
            Circle()
                .fill(Palette.sumi.opacity(0.16))
                .frame(width: 28, height: 28)
            Circle()
                .strokeBorder(Palette.ivory.opacity(0.85), lineWidth: 1)
                .frame(width: 28, height: 28)
            Circle()
                .fill(Palette.ivory)
                .frame(width: 3, height: 3)
            Text("\(letter) \(ValuePipeline.percentText(value))")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Palette.ivory)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Palette.sumi.opacity(0.60), in: Capsule())
                .offset(y: -26)
        }
        .frame(width: 84, height: 84)
        .contentShape(Rectangle())
        .position(point)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("preview"))
                .onChanged { drag in
                    let clamped = PreviewGeometry.clamped(drag.location, in: viewSize, margin: 20)
                    if letter == "A" {
                        pointA = clamped
                    } else {
                        pointB = clamped
                    }
                }
        )
    }

    private func differenceLabel(between a: CGPoint, and b: CGPoint) -> some View {
        let text: String
        if let ra = readingA, let rb = readingB {
            text = "差 \(ValuePipeline.percentText(abs(ra - rb)))"
        } else {
            text = "差 —"
        }
        return Text(text)
            .font(.system(size: 10, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(Palette.ivory.opacity(0.8))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Palette.sumi.opacity(0.50), in: Capsule())
            .position(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 - 15)
    }

    private func updatePreviewSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0, previewSize != size else { return }
        previewSize = size
        if comparisonOn {
            placeDefaultPoints()
        }
    }

    private func placeDefaultPoints() {
        guard previewSize.width > 0, previewSize.height > 0 else { return }
        if pointA == nil {
            pointA = CGPoint(x: previewSize.width * 0.32, y: previewSize.height * 0.40)
        }
        if pointB == nil {
            pointB = CGPoint(x: previewSize.width * 0.68, y: previewSize.height * 0.64)
        }
    }

    private func scheduleReadings() {
        readingTask?.cancel()
        guard comparisonOn, let frame = camera.frame, previewSize.width > 0, previewSize.height > 0 else {
            readingA = nil
            readingB = nil
            return
        }
        let geometry = PreviewGeometry(imageSize: frame.extent.size, viewSize: previewSize)
        let a = pointA
        let b = pointB
        let isMirrored = mirrored
        let source = frame
        let pipeline = self.pipeline

        readingTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 70_000_000)
            if Task.isCancelled { return }
            let valueA = a.map {
                pipeline.luminance(at: geometry.imagePoint(forViewPoint: $0, mirrored: isMirrored), in: source)
            }
            let valueB = b.map {
                pipeline.luminance(at: geometry.imagePoint(forViewPoint: $0, mirrored: isMirrored), in: source)
            }
            if Task.isCancelled { return }
            self.readingA = valueA ?? nil
            self.readingB = valueB ?? nil
        }
    }

    // MARK: コントロール

    private var controlPanel: some View {
        VStack(spacing: 14) {
            modeSelector
            HStack(spacing: 8) {
                Group {
                    if mode == .posterize {
                        levelSelector
                    } else {
                        Text(mode.summary)
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.ivory.opacity(0.45))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                chipButton(title: "反転", isOn: mirrored) {
                    mirrored.toggle()
                }
                chipButton(title: "二点比較", isOn: comparisonOn) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        comparisonOn.toggle()
                    }
                }
            }
            HStack(spacing: 0) {
                saveButton
                    .frame(width: 92)
                Spacer(minLength: 0)
                captureButton
                Spacer(minLength: 0)
                Color.clear
                    .frame(width: 92, height: 1)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(Palette.sumi)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Palette.ivory.opacity(0.09))
                .frame(height: 0.5)
        }
    }

    private var modeSelector: some View {
        HStack(spacing: 2) {
            ForEach(DisplayMode.allCases) { item in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        mode = item
                    }
                } label: {
                    Text(item.label)
                        .font(.system(size: 13, weight: mode == item ? .semibold : .regular))
                        .foregroundStyle(mode == item ? Palette.sumi : Palette.ivory.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background {
                            if mode == item {
                                Capsule().fill(Palette.ivory)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Palette.ivory.opacity(0.08), in: Capsule())
    }

    private var levelSelector: some View {
        HStack(spacing: 6) {
            Text("階調数")
                .font(.system(size: 10))
                .foregroundStyle(Palette.ivory.opacity(0.5))
            ForEach([3, 4, 5], id: \.self) { number in
                Button {
                    levels = number
                } label: {
                    Text("\(number)")
                        .font(.system(size: 12, weight: levels == number ? .semibold : .regular))
                        .foregroundStyle(levels == number ? Palette.sumi : Palette.ivory.opacity(0.62))
                        .frame(width: 26, height: 26)
                        .background {
                            if levels == number {
                                Circle().fill(Palette.ivory)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func chipButton(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isOn ? Palette.accent : Palette.ivory.opacity(0.28))
                    .frame(width: 5, height: 5)
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(isOn ? Palette.ivory : Palette.ivory.opacity(0.6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Palette.ivory.opacity(isOn ? 0.14 : 0.06), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var captureButton: some View {
        VStack(spacing: 7) {
            Button {
                camera.togglePaused()
            } label: {
                ZStack {
                    Circle()
                        .fill(Palette.ivory)
                        .frame(width: 62, height: 62)
                    Image(systemName: camera.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Palette.sumi)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(camera.isPaused ? "再開" : "一時停止")
            Text(camera.isPaused ? "再開" : "停止")
                .font(.system(size: 10))
                .foregroundStyle(Palette.ivory.opacity(0.5))
        }
        .frame(height: 84, alignment: .top)
    }

    private var canSave: Bool {
        !isSaving && camera.frame != nil
    }

    private var saveButton: some View {
        VStack(spacing: 7) {
            Button {
                savePhoto()
            } label: {
                ZStack {
                    Circle()
                        .fill(Palette.ivory.opacity(canSave ? 0.12 : 0.05))
                        .frame(width: 62, height: 62)
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(Palette.ivory.opacity(canSave ? 0.9 : 0.3))
                }
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .accessibilityLabel("写真に保存")
            Text("保存")
                .font(.system(size: 10))
                .foregroundStyle(Palette.ivory.opacity(canSave ? 0.55 : 0.3))
        }
        .frame(height: 84, alignment: .top)
    }

    // MARK: 権限

    private var permissionPanel: some View {
        VStack(spacing: 12) {
            switch camera.permission {
            case .checking:
                ProgressView()
                    .tint(Palette.ivory)
                Text("カメラを準備しています")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ivory.opacity(0.6))
            case .denied:
                Text("カメラへのアクセスが必要です")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.ivory)
                Text("設定アプリでカメラを許可してください。映像は明暗の確認にだけ使い、端末の外には送りません。")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ivory.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 268)
                Button {
                    openSettings()
                } label: {
                    Text("設定を開く")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.sumi)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 9)
                        .background(Palette.ivory, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            case .unavailable:
                Text("カメラを利用できません")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.ivory)
                Text("この端末では背面カメラが見つかりませんでした。実機で起動すると、映像がここに表示されます。")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ivory.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 268)
            case .authorized:
                EmptyView()
            }
        }
        .padding(24)
    }

    // MARK: トースト

    private var toastLayer: some View {
        VStack {
            Spacer(minLength: 0)
            if let toast {
                Text(toast)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.sumi)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Palette.ivory.opacity(0.95), in: Capsule())
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
    }

    private func showToast(_ text: String) {
        toastToken += 1
        let token = toastToken
        withAnimation(.easeOut(duration: 0.18)) {
            toast = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            guard self.toastToken == token else { return }
            withAnimation(.easeIn(duration: 0.25)) {
                self.toast = nil
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: 保存

    private func savePhoto() {
        guard !isSaving, let frame = camera.frame else { return }
        isSaving = true
        let output = pipeline.composed(frame, mode: mode, levels: levels, mirrored: mirrored)
        let extent = output.extent
        guard extent.width >= 1, extent.height >= 1,
              let cgImage = RenderContext.shared.ciContext.createCGImage(
                output,
                from: extent,
                format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
              ) else {
            isSaving = false
            showToast("保存できませんでした")
            return
        }
        let image = UIImage(cgImage: cgImage)

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    self.isSaving = false
                    Haptics.shared.warning()
                    self.showToast("写真への追加が許可されていません")
                }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, _ in
                DispatchQueue.main.async {
                    self.isSaving = false
                    if success {
                        Haptics.shared.success()
                        self.showToast("写真に保存しました")
                    } else {
                        Haptics.shared.warning()
                        self.showToast("保存できませんでした")
                    }
                }
            }
        }
    }

    // MARK: 広告

    private var adArea: some View {
        Group {
            if pro.isPro {
                Color.clear
                    .frame(height: 0)
            } else {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Palette.sumi.opacity(0.12))
                        .frame(height: 0.5)
                    AdBannerView(adUnitID: AdsSetup.bannerUnitID)
                        .frame(width: 320, height: 50)
                }
                .frame(maxWidth: .infinity)
                .background {
                    Palette.ivory.ignoresSafeArea(edges: .bottom)
                }
            }
        }
    }
}

// MARK: - このアプリについて

@MainActor
struct AboutSheet: View {
    @ObservedObject var pro: ProStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    block("このアプリについて",
                          "絵を描くときに、色の情報をいったん外して明暗（バリュー）だけを見るためのカメラです。モードを切り替えながら、モチーフの明るさの差を確かめられます。")
                    block("三つの見え方",
                          "カラー　色をそのまま見る。\n明度　Rec.709 の輝度（赤 0.2126・緑 0.7152・青 0.0722）で色味を落とし、明暗だけにする。\n階調　明暗を 3・4・5 段に整理する。境界線は引かない。")
                    block("二点比較",
                          "「二点比較」を入れると、画面の上で A と B を指で動かせます。それぞれの位置の明度を 0〜100% で表示するので、どこがどれだけ明るいかを数字で確かめられます。数値はカメラの映像そのものから読み取ります（階調モードの段階ではなく、実際の明るさ）。")
                    block("保存と反転",
                          "「反転」はプレビューと保存写真の両方を左右反転します。画面で見えているとおりの向きとフィルタで保存されます。映像は端末の中で処理し、保存した写真以外は外部に送りません。")
                    proBlock
                    block("この版について",
                          "バージョン 1.0。広告は Google のテスト用 ID で表示しています。明度の数値は画素値に Rec.709 の係数を掛けた目安で、測色器の値ではありません。")
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Palette.ivory)
            .navigationTitle("明暗カメラ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .tint(Palette.accent)
        .preferredColorScheme(.light)
    }

    private func block(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.sumi)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Palette.sumi.opacity(0.72))
                .lineSpacing(5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var proBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("広告について")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.sumi)
            Text(pro.isPro
                 ? "広告は表示されていません。"
                 : "画面のいちばん下に広告を出しています。買い切りで消せます。")
                .font(.system(size: 12))
                .foregroundStyle(Palette.sumi.opacity(0.72))

            if !pro.isPro {
                Button {
                    Task { await pro.purchase() }
                } label: {
                    HStack {
                        Text("広告を消す")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text(pro.isPurchasing ? "手続き中" : (pro.displayPrice ?? "準備中"))
                            .font(.system(size: 12))
                            .monospacedDigit()
                    }
                    .foregroundStyle(Palette.sumi)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Palette.sumi.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(pro.isPurchasing || pro.displayPrice == nil)

                Button("購入を復元") {
                    Task { await pro.restore() }
                }
                .font(.system(size: 11))
                .foregroundStyle(Palette.sumi.opacity(0.6))
            }

            if let message = pro.message {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
