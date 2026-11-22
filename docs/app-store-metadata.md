# App Store 提出用メタデータ — 明暗カメラ

App Store Connect にそのまま貼れる形でまとめた。字数は実測値（全角1文字＝1文字で計算）。
最終更新 2026-11-23 ／ 対象バージョン 1.0（ビルド番号は CI の `github.run_number`）。

## 1. 基本情報

| 項目 | 値 |
| --- | --- |
| ホーム画面の表示名 | 明暗カメラ |
| App Store のアプリ名 | 明暗カメラ（5文字／上限30） |
| Bundle ID | `com.shodai4.livevaluecamera` |
| App Store Connect の Apple ID | 6837945474 |
| バージョン | 1.0 |
| 対応 | iPhone（iOS 17.0 以上）・縦向きのみ・iPad 非対応 |
| 価格 | 無料（広告あり） |
| アプリ内課金 | 広告非表示の買い切り `com.shodai4.livevaluecamera.pro`（コード側は実装済み・App Store Connect への商品登録は未了） |
| 対応言語 | 日本語のみ |
| カテゴリ | プライマリ：写真＆ビデオ ／ セカンダリ：グラフィック＆デザイン |
| 年齢制限 | 4+（全年齢） |
| 端末の許可 | カメラ（`NSCameraUsageDescription`）／写真への追加のみ（`NSPhotoLibraryAddUsageDescription`） |

## 2. App Store に貼るテキスト

### アプリ名（30文字以内）
```
明暗カメラ
```

### サブタイトル（30文字以内）
```
色を外して明暗だけを見るカメラ
```
（15文字）

### プロモーションテキスト（170文字以内・審査なしで更新できる）
```
モチーフのどこがどれだけ明るいか、数字で確かめられます。A と B の二点比較、3・4・5段の階調、左右反転、写真保存。映像は端末のなかだけで処理し、外部へ送りません。
```
（84文字）

### 概要（4000文字以内）
```
絵を描くとき、色の情報をいったん外して明暗（バリュー）だけを見ると、形と光の構造がはっきりします。明暗カメラは、そのためのカメラです。

■ 三つの見え方
カラー：色をそのまま見る
明度：Rec.709 の輝度で色味を落とし、明暗だけにする
階調：明暗を3・4・5段に整理する（境界線は引かない）

■ 二点比較
「二点比較」を入れると A と B の照準が出ます。指で動かして比べたい2か所に合わせると、それぞれの明度が 0〜100% の数字で出て、A と B の差も分かります。数値はカメラの映像そのものから読むので、階調モードで表示していても実際の明るさがそのまま出ます。

■ 保存と反転
画面で見えているとおりの向き・フィルタ・左右反転で、写真に保存できます。左右反転はプレビューと保存の両方に効くので、鏡を使って描くときの確認にも使えます。

■ 端末のなかだけで
映像と明度の計算は、すべて iPhone のなかで行います。写真を外部へ送ることはありません（通信は広告の読み込みのみ）。

※ 明度の数値は画素値に Rec.709 の係数を掛けた目安で、測色器の値ではありません。
※ iPhone（iOS 17.0 以上）・縦向き。
```
（524文字）

### キーワード（100文字以内・カンマ区切り・スペースなし）
```
デッサン,明暗,バリュー,明度,デッサン用,絵画,スケッチ,カメラ,観察,画材,アトリエ
```
（44文字）

キーワードの考え方：アプリ名とサブタイトルに入っている語（明暗カメラ／色を外して明暗だけを見るカメラ）は重複しても検索対象になるため、ここでは**入っていない語**を優先した。「デッサン」「明暗」「バリュー」はサブタイトルと重ならないよう調整した。

## 3. URL

| 項目 | URL |
| --- | --- |
| サポートURL（必須） | https://shodai4.com/apps/live-value-camera/support.html |
| プライバシーポリシーURL（必須） | https://shodai4.com/apps/live-value-camera/privacy.html |
| マーケティングURL（任意） | https://shodai4.com/apps/live-value-camera/ |
| サポートの入口（アプリのページ） | https://shodai4.com/apps/live-value-camera/ |

3つとも公開済み（2026-11-23 に 200 OK を確認）。

## 4. 年齢制限（App の年齢制限）

- 全年齢（4+）。暴力・性的表現・ギャンブル・ホラー・医薬品・ユーザー生成コンテンツ・位置情報の共有はいずれも「なし」。
- 広告は画面下部に Google AdMob のバナーを表示する（内容は Google の広告ネットワークの審査を通ったもの）。

暴力・性的表現・ギャンブル・ホラー等の要素はない。カメラで撮る対象は利用者が選ぶ。

## 5. App のプライバシー（栄養ラベル）

アプリ本体は何も収集しない。広告SDK（Google Mobile Ads）分だけを、サードパーティの広告目的として申告する。

| データの種類 | 収集 | 使途 | トラッキング |
| --- | --- | --- | --- |
| 識別子（端末ID） | する（Google Mobile Ads SDK） | サードパーティの広告 | しない |
| 使用状況データ（広告の表示・反応） | する（Google Mobile Ads SDK） | サードパーティの広告 | しない |
| ユーザーのコンテンツ（写真・映像） | しない | 端末内のみ | — |
| 位置情報 | しない | — | — |
| 診断 | しない | — | — |

- 「トラッキング」はすべて**しない**（ATT を要求しておらず、`PrivacyInfo.xcprivacy` も `NSPrivacyTracking=false`）。App Store Connect では「データをトラッキングに使用していますか」に **いいえ**。
- 提出前に Google の開示（<https://policies.google.com/technologies/partner-sites>）と AdMob SDK のデータ開示を照合し、過不足がないか最終確認する。

## 6. App Review 担当者向けメモ（Review Notes）

英日どちらも貼れるようにしてある。ASC の Review Notes は英語を推奨。

### English

```
No account or sign-in is required. The rear camera is used only to show a live preview and to read pixel brightness; nothing is recorded, uploaded or stored. Saving a still uses add-only photo access (NSPhotoLibraryAddUsageDescription) — the app never reads the photo library.

The app works fully offline. The only network traffic is the Google Mobile Ads banner at the bottom of the screen. The app does not request App Tracking Transparency and its privacy manifest declares no tracking.

To reach the core feature: launch the app (camera preview), tap the mode row to switch カラー/明度/階調, turn on 二点比較 to place points A and B and read the 0–100% values, then tap 保存.

Note: the Simulator has no camera, so please test on a device. If the "Remove ads" product is not yet available in App Store Connect, the purchase row shows 準備中 and stays disabled.
```

### 日本語（控え）

```
ログイン不要。背面カメラはプレビュー表示と明るさの読み取りにだけ使い、録画・保存・送信はしません。写真は「追加のみ」の権限で保存し、ライブラリの読み取りは行いません。通信は広告の読み込みのみ。ATTは要求せず、マニフェストも追跡なし。
```

## 7. スクリーンショット

- 必須：iPhone 6.9インチ（1290×2796px または 1320×2868px）。3〜10枚。
- 任意：iPhone 6.5インチ（1284×2778px）。iPad は非対応なので不要。
- 1枚目でアプリの核心が分かる画面を出す（起動 → モード切替 → 二点比較をオン → 「保存」）。
- 端末の枠やキャプションを載せる場合も、実際のアプリ画面をそのまま使う（合成した偽のUIは不可）。
- 撮影は実機または iOS 17 以降のシミュレータ。カメラの映像はシミュレータでは出ないため、スクリーンショットは実機で撮る。

## 8. 提出前チェックリスト

- [ ] App Store Connect にアプリレコードがある（Apple ID 6837945474）／Bundle ID `com.shodai4.livevaluecamera`
- [ ] バージョン 1.0 に、CI がアップロードしたビルドを選択
- [ ] サポートURL・プライバシーポリシーURL が 200 で開く
- [ ] 「App のプライバシー」を第5節のとおり入力
- [ ] 年齢制限を 4+ に設定
- [ ] カテゴリを第1節のとおり設定
- [ ] スクリーンショットを 6.9インチで3枚以上
- [ ] 広告の本番IDへの差し替え（下記「未対応」を参照）
- [ ] アプリ内課金を出す場合は商品登録と審査提出、出さない場合は導線が「準備中」で押せないことを確認
- [ ] 輸出コンプライアンス：`ITSAppUsesNonExemptEncryption=false` 済み（追加質問なし）
- [ ] 審査用の連絡先メールと電話を記入

## 9. 未対応・提出前に判断がいること

1. **広告IDが Google のテスト用IDのまま**（`Sources/AdBannerView.swift` の `AdsSetup` と `Info.plist` の `GADApplicationIdentifier` が `ca-app-pub-3940256099942544` 系）。このまま審査に出すと広告はテスト広告のままで、収益も出ない。本番のアプリID・ユニットIDへ差し替えるか、いったん広告を外して出すかを決める。差し替えは Swift 側の変更なので、このタスクでは触っていない。
2. **アプリ内課金（広告非表示）が ASC 未登録**。商品を作らないまま提出すると、アプリ内の「広告を消す」が「準備中」で押せない状態になる。審査で「機能していない課金導線」と見られる可能性があるため、商品登録して提出するか、導線ごと外すかを決める。
3. **6本同時提出のスパム判定（ガイドライン4.3）**。同じ開発者から同じ分野のアプリをまとめて出すため、機能の違いが伝わるよう、概要とレビューメモで「何をするアプリか」を明確にしている。スクリーンショットもアプリごとに別の画面にすること。
4. **`PrivacyInfo.xcprivacy` は同梱済み**（追跡なし・UserDefaults の利用理由 CA92.1）。追加の作業はない。

## 10. 審査で聞かれやすい点と回答

| 想定される指摘 | 回答 |
| --- | --- |
| カメラ／写真を何に使うのか | 背面カメラでプレビューを出し、画素の明るさを読むため。録画・保存・送信はしない。保存は「追加のみ」の権限。 |
| 通信はあるのか | 広告（Google AdMob）の読み込みのみ。映像・写真・明度の数値は送らない。 |
| 広告はどこから出ているのか | 画面下部の AdMob バナー。テストIDで動作確認済み。 |
| データはどこに保存されるのか | 端末内のみ。アプリ内に残るのは購入状態だけ。 |
| 似たアプリが複数ある（4.3） | それぞれ目的が異なる（明暗を見る／配色を逆算する／額装を確かめる／構図を決める／号数と送料を調べる／乾燥日数を見積もる）。画面構成もデータも別で、共通のコードベースは使っていない。 |
