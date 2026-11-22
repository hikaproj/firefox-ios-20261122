# Firefox-iOS GodMode / Omega Zero-Footprint Edition

> **Customized by Hikaproj**  
> Twitter / X: [@hikaproj](https://x.com/hikaproj)  
> Official Website: [https://hikaproj.com](https://hikaproj.com)  
> Contact: [https://hikaproj.com/new/contact](https://hikaproj.com/new/contact)

---

## 1. 概要 (Overview)

**Firefox-iOS GodMode / Omega Zero-Footprint Edition** は、RAM 2GB〜3GBの旧世代iOSデバイス（iPhone 8、iPhone XR、iPhone SE第2世代等）において、バックグラウンドのSpotify・X（Twitter）・DiscordをOSのメモリ不足キル（Jetsam）から守りつつ、PC不要でチート級の高度機能群をフル活用できるように極限改造されたブラウザです。

PC版WebExtension互換レイヤーの巨大なオーバーヘッドを一切排除し、WebKitネイティブAPI（`WKUserScript` / `WKContentRuleList` / `WKWebpagePreferences` / `WKWebsiteDataStore`）とiOS低レイヤーフレームワーク（`Darwin/Mach`, `Network.framework`, `AVFoundation`, `CoreGraphics`, `SQLite3`）のみを用いて物理限界レベルの極小フットプリントを実現しています。

---

## 2. 最適化プリセット (Optimization Presets)

画面上のHUDまたは設定画面から、利用シーンに応じた3段階プリセットをワンタップで切り替え可能です。

| プリセット | 特徴 | 推奨用途 |
| :--- | :--- | :--- |
| **Balanced** | ネイティブ広告ブロック ＋ 30秒タブ休止 ＋ CSSアニメ停止 ＋ バックグラウンドメディア再生 | 通常の高速・快適ブラウジング |
| **Spotify + Discord 共存モード** | 単一ProcessPool強制 ＋ 画像遅延読み込み ＋ Retina 1.5x制限 ＋ 10秒タブ休止 ＋ URLCache 2MB制限 ＋ DOM刈り込み ＋ サーマルFPS制御 | 音楽再生や通話を維持しながらブラウジング（Jetsam完全制圧） |
| **Ultra-Survival (極限生存)** | JS選択的キル ＋ 全画像/Webフォント完全ブロック ＋ Retina 1.0x ＋ 仮想タブ1枚制限 ＋ URLCache 0MB | RAM 2GB機での極限状態・テキスト重視ブラウジング |
| **Custom** | 全32モジュールのON/OFF・数値を手動設定 | パワーユーザー向けカスタマイズ |

---

## 3. 実装済み全32機能モジュール詳細仕様

### 【第1部：極限軽量化 & Jetsam・サーマル完全制圧】

- **モジュールA-1: アグレッシブ・タブ休止 (Tab Hibernation)**
  非アクティブタブの放置タイマー（即時〜1分）により、`CGImageSourceCreateThumbnailAtIndex` で超低解像度化したJPEGサムネイル（幅180px以下）とURLのみを保持し、`WKWebView` を `nil` 化して物理RAMを即座に解放。
- **モジュールA-2: 単一 `WKProcessPool` 強制**
  全タブでグローバルシングルトン `WKProcessPool` を共有。タブごとに独立したWebContentプロセスが生成されるのを抑止し、プロセス乱立によるクラッシュを防止。
- **モジュールA-3: Extreme Lite レンダリング・通信リミッター**
  Webフォント（`@font-face` / `.woff2`）の完全遮断、画像ブロック / 遅延強制、CSSアニメーション無効化、動画 `autoplay` 剥奪 ＆ `preload="none"` を個別制御。
- **モジュールA-4: リアルタイムRAM & Jetsam監視HUD**
  Machカーネルの `task_info` (`phys_footprint`) および `os_proc_available_memory()` を常時サンプリングし、消費RAM（MB）と残存Jetsamマージンを画面上にコンパクト表示。ダブルタップまたはタップでDevTools・設定を即座に起動可能。
- **モジュールU: 動的JavaScriptエンジン選択的キル**
  `WKWebpagePreferences.allowsContentJavaScript` をサイト別・グローバルで制御。JS無効化時はWebKitのJITコンパイラおよびJSヒープ割り当てそのものを完全抑止。
- **モジュールV: ブラウザ本体極限ダイエット**
  アプリ本体の `URLCache` メモリ上限を 0MB〜4MB に厳格制限。バックグラウンド移行時やメモリ警告時に自動で全キャッシュパージを実行。
- **モジュールW: GPUフレームバッファ強制圧縮 (Retinaリミッター)**
  WebViewの描画スケール（`contentScaleFactor` / `contentsScale`）を Retina 3x/2x から **1.0x / 1.5x** に制限。GPUフレームバッファ消費を最大1/4〜1/9に削減。さらに `backdrop-filter: blur()` や `box-shadow` 等の高負荷CSSを自動剥奪。
- **モジュールX: DOM物理刈り込み & 超軽量テキスト直結モード**
  画面外にスクロールアウトしたDOMノードを定期的に刈り取るDOM Pruningと、`<script>`, `<style>`, `<img>`, `<video>`, `<iframe>` を物理削除してプレーンテキストとリンクのみで描画するDOM Stripper。
- **モジュールT: WKWebViewプロセス強制デトックス (RAM即時リセット)**
  HUD上の「⚡」ボタンを1タップするだけで、閲覧履歴とスクロール位置を完全に維持したまま裏側のWebViewインスタンスを即座に再生成し、メモリをリセット。
- **モジュールAA: サーマルスロットリング回避・FPSリミッター**
  `ProcessInfo.processInfo.thermalState` を監視し、端末発熱検知時に `requestAnimationFrame` の上限FPSを 60fps → 30fps / 15fps に自動制限。
- **モジュールAB: メモリスパイク防止ストリーム**
  メモリプレッシャー緊急検知時にインメモリ画像や大容量レスポンスキャッシュを即座に破棄。
- **モジュールAC: 仮想タブツリー管理**
  開いている全タブを軽量メタデータで管理し、インメモリ上に実体化する `WKWebView` の数を1〜2個に厳格制限。100タブ開いていても実質1タブ分のRAM消費を実現。
- **モジュールAF: 自己修復クラッシュガード**
  WebContentプロセスのクラッシュ（`webViewWebContentProcessDidTerminate`）を検知した際、連続リロードループを防ぎつつ、クラッシュしたドメインを自動隔離して0.5秒でタブ状態を復元。

### 【第2部：チート級ランタイム・通信改ざん・自動化】

- **モジュールN: ネットワークオンザフライ書き換え (MITM)**
  `window.fetch` および `XMLHttpRequest` をフックし、URL正規表現にマッチしたリクエスト/レスポンスボディ（JSON/テキスト）をブラウザのレンダリング前にリアルタイム置換・モック返却。
- **モジュールO: JSタイムワープ & 制限全解除 (Anti-Anti-Debug)**
  `setTimeout`, `setInterval`, `requestAnimationFrame`, `Date.now()`, `performance.now()` をフックし、実行速度倍率を 0.1x〜50.0x までリアルタイム変更。さらにコピー禁止・右クリック禁止・選択禁止を解除し、`debugger;` ループを無効化。
- **モジュールP: RPA自動マクロ & オートクリッカー**
  座標タップ・CSSセレクタクリック・テキスト入力・スクロール・待機ステップを記録・編集し、指定回数または無限ループで自動実行。
- **モジュールQ-1: アンチアドブロック偽装シールド**
  AdBlock検知スクリプトが参照するダミー変数・関数を自動注入し、警告オーバーレイを無効化。
- **モジュールQ-2: フローティング・デュアルWebView (スプリットビュー)**
  画面50%分割またはリサイズ・ドラッグ移動可能な小窓WebViewをオーバーレイ表示し、2サイトを同時操作。
- **モジュールR: セッション・クローン (Cookie / Storage 一括移植)**
  `WKHTTPCookieStore`（`HttpOnly`含む）・`localStorage`・`sessionStorage` を1つのJSONにエクスポート/インポートし、別プロファイルや他端末へログイン状態を一瞬で移植。
- **モジュールS: 内蔵ローカルHTTPサーバー**
  Apple `Network.framework` (`NWListener`) を用い、同一Wi-Fi内のPCや他端末からiPhone内のDocumentsやダウンロード済みファイルへ直接ブラウザアクセス可能にする軽量サーバー（64KBチャンクストリーミング対応）。

### 【第3部：パワーユーザー開発・メディア・プライバシー・UI基盤】

- **モジュールB: ネイティブ高速ブロッカー & Userscriptエンジン**
  `WKContentRuleList` による高速広告遮断と、Tampermonkey互換メタデータ（`@match`, `@run-at`）対応の `.user.js` スクリプトマネージャー。
- **モジュールC: 最強メディア・バックグラウンド再生 & 強制PiP**
  `AVAudioSession` (`.playback`) ＋ `visibilitychange` 握りつぶしによる完全バックグラウンド再生と、任意の動画に対する強制Picture-in-Pictureボタン。
- **モジュールD: 内蔵DevTools & XHR/Fetchスニッファー**
  オンデバイスでDOMツリー、Consoleログ、Storage、通信履歴（100件リングバッファ、各64KB上限）を閲覧し、ワンタップでcURLコマンドをクリップボードに生成。
- **モジュールJ: WebSocket / SSE リアルタイム監視 & フレームインジェクター**
  送受信フレームのリアルタイム監視と、開いているソケットへの手動フレーム送信（インジェクション）。
- **モジュールE: プロファイル完全分離 & プロキシ / UA偽装**
  `WKWebsiteDataStore(forIdentifier: UUID)` によるデータ完全分離プロファイルと、SOCKS5/HTTPプロキシ設定、UA即時偽装。
- **モジュールF: AIページ要約 & 動的DOMカスタマイズ**
  Gemini / OpenAI APIキーを設定し、ページ本文の3行要約・翻訳、および「この要素を消して」などの自然言語指示によるCSS/JS自動生成＆適用。
- **モジュールG-1 & G-2: Sideload最適化 & ローカルファイラー**
  LiveContainer / AltStore / SideStore 環境でのApp Group・Keychainエラーの完全回避と、Documents内のHTML/JS/PDF/動画ファイルの直接プレビュー・インラインコード編集・タブ実行。
- **モジュールH: アンチ・フィンガープリンティング**
  URLクレンジング（`utm_*`, `fbclid`, `gclid` 等の自動切除）、Canvas/AudioContextノイズ注入、クロスオリジンRefererカット。
- **モジュールI: メディア一括抽出ダウンローダー & PDFオフライン保存**
  ページ内の動画（MP4/HLS）・音声・画像の一括ダウンロードと、ページ全体の単一PDFオフライン保存。
- **モジュールAD: オフライン全文検索ナレッジDB (SQLite FTS5)**
  閲覧したページの本文を軽量SQLite3 FTS5テーブルに自動保存し、電波のないオフライン環境でもキーワードで過去の閲覧履歴を爆速全文検索。
- **モジュールK: スマート強制ダークモード & ドメイン別カスタムCSS**
  画像・動画の色反転を防止する軽量スマートダークモードCSSと、ドメイン別のStylus互換カスタムCSSエディタ。
- **モジュールL & AE: 片手ジェスチャー & カスタムフローティングD-Pad**
  最上部/最下部スクロール・RAMデトックス・PiP・マクロ・DevToolsを片手で呼び出せる半透明フローティングボタン。
- **モジュールM: 自動リロード & DOM変化監視アラート**
  指定秒数ごとの自動リロードと、特定キーワード出現・要素変化を検知してローカル通知（`UNUserNotificationCenter`）を送信。

---

## 4. インストール方法 (Sideload / AltStore / TrollStore / LiveContainer)

本エディションは、サイドローディング環境向けにApp GroupやKeychainのフォールバックパッチ（`SideloadResiliencePatcher`）が組み込まれているため、以下のいずれの環境でもそのまま快適に動作します：

1. **TrollStore:** 脱獄不要で無期限署名インストール（最も推奨）。
2. **AltStore / SideStore:** 7日ごとの自動更新で動作。
3. **LiveContainer:** JIT・非署名実行環境でもApp Groupエラーなしで安定動作。

---

## 5. カスタマイズ・開発元クレジット

- **開発・カスタマイズ:** **Hikaproj**
- **X (Twitter):** [@hikaproj](https://x.com/hikaproj)
- **公式ウェブサイト:** [https://hikaproj.com](https://hikaproj.com)
- **お問い合わせ・フィードバック:** [https://hikaproj.com/new/contact](https://hikaproj.com/new/contact)

---

## 6. ライセンス

本プロジェクトは元の `mozilla-mobile/firefox-ios` と同様に [Mozilla Public License 2.0 (MPL-2.0)](https://mozilla.org/MPL/2.0/) に基づいて公開されています。
