#!/bin/bash
# ==============================================================================
# StudySpace カードリーダー中継アプリ - macOS セットアップウィザード
# Finderからダブルクリックで実行できます。
# ==============================================================================

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

# .core フォルダが存在する場合は coreDir を設定
if [ -d ".core" ]; then
    CORE_DIR="$DIR/.core"
else
    CORE_DIR="$DIR/.core"
    mkdir -p "$CORE_DIR"
fi

CONFIG_FILE="$CORE_DIR/config.json"
LOG_FILE="$CORE_DIR/setup.log"
PYTHON_CMD="python3"

# ルートに古いファイルがあれば掃除
rm -f "$DIR/config.json" "$DIR/setup.log"

echo "=== StudySpace macOS Setup ===" > "$LOG_FILE"

# Python3 の確認
if ! command -v python3 &> /dev/null; then
    osascript -e 'display alert "Python 3 が見つかりません" message "macOSにPython 3がインストールされていません。Homebrewまたはpython.orgからインストールしてください。" as critical'
    exit 1
fi

# 1. サーバーURLの入力ダイアログ
DEFAULT_URL="https://entry.studyspace.okinawa"
SERVER_URL=$(osascript -e "try
    display dialog \"StudySpace サーバーの接続先URLを入力してください:\" default answer \"$DEFAULT_URL\" with title \"StudySpace セットアップ\" buttons {\"キャンセル\", \"次へ\"} default button \"次へ\" with icon note
    text returned of result
on error
    return \"CANCEL\"
end try")

if [ "$SERVER_URL" = "CANCEL" ] || [ -z "$SERVER_URL" ]; then
    exit 0
fi

# 末尾のスラッシュを削除
SERVER_URL="${SERVER_URL%/}"
# 末尾の /api を自動削除
SERVER_URL="${SERVER_URL%/api}"
SERVER_URL="${SERVER_URL%/}"

# 2. 端末名の入力ダイアログ
HOST_NAME=$(scutil --get ComputerName 2>/dev/null || hostname -s 2>/dev/null || echo "Mac")
DEFAULT_NAME="受付Mac-$HOST_NAME"
TERM_NAME=$(osascript -e "try
    display dialog \"管理画面で識別する受付端末名を入力してください:\" default answer \"$DEFAULT_NAME\" with title \"StudySpace セットアップ\" buttons {\"キャンセル\", \"登録する\"} default button \"登録する\" with icon note
    text returned of result
on error
    return \"CANCEL\"
end try")

if [ "$TERM_NAME" = "CANCEL" ] || [ -z "$TERM_NAME" ]; then
    exit 0
fi

echo "サーバーURL: $SERVER_URL" >> "$LOG_FILE"
echo "端末名: $TERM_NAME" >> "$LOG_FILE"

# 3. サーバー接続 & 端末登録API
API_KEY="test-terminal-api-key-12345"
REG_RESPONSE=$(curl -s -X POST "$SERVER_URL/api/terminals/register" \
    -H "Content-Type: application/json; charset=utf-8" \
    -H "User-Agent: StudySpace-Mac-Setup/1.0" \
    -d "{\"name\":\"$TERM_NAME\"}" \
    --max-time 6)

if [ $? -eq 0 ] && [ -n "$REG_RESPONSE" ]; then
    # JSONからapi_keyを簡易抽出
    EXT_KEY=$(echo "$REG_RESPONSE" | grep -o '"api_key":"[^"]*' | cut -d'"' -f4)
    if [ -n "$EXT_KEY" ]; then
        API_KEY="$EXT_KEY"
        echo "端末登録成功: APIキー発行" >> "$LOG_FILE"
    fi
fi

# 4. config.json の生成
DATE_STR=$(date "+%Y-%m-%d %H:%M:%S")
cat <<EOF > "$CONFIG_FILE"
{
  "api_url": "$SERVER_URL/api/touch",
  "api_key": "$API_KEY",
  "terminal_name": "$TERM_NAME",
  "configured_at": "$DATE_STR"
}
EOF

echo "config.json 作成完了: $CONFIG_FILE" >> "$LOG_FILE"

# 5. デスクトップに起動用ショートカット（.command）を作成
DESKTOP_DIR="$HOME/Desktop"
DESKTOP_LAUNCHER="$DESKTOP_DIR/StudySpace カードリーダー.command"

cat <<EOF > "$DESKTOP_LAUNCHER"
#!/bin/bash
DIR="$DIR"
cd "\$DIR"
if [ -f ".core/reader_agent.py" ]; then
    python3 .core/reader_agent.py
else
    python3 reader_agent.py
fi
EOF

chmod +x "$DESKTOP_LAUNCHER"
echo "デスクトップショートカット作成完了: $DESKTOP_LAUNCHER" >> "$LOG_FILE"

# 6. セットアップ完了通知ダイアログ
RES_ACTION=$(osascript -e "try
    display dialog \"🎉 StudySpace カードリーダーのセットアップが完了しました！\n\n・デスクトップに『StudySpace カードリーダー』を作成しました。\n・管理画面の『端末管理』タブで端末を承認すると打刻が可能になります。\" with title \"セットアップ完了\" buttons {\"閉じる\", \"今すぐ起動\"} default button \"今すぐ起動\" with icon note
    button returned of result
on error
    return \"閉じる\"
end try")

if [ "$RES_ACTION" = "今すぐ起動" ]; then
    open "$DESKTOP_LAUNCHER"
fi

exit 0
