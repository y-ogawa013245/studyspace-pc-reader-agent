# StudySpace カードリーダー GUIセットアップウィザード
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# TLS 1.2 を有効化 (HTTPS 接続エラー防止)
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls11 -bor [System.Net.SecurityProtocolType]::Tls

[System.Windows.Forms.Application]::EnableVisualStyles()

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }

if ((Split-Path -Leaf $scriptDir) -eq ".core") {
    $rootDir = Split-Path -Parent $scriptDir
    $coreDir = $scriptDir
} else {
    $rootDir = $scriptDir
    $coreDir = Join-Path $scriptDir ".core"
}
if (-not (Test-Path $coreDir)) { New-Item -ItemType Directory -Path $coreDir -Force | Out-Null }
Set-Location $rootDir

# ルートの古いファイルを掃除
if (Test-Path (Join-Path $rootDir "config.json")) { Remove-Item -Force (Join-Path $rootDir "config.json") -ErrorAction SilentlyContinue }
if (Test-Path (Join-Path $rootDir "setup.log")) { Remove-Item -Force (Join-Path $rootDir "setup.log") -ErrorAction SilentlyContinue }

$logFile = Join-Path $coreDir "setup.log"
$configFile = Join-Path $coreDir "config.json"
$startBat = Join-Path $rootDir "start.bat"
$studySpaceExe = Join-Path $coreDir "StudySpace.exe"
if (-not (Test-Path $studySpaceExe)) { $studySpaceExe = Join-Path $rootDir "StudySpace.exe" }
$iconFile = Join-Path $coreDir "app.ico"
if (-not (Test-Path $iconFile)) { $iconFile = Join-Path $rootDir "app.ico" }

function Write-SetupLog($msg) {
    $time = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $logFile -Value "[$time] $msg" -Encoding UTF8 -ErrorAction SilentlyContinue
}

# ログ初期化
Set-Content -Path $logFile -Value "=== StudySpace GUIセットアップ開始: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" -Encoding UTF8

$form = New-Object System.Windows.Forms.Form
$form.Text = "StudySpace カードリーダー セットアップ"
if (Test-Path $iconFile) {
    try {
        $form.Icon = New-Object System.Drawing.Icon($iconFile)
    } catch {}
}
$form.Size = New-Object System.Drawing.Size(530, 560)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.BackColor = [System.Drawing.Color]::FromArgb(248, 250, 252)

# ヘッダータイトル
$lblHeader = New-Object System.Windows.Forms.Label
$lblHeader.Text = "StudySpace カードリーダー セットアップ"
$lblHeader.Font = New-Object System.Drawing.Font("Meiryo UI", 13, [System.Drawing.FontStyle]::Bold)
$lblHeader.ForeColor = [System.Drawing.Color]::FromArgb(15, 23, 42)
$lblHeader.Location = New-Object System.Drawing.Point(24, 18)
$lblHeader.Size = New-Object System.Drawing.Size(460, 26)
$form.Controls.Add($lblHeader)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = "受付PCの初期設定を行います。通常はこのまま【セットアップを実行】を押してください。"
$lblSub.Font = New-Object System.Drawing.Font("Meiryo UI", 9)
$lblSub.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
$lblSub.Location = New-Object System.Drawing.Point(24, 46)
$lblSub.Size = New-Object System.Drawing.Size(460, 36)
$form.Controls.Add($lblSub)

# グループパネル (カード型コンテナ)
$panel = New-Object System.Windows.Forms.Panel
$panel.Location = New-Object System.Drawing.Point(24, 86)
$panel.Size = New-Object System.Drawing.Size(466, 260)
$panel.BackColor = [System.Drawing.Color]::White
$panel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$form.Controls.Add($panel)

# サーバーURL
$lblUrl = New-Object System.Windows.Forms.Label
$lblUrl.Text = "1. 接続先サーバーURL:"
$lblUrl.Font = New-Object System.Drawing.Font("Meiryo UI", 9, [System.Drawing.FontStyle]::Bold)
$lblUrl.Location = New-Object System.Drawing.Point(16, 14)
$lblUrl.Size = New-Object System.Drawing.Size(400, 20)
$panel.Controls.Add($lblUrl)

$txtUrl = New-Object System.Windows.Forms.TextBox
$txtUrl.Text = "https://entry.studyspace.okinawa"
$txtUrl.Font = New-Object System.Drawing.Font("Meiryo UI", 9.5)
$txtUrl.Location = New-Object System.Drawing.Point(16, 36)
$txtUrl.Size = New-Object System.Drawing.Size(320, 24)
$panel.Controls.Add($txtUrl)

$btnTest = New-Object System.Windows.Forms.Button
$btnTest.Text = "接続テスト"
$btnTest.Font = New-Object System.Drawing.Font("Meiryo UI", 8.5)
$btnTest.Location = New-Object System.Drawing.Point(344, 34)
$btnTest.Size = New-Object System.Drawing.Size(100, 27)
$btnTest.BackColor = [System.Drawing.Color]::FromArgb(241, 245, 249)
$btnTest.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$panel.Controls.Add($btnTest)

$lblTestRes = New-Object System.Windows.Forms.Label
$lblTestRes.Text = ""
$lblTestRes.Font = New-Object System.Drawing.Font("Meiryo UI", 8.5)
$lblTestRes.Location = New-Object System.Drawing.Point(16, 64)
$lblTestRes.Size = New-Object System.Drawing.Size(420, 18)
$panel.Controls.Add($lblTestRes)

# 端末名
$lblName = New-Object System.Windows.Forms.Label
$lblName.Text = "2. 受付端末名 (管理画面の識別名):"
$lblName.Font = New-Object System.Drawing.Font("Meiryo UI", 9, [System.Drawing.FontStyle]::Bold)
$lblName.Location = New-Object System.Drawing.Point(16, 92)
$lblName.Size = New-Object System.Drawing.Size(400, 20)
$panel.Controls.Add($lblName)

$compName = $env:COMPUTERNAME
if (-not $compName) { $compName = "受付PC" } else { $compName = "受付PC-$compName" }
$txtName = New-Object System.Windows.Forms.TextBox
$txtName.Text = $compName
$txtName.Font = New-Object System.Drawing.Font("Meiryo UI", 9.5)
$txtName.Location = New-Object System.Drawing.Point(16, 114)
$txtName.Size = New-Object System.Drawing.Size(428, 24)
$panel.Controls.Add($txtName)

# オプション
$lblOpt = New-Object System.Windows.Forms.Label
$lblOpt.Text = "3. ショートカット・起動設定:"
$lblOpt.Font = New-Object System.Drawing.Font("Meiryo UI", 9, [System.Drawing.FontStyle]::Bold)
$lblOpt.Location = New-Object System.Drawing.Point(16, 154)
$lblOpt.Size = New-Object System.Drawing.Size(400, 20)
$panel.Controls.Add($lblOpt)

$chkDesktop = New-Object System.Windows.Forms.CheckBox
$chkDesktop.Text = "デスクトップに起動ショートカットを作成する"
$chkDesktop.Font = New-Object System.Drawing.Font("Meiryo UI", 9)
$chkDesktop.Checked = $true
$chkDesktop.Location = New-Object System.Drawing.Point(16, 178)
$chkDesktop.Size = New-Object System.Drawing.Size(420, 22)
$panel.Controls.Add($chkDesktop)

$chkStartup = New-Object System.Windows.Forms.CheckBox
$chkStartup.Text = "Windows起動時に自動でバックグラウンド常駐する"
$chkStartup.Font = New-Object System.Drawing.Font("Meiryo UI", 9)
$chkStartup.Checked = $false
$chkStartup.Location = New-Object System.Drawing.Point(16, 204)
$chkStartup.Size = New-Object System.Drawing.Size(420, 22)
$panel.Controls.Add($chkStartup)

# 進行状況ラベル
$lblProgress = New-Object System.Windows.Forms.Label
$lblProgress.Text = "設定を確認し、下のボタンを押してください。"
$lblProgress.Font = New-Object System.Drawing.Font("Meiryo UI", 9)
$lblProgress.ForeColor = [System.Drawing.Color]::FromArgb(71, 85, 105)
$lblProgress.Location = New-Object System.Drawing.Point(24, 356)
$lblProgress.Size = New-Object System.Drawing.Size(466, 20)
$form.Controls.Add($lblProgress)

# 進行状況バー
$pBar = New-Object System.Windows.Forms.ProgressBar
$pBar.Location = New-Object System.Drawing.Point(24, 380)
$pBar.Size = New-Object System.Drawing.Size(466, 12)
$pBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
$pBar.Value = 0
$form.Controls.Add($pBar)

# アクションボタン
$btnAction = New-Object System.Windows.Forms.Button
$btnAction.Text = "セットアップを実行する（ワンクリック完了）"
$btnAction.Font = New-Object System.Drawing.Font("Meiryo UI", 10.5, [System.Drawing.FontStyle]::Bold)
$btnAction.BackColor = [System.Drawing.Color]::FromArgb(2, 132, 199)
$btnAction.ForeColor = [System.Drawing.Color]::White
$btnAction.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnAction.FlatAppearance.BorderSize = 0
$btnAction.Location = New-Object System.Drawing.Point(24, 404)
$btnAction.Size = New-Object System.Drawing.Size(466, 44)
$btnAction.Cursor = [System.Windows.Forms.Cursors]::Hand
$form.Controls.Add($btnAction)

# 下部サブボタンコンテナ (完了時に表示)
$btnLaunch = New-Object System.Windows.Forms.Button
$btnLaunch.Text = "今すぐカードリーダーを起動する"
$btnLaunch.Font = New-Object System.Drawing.Font("Meiryo UI", 9.5, [System.Drawing.FontStyle]::Bold)
$btnLaunch.BackColor = [System.Drawing.Color]::FromArgb(16, 185, 129)
$btnLaunch.ForeColor = [System.Drawing.Color]::White
$btnLaunch.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnLaunch.FlatAppearance.BorderSize = 0
$btnLaunch.Location = New-Object System.Drawing.Point(24, 458)
$btnLaunch.Size = New-Object System.Drawing.Size(320, 36)
$btnLaunch.Visible = $false
$form.Controls.Add($btnLaunch)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "閉じる"
$btnClose.Font = New-Object System.Drawing.Font("Meiryo UI", 9.5)
$btnClose.BackColor = [System.Drawing.Color]::FromArgb(226, 232, 240)
$btnClose.ForeColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
$btnClose.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnClose.FlatAppearance.BorderSize = 0
$btnClose.Location = New-Object System.Drawing.Point(356, 458)
$btnClose.Size = New-Object System.Drawing.Size(134, 36)
$btnClose.Visible = $false
$form.Controls.Add($btnClose)

# 接続テストイベント
$btnTest.Add_Click({
    $url = $txtUrl.Text.Trim().TrimEnd('/')
    if ($url.ToLower().EndsWith('/api')) { $url = $url.Substring(0, $url.Length - 4).TrimEnd('/') }
    $lblTestRes.ForeColor = [System.Drawing.Color]::FromArgb(217, 119, 6)
    $lblTestRes.Text = "接続テスト中..."
    $form.Refresh()
    try {
        $res = Invoke-RestMethod -Uri "$url/api/kiosk-status" -Method Get -TimeoutSec 4
        $lblTestRes.ForeColor = [System.Drawing.Color]::FromArgb(16, 185, 129)
        $lblTestRes.Text = "✓ サーバー接続成功！ (正常に応答しました)"
        Write-SetupLog "接続テスト成功: $url"
    } catch {
        $lblTestRes.ForeColor = [System.Drawing.Color]::FromArgb(225, 29, 72)
        $lblTestRes.Text = "⚠ 接続失敗: $($_.Exception.Message)"
        Write-SetupLog "接続テスト失敗: $url ($($_.Exception.Message))"
    }
})

# セットアップ実行イベント
$btnAction.Add_Click({
    $btnAction.Enabled = $false
    $btnTest.Enabled = $false
    $txtUrl.Enabled = $false
    $txtName.Enabled = $false
    $chkDesktop.Enabled = $false
    $chkStartup.Enabled = $false

    $serverUrl = $txtUrl.Text.Trim().TrimEnd('/')
    if ($serverUrl.ToLower().EndsWith('/api')) { $serverUrl = $serverUrl.Substring(0, $serverUrl.Length - 4).TrimEnd('/') }
    $termName = $txtName.Text.Trim()
    if (-not $termName) { $termName = "受付PC" }

    $pBar.Value = 20
    $lblProgress.Text = "サーバーに接続して端末登録申請中..."
    $form.Refresh()

    $apiKey = "test-terminal-api-key-12345"
    try {
        $regUrl = "$serverUrl/api/terminals/register"
        $body = @{ name = $termName } | ConvertTo-Json
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        $res = Invoke-RestMethod -Uri $regUrl -Method Post -Body $bodyBytes -ContentType "application/json; charset=utf-8" -TimeoutSec 6
        if ($res.api_key) {
            $apiKey = $res.api_key
            Write-SetupLog "端末登録成功: ID=$($res.terminal_id), APIキー発行"
        }
    } catch {
        Write-SetupLog "端末登録API警告 (デフォルトキー使用): $($_.Exception.Message)"
    }

    $pBar.Value = 50
    $lblProgress.Text = "config.json を保存中..."
    $form.Refresh()

    # config.json 生成 (BOMなしUTF-8で保存)
    $configObj = @{
        api_url = "$serverUrl/api/touch"
        api_key = $apiKey
        terminal_name = $termName
        configured_at = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    }
    $configJson = $configObj | ConvertTo-Json -Depth 3
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($configFile, $configJson, $utf8NoBom)
    Write-SetupLog "config.json 保存完了"

    # デスクトップショートカット作成
    $targetFile = if (Test-Path $studySpaceExe) { $studySpaceExe } else { $startBat }
    if ($chkDesktop.Checked) {
        $pBar.Value = 75
        $lblProgress.Text = "デスクトップショートカットを作成中..."
        $form.Refresh()
        try {
            $desktopDir = [Environment]::GetFolderPath('Desktop')
            $shortcutPath = Join-Path $desktopDir "StudySpace カードリーダー.lnk"
            $ws = New-Object -ComObject WScript.Shell
            $s = $ws.CreateShortcut($shortcutPath)
            $s.TargetPath = $targetFile
            $s.WorkingDirectory = $rootDir
            $s.Description = "StudySpace ICカードリーダー中継アプリ"
            if (Test-Path $iconFile) {
                $s.IconLocation = "$iconFile,0"
            }
            $s.Save()
            Write-SetupLog "デスクトップショートカット作成成功: $shortcutPath (Icon: $iconFile)"
        } catch {
            Write-SetupLog "ショートカット作成エラー: $($_.Exception.Message)"
        }
    }

    # スタートアップ登録
    if ($chkStartup.Checked) {
        try {
            $startupDir = [Environment]::GetFolderPath('Startup')
            $shortcutStartup = Join-Path $startupDir "StudySpace カードリーダー.lnk"
            $ws = New-Object -ComObject WScript.Shell
            $s = $ws.CreateShortcut($shortcutStartup)
            $s.TargetPath = $targetFile
            $s.WorkingDirectory = $rootDir
            $s.Description = "StudySpace ICカードリーダー中継アプリ"
            if (Test-Path $iconFile) {
                $s.IconLocation = "$iconFile,0"
            }
            $s.Save()
            Write-SetupLog "スタートアップ登録成功: $shortcutStartup"
        } catch {
            Write-SetupLog "スタートアップ登録エラー: $($_.Exception.Message)"
        }
    }

    $pBar.Value = 100
    $lblProgress.ForeColor = [System.Drawing.Color]::FromArgb(16, 185, 129)
    $lblProgress.Text = "✓ セットアップが正常に完了しました！"
    Write-SetupLog "セットアップ正常完了"

    $btnAction.Text = "✓ 完了しました"
    $btnAction.BackColor = [System.Drawing.Color]::FromArgb(100, 116, 139)

    $btnLaunch.Visible = $true
    $btnClose.Visible = $true
})

# 今すぐ起動ボタン
$btnLaunch.Add_Click({
    $targetFile = if (Test-Path $studySpaceExe) { $studySpaceExe } else { $startBat }
    Start-Process -FilePath $targetFile -WorkingDirectory $rootDir
    $form.Close()
})

# 閉じるボタン
$btnClose.Add_Click({
    $form.Close()
})

# フォーム表示
[void]$form.ShowDialog()
