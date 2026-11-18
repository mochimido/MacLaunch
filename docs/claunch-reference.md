# CLaunchの調査とMacLaunch 1.2への反映

2026-11-18に、公式のスキン仕様と、公式配布ZIP内のFluent Light・Glass・Solid BlackのXMLおよびPNGを確認した。

- [スキンXML仕様](https://ss1.xrea.com/pyonkichi.g1.xrea.com/claunch_skin.html)
- [公式ダウンロード](https://ss1.xrea.com/pyonkichi.g1.xrea.com/claunch.html)
- [登録操作](https://pyonky.github.io/CLaunch-Help/ja/useRegister.htm)
- [移動操作](https://pyonky.github.io/CLaunch-Help/ja/useMoveItem.htm)

## スキンの構成

XMLが背景・四辺のフレーム・キャプション・システムボタン・タブ領域・ボタン領域を定義する。タブ画像は通常／ホバー／選択、ボタン画像は通常／ホバー／押下の3状態を縦に持つ。画像の周囲を伸縮対象から外す指定と、推奨サイズ・余白・間隔の指定がある。

Fluent Lightの推奨値は上枠28px、タブ64×26px、ボタン58×58px、アイコン32px、7列×3行。MacLaunchではこの寸法を基準に、LauncherLayoutとLauncherSkinで部品を分け、ネイティブ描画で再構成した。公式画像のアプリへの同梱はしていない。

ライト／ダーク／青いグラス調、タブの上下配置、表示行数、列数、ラベルの有無を選べる。CLaunchのZIPスキンを直接読み込む機能は含まない。

## 登録操作の反映

公式ヘルプの空きボタンへのドロップ、右クリック登録、複数登録、実行中アプリの参照を、macOSに合わせて実装した。起動中アプリはウィンドウを指す方式に代えて一覧から選択する。

空きマスのダブルクリック・右クリック、アプリ一覧の複数選択、ファイル選択、URL入力、クリップボード、連続登録を用意。登録後も選んだマスの位置を保ち、移動元は空白になる。タブ上へのドラッグでページを切り替える。コピーの修飾キーはmacOSに合わせてOptionにした。

既存のアイテムと呼び出しキーは維持し、新しい配置情報は登録・移動時に保存する。スキン変更だけでは登録内容を書き換えない。
