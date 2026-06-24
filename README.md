# EyePal

iOS 視障輔助 App，整合多種 AI 視覺辨識功能，幫助視障用戶理解周遭環境。

## 功能

| 功能 | 說明 |
|------|------|
| **Quick Recognition** | 快速拍照描述場景（Moondream AI） |
| **Details Recognition** | 詳細場景描述 + 連續對話（ChatGPT/Codex API） |
| **Read Text** | OCR 文字辨識（MLKit，支援中日韓英等多語言） |
| **Faces** | 人臉辨識與記憶（ArcFace ONNX 模型） |
| **Floor Detection** | 樓層偵測 + 室内地圖 |
| **Chat** | 即時語音對話（WebRTC + OpenAI Realtime API） |
| **Lyric Prompter** | 歌詞搜尋與語音朗讀（LRCLIB + QQ Music + LLM） |

## 技術架構

- **Platform**: iOS 17+, Swift 5, SwiftUI
- **AI/ML**: OpenAI API (Codex Responses), Moondream AI, ArcFace ONNX, MLKit OCR
- **Audio**: WebRTC (即時語音), AVAudioEngine (HRTF 3D 音效)
- **Camera**: AVFoundation camera pipeline
- **Storage**: Keychain (API keys, OAuth tokens), UserDefaults (設定), JSON file (人臉資料)

## 歌詞資料來源

Lyric Prompter 功能從以下來源取得歌詞：

1. **LRCLIB** (`lrclib.net`) — 開放歌詞資料庫，免費無需 API key，支援 LRC 格式同步歌詞
2. **QQ Music** (`c.y.qq.com`) — QQ 音樂搜尋 API + QRC 歌詞解密
3. **LLM Fallback** — 當上述來源找不到時，使用 AI 搜尋（Codex/Gemini/OpenAI API）

參考項目：[Lyricify-Lyrics-Helper](https://github.com/WXRIW/Lyricify-Lyrics-Helper)（歌詞解析、搜尋、解密邏輯參考）

## 認證

- **ChatGPT/Codex**: OAuth2 + PKCE（透過 ChatGPT 帳號登入）
- **Moondream**: API Key（用戶自行輸入）
- **Gemini / OpenAI API**: API Key（用戶自行輸入）

## 建置

```bash
# 安裝 CocoaPods 依賴
pod install

# 下載 ArcFace ONNX 模型
mkdir -p tools/face_model/models
curl -L "https://huggingface.co/garavv/arcface-onnx/resolve/main/arc.onnx?download=true" \
  -o tools/face_model/models/arcface_fresh.onnx

# 開啟 Xcode
open EyePal.xcworkspace
```

## GitHub Actions

推送到 `main` 分支會自動觸發 unsigned IPA build。

手動觸發：
```bash
gh workflow run ios-unsigned-build.yml --ref main
```

下載 IPA：
```bash
gh run download <run_id> -n EyePal-unsigned-ipa -D ./artifacts-ipa
```

## 授權

參見 LICENSE 檔案。
