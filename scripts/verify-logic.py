#!/usr/bin/env python3
"""明暗カメラの計算ロジックの写しと自己点検。

Swift 側（Sources/ValueModel.swift）と同じ式を Python に写し、
明度の重みづけ・パーセント表示・アスペクトフィルの座標変換が
意図どおりかを確認する。CI でも実行する。
"""

import math

RED = 0.2126
GREEN = 0.7152
BLUE = 0.0722


def luminance(red, green, blue):
    """Rec.709 の輝度（0〜1）。Swift の ValuePipeline.luminance と同じ。"""
    return min(max((RED * red + GREEN * green + BLUE * blue) / 255.0, 0.0), 1.0)


def percent(value):
    """0〜1 を「30%」の形にする。Swift の .rounded()（四捨五入）に合わせる。"""
    if value is None:
        return "—"
    return "%d%%" % int(math.floor(value * 100 + 0.5))


def scale(image_size, view_size):
    return max(view_size[0] / image_size[0], view_size[1] / image_size[1])


def offset(image_size, view_size):
    s = scale(image_size, view_size)
    displayed = (image_size[0] * s, image_size[1] * s)
    return ((view_size[0] - displayed[0]) / 2, (view_size[1] - displayed[1]) / 2)


def clamp(value, low, high):
    return min(max(value, low), high)


def image_point(image_size, view_size, point, mirrored):
    """画面上の点（左上原点）→ 元画像の画素座標（左下原点）。"""
    s = max(scale(image_size, view_size), 0.0001)
    off = offset(image_size, view_size)
    x = (point[0] - off[0]) / s
    distance_from_top = (point[1] - off[1]) / s
    if mirrored:
        x = image_size[0] - x
    y = image_size[1] - distance_from_top
    return (
        clamp(x, 0.5, max(image_size[0] - 0.5, 0.5)),
        clamp(y, 0.5, max(image_size[1] - 0.5, 0.5)),
    )


def fill_transform(image_size, target_size):
    s = scale(image_size, target_size)
    dx = (target_size[0] - image_size[0] * s) / 2
    dy = (target_size[1] - image_size[1] * s) / 2
    return s, dx, dy


def apply_transform(transform, point):
    s, dx, dy = transform
    return (point[0] * s + dx, point[1] * s + dy)


def main():
    failures = []

    def check(name, actual, expected, tolerance=1e-6):
        if abs(actual - expected) > tolerance:
            failures.append("%s: %.6f != %.6f" % (name, actual, expected))

    def check_point(name, actual, expected, tolerance=1e-6):
        check(name + ".x", actual[0], expected[0], tolerance)
        check(name + ".y", actual[1], expected[1], tolerance)

    # 1) Rec.709 の輝度
    check("white", luminance(255, 255, 255), 1.0)
    check("black", luminance(0, 0, 0), 0.0)
    check("red", luminance(255, 0, 0), RED)
    check("green", luminance(0, 255, 0), GREEN)
    check("blue", luminance(0, 0, 255), BLUE)
    check("weights sum", RED + GREEN + BLUE, 1.0, 1e-4)
    # 中間調（明度モードにしたとき画素値がそのまま保たれる）
    check("mid gray", luminance(128, 128, 128), 128 / 255)

    # 2) パーセント表示
    check("percent 0.299", float(percent(0.299).rstrip("%")), 30.0)
    check("percent 0.745", float(percent(0.745).rstrip("%")), 75.0)
    check("percent 0.005", float(percent(0.005).rstrip("%")), 1.0)
    check("percent 1.0", float(percent(1.0).rstrip("%")), 100.0)
    if percent(None) != "—":
        failures.append("percent(None) が — になっていない")

    # 3) アスペクトフィル（1920x1080 の映像を 390x700 の画面へ）
    image = (1920.0, 1080.0)
    view = (390.0, 700.0)
    check("scale", scale(image, view), 700.0 / 1080.0)
    check_point("offset", offset(image, view), ((390.0 - 1920.0 * 700.0 / 1080.0) / 2, 0.0))

    # 画面の中心は映像の中心
    check_point("center", image_point(image, view, (195.0, 350.0), False), (960.0, 540.0))
    # 左右反転では、画面の中心はそのまま、左端は右側の画素を指す
    check_point("center mirrored", image_point(image, view, (195.0, 350.0), True), (960.0, 540.0))
    left = image_point(image, view, (0.0, 350.0), False)
    left_mirrored = image_point(image, view, (0.0, 350.0), True)
    check("mirror x", left_mirrored[0], 1920.0 - left[0])
    check("mirror y", left_mirrored[1], left[1])

    # 画面の上端は映像の上端（y = 1080 側、0.5 で止める）
    top = image_point(image, view, (195.0, 0.0), False)
    check("top y", top[1], 1079.5)
    bottom = image_point(image, view, (195.0, 700.0), False)
    check("bottom y", bottom[1], 0.5)

    # 4) 描画変換：映像が目標の矩形を完全に覆う（はみ出しは切り抜く）
    for target in [(1170.0, 2100.0), (780.0, 1400.0), (390.0, 700.0)]:
        transform = fill_transform(image, target)
        corners = [apply_transform(transform, p) for p in [(0, 0), (1920, 0), (0, 1080), (1920, 1080)]]
        xs = [c[0] for c in corners]
        ys = [c[1] for c in corners]
        if not (min(xs) <= 0.0001 and max(xs) >= target[0] - 0.0001):
            failures.append("cover x %s: %s" % (target, (min(xs), max(xs))))
        if not (min(ys) <= 0.0001 and max(ys) >= target[1] - 0.0001):
            failures.append("cover y %s: %s" % (target, (min(ys), max(ys))))
        # 縦横の比が崩れていない
        check("aspect %s" % (target,), (xs[1] - xs[0]) / (ys[2] - ys[0]), 1920 / 1080)

    # 5) 左右反転した画素の範囲は (0, 0, 幅, 高さ) に戻る
    def mirror(px):
        return 1920.0 - px

    check("mirror range left", mirror(0.0), 1920.0)
    check("mirror range right", mirror(1920.0), 0.0)

    # 6) 照準の可動範囲
    def clamped(p, size, margin=16.0):
        return (
            clamp(p[0], min(margin, size[0] / 2), max(size[0] - margin, size[0] / 2)),
            clamp(p[1], min(margin, size[1] / 2), max(size[1] - margin, size[1] / 2)),
        )

    check_point("clamp corner", clamped((-40.0, 900.0), view), (16.0, 684.0))
    check_point("clamp inside", clamped((200.0, 300.0), view), (200.0, 300.0))

    if failures:
        print("NG")
        for line in failures:
            print("  - " + line)
        raise SystemExit(1)

    print("OK: 明度・表示・座標変換の自己点検 すべて通過")
    print("  例) 画面中央 → 画素 (960.0, 540.0) / 白 100%% / 左端の反転 x %.1f" % left_mirrored[0])


if __name__ == "__main__":
    main()
