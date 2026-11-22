# 明暗カメラ

絵を描くときに、色の情報をいったん外して明暗（バリュー）だけを見るための iOS カメラ。モチーフのどこがどれだけ明るいかを、画面上の数字で確かめられる。

- カラー / 明度 / 階調（3・4・5 段）の切り替え
- 左右反転（プレビューと保存写真の両方）
- 一時停止と写真保存
- A・B の二点比較（それぞれの位置の明度を 0〜100% で表示）

## 構成

| パス | 内容 |
| --- | --- |
| `project.yml` | XcodeGen 定義（Bundle ID: `com.shodai4.livevaluecamera`、iOS 17.0+、GoogleMobileAds を SPM で取得） |
| `Sources/LiveValueCameraApp.swift` | アプリのエントリポイント（広告 SDK の初期化） |
| `Sources/ContentView.swift` | 画面全体（プレビュー・コントロール・二点比較・保存・このアプリについて） |
| `Sources/CameraController.swift` | 背面カメラの制御とフレーム配信、権限、停止 |
| `Sources/ValueModel.swift` | 明度・階調フィルタ、アスペクトフィルの座標変換、明度の読み取り |
| `Sources/PreviewMetalView.swift` | `MTKView` によるプレビュー描画 |
| `Sources/AdBannerView.swift` | AdMob バナー（SDK が無い環境では何も出さない） |
| `Sources/ProStore.swift` | 買い切りの広告非表示（StoreKit 2 の土台） |
| `Resources/Info.plist` | カメラ・写真の利用目的、暗号化の申告、広告のアプリ ID、SKAdNetwork |
| `Resources/PrivacyInfo.xcprivacy` | プライバシー申告（追跡なし・UserDefaults の利用理由） |
| `Resources/Assets.xcassets` | アプリアイコン（1024px） |
| `scripts/verify-logic.py` | 明度・表示・座標変換の自己点検（CI でも実行） |
| `scripts/ci-testflight.sh` | アーカイブ・書き出し・TestFlight アップロード |
| `.github/workflows/ios-build.yml` | ビルド検証ジョブと TestFlight 配信ジョブ |

## 見え方

| モード | 処理 |
| --- | --- |
| カラー | フィルタなし |
| 明度 | `CIColorMatrix` で Rec.709 の輝度（R 0.2126 / G 0.7152 / B 0.0722）を各チャンネルへ入れて灰色にする |
| 階調 | 明度にしたうえで `CIColorPosterize` を 3・4・5 段で適用。境界線は引かない |

- プレビューは `MTKView`（Metal）に `CIContext` で描く。`isPaused = true` + `enableSetNeedsDisplay` で、新しいフレームが届いたときだけ描画する。
- 映像はアスペクトフィルでプレビュー領域いっぱいに広げる。はみ出した部分は切り抜く。
- フレームは 30fps に間引いて受け取る。停止中は新しいフレームを取り込まず、最後の 1 枚を保つ。

## 二点比較

- 「二点比較」を入れると A と B の照準が出る。指で動かせる。
- それぞれの位置の画素を 1×1 ピクセル（RGBA8）で書き出し、Rec.709 の係数で重みづけした明度を 0〜100% で表示する。A と B の中間には差も出す。
- 画面上の点から画素への変換は、アスペクトフィルの倍率と中央合わせのずれを使う（`PreviewGeometry.imagePoint`）。左右反転中は `幅 - x` で折り返す。
- 数値はカメラの映像そのものから読む（階調モードの段階ではなく、実際の明るさ）。

## 保存

- 停止中でも動作中でも保存できる。保存されるのは「画面で見えているとおり」の向き・フィルタ・左右反転を適用した 1 枚（元映像の解像度）。
- 写真ライブラリへの追加のみを求める（`NSPhotoLibraryAddUsageDescription`）。保存後に控えめなトーストで知らせる。

## 権限

- カメラが未許可・拒否のときは、プレビュー領域に案内と「設定を開く」を出す。
- 背面カメラが見つからない端末（シミュレータなど）では、その旨を出す。

## 広告と課金

- AdMob バナーを画面のいちばん下（コントロールバーの下）に置く。今は Google のテスト ID。
  - アプリ ID: `ca-app-pub-3940256099942544~1458002511`
  - バナー: `ca-app-pub-3940256099942544/2934735716`
  - 本番へ切り替えるときは `Sources/AdBannerView.swift` の `AdsSetup` と `Resources/Info.plist` の `GADApplicationIdentifier` を差し替える。
- 買い切りで広告を消せる土台を用意している（`ProStore`）。商品 ID は `com.shodai4.livevaluecamera.pro`。App Store Connect に商品ができるまでは「準備中」と表示し、購入ボタンは押せない。購入済みなら広告欄は出ない。

## ビルド

```sh
xcodegen generate
xcodebuild build -project LiveValueCamera.xcodeproj -scheme LiveValueCamera \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

カメラの映像はシミュレータでは出ないため、見え方の確認は実機で行う。

## TestFlight 配信

`main` へ push すると GitHub Actions が動く。

1. `build` ジョブ: 計算ロジックの自己点検と、署名なしのシミュレータ向けビルド。
2. `testflight` ジョブ: Secrets が登録されていれば `scripts/ci-testflight.sh` でアーカイブ・書き出し・アップロード。未登録なら飛ばす。

必要なリポジトリ Secrets:

| 名前 | 内容 |
| --- | --- |
| `APP_STORE_CONNECT_KEY_ID` | App Store Connect API キーの Key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID |
| `APP_STORE_CONNECT_PRIVATE_KEY` | AuthKey_*.p8 の中身 |
| `APPLE_TEAM_ID` | チーム ID（`86WNUS2875`） |

App Store Connect: App ID `6837945474`／Bundle ID `com.shodai4.livevaluecamera`／内部グループ「開発テスト」（自動配布）。

`main` に push した時点では Secrets が未登録のため、`testflight` ジョブは「スキップ」で終わる。4 つの Secrets をリポジトリに登録すると、次の push から TestFlight まで自動で進む。

## 注意

- カメラの映像は 1920×1080（16:9）で受け取る。縦長の画面では左右が切り抜かれる。
- 明度の数値は sRGB の画素値に Rec.709 の係数を掛けた目安で、測色器の値ではない。色管理は行わず、フィルタと数値表示を同じ土台に揃えている。
- 画面は縦向きのみ。
- プライバシー: 映像と明度の計算はすべて端末内で行う。外部へ送るのは広告の読み込みだけで、アプリ側では何も収集しない（`Resources/PrivacyInfo.xcprivacy` に追跡なし・UserDefaults の利用理由を記載）。
