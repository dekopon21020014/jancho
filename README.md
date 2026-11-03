# Mahjon — 麻雀点数計算アプリ

SwiftUI製の日本式リーチ麻雀 点数計算アプリ．Swift Package形式なので，Xcodeでそのまま開ける．

## 機能

- **点数計算**: 翻・符・親/子・ロン/ツモから支払い点を計算
  - 満貫〜役満，数え役満，ダブル役満以上にも対応
  - 七対子（25符固定），平和ツモ（20符）
  - 本場（ロン+300，ツモ+100/人）と供託リーチ棒に対応
  - 子ツモの表示は慣例の「子の支払い / 親の支払い」
- **符計算**: 底符・門前ロン加符・ツモ符・雀頭・待ち・刻子/槓子から符を内訳付きで計算
  - 20符形は30符扱い（喰いピンフ形）にする一般ルールを適用
  - ダブル風牌は4符として計算（2符ルールの場合は雀頭分を差し引くこと）
- **早見表**: 1〜4翻のロン/ツモ早見表（ロジックから自動生成するので計算と常に一致する）

## 動かし方

配置先は `/Users/deko/opt/src/mahjon` を想定．

```sh
cd /Users/deko/opt/src/mahjon
swift test          # 点数計算ロジックの単体テスト
swift run MahjonApp # macOSアプリとして起動
```

Xcodeで開く場合:

```sh
open Package.swift
```

iOSで動かす場合は，Xcodeで新規Appプロジェクトを作り，
`Sources/MahjongScore` と `Sources/MahjonApp` の各Swiftファイルを
プロジェクトに加えればそのまま使える（SwiftUIのみ使用，追加依存なし）．

## 構成

```
Package.swift
Sources/
  MahjongScore/        # UI非依存の計算ロジック（単体テスト対象）
    ScoreCalculator.swift
    FuCalculator.swift
  MahjonApp/           # SwiftUI画面
    MahjonApp.swift
    ContentView.swift      # タブ（点数計算 / 符計算 / 早見表）
    CalculatorView.swift
    FuCalculatorView.swift
    ScoreTableView.swift
Tests/
  MahjongScoreTests/
    ScoreCalculatorTests.swift
```

## 計算式

- 基本点 = 符 × 2^(翻+2)，上限2,000（満貫）
- 5翻=満貫（2,000），6〜7翻=跳満（3,000），8〜10翻=倍満（4,000），
  11〜12翻=三倍満（6,000），13翻〜=役満（8,000）
- ロン: 子は基本点×4，親は×6 を100点単位に切り上げ
- ツモ: 親は全員から×2，子は親から×2・子から×1 をそれぞれ切り上げ

## iPhoneアプリとして使う

同じフォルダにある `Mahjon.xcodeproj` がiOSアプリ本体（Bundle ID: com.deko.mahjon）．
アプリのソースは `Sources/MahjonApp` を，計算ロジックはこのパッケージの
`MahjongScore` ライブラリをローカルパッケージ参照でそのまま使う．
署名は Personal Team 設定済み．Xcodeで開いて実行先にiPhone（実機/シミュレータ）を選んで Run．

注: パッケージ（Package.swift）をXcodeで開いているとローカルパッケージが
二重に開けて読み込めないので，アプリプロジェクトを開くときはパッケージ側を閉じること．
