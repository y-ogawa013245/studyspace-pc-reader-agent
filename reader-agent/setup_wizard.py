"""
StudySpace - カードリーダー中継アプリ 対話型セットアップウィザード
"""

import os
import sys
import base64
import ctypes
from ctypes import wintypes
import json
import socket
import subprocess
import traceback
import urllib.request
import urllib.error
from datetime import datetime

# WindowsコンソールのUTF-8化
if sys.platform == "win32":
    try:
        sys.stdin.reconfigure(encoding="utf-8", errors="replace")
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if os.path.basename(SCRIPT_DIR) == ".core":
    BASE_DIR = os.path.dirname(SCRIPT_DIR)
else:
    BASE_DIR = SCRIPT_DIR

LOG_FILE = os.path.join(BASE_DIR, "setup.log")
CONFIG_FILE = os.path.join(BASE_DIR, "config.json")
START_BAT = os.path.join(BASE_DIR, "StudySpace.exe") if os.path.exists(os.path.join(BASE_DIR, "StudySpace.exe")) else (
    os.path.join(SCRIPT_DIR, "StudySpace.exe") if os.path.exists(os.path.join(SCRIPT_DIR, "StudySpace.exe")) else os.path.join(BASE_DIR, "start.bat")
)

def clean_str(s):
    if not isinstance(s, str):
        return s
    # BOMやサロゲート文字、制御文字を除去
    s = s.strip("\ufeff\u200b\r\n \t")
    return s.encode("utf-8", "ignore").decode("utf-8")

def log(msg, also_print=True):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    safe_msg = clean_str(str(msg))
    log_line = f"[{timestamp}] {safe_msg}"
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(log_line + "\n")
    except Exception:
        pass
    if also_print:
        print(safe_msg, flush=True)

def create_shortcut(target_path, shortcut_path, description="StudySpace カードリーダー"):
    target_dir = os.path.dirname(target_path)
    # 文字コードや日本語パスの誤爆を根絶するため、UTF-16LE + Base64 (-EncodedCommand) でPowerShellを実行
    ps_code = f"""
$ws = New-Object -ComObject WScript.Shell
$s = $ws.CreateShortcut("{shortcut_path}")
$s.TargetPath = "{target_path}"
$s.WorkingDirectory = "{target_dir}"
$s.Description = "{description}"
$s.Save()
"""
    encoded = base64.b64encode(ps_code.encode("utf-16le")).decode("ascii")
    cmd = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand", encoded]
    res = subprocess.run(cmd, capture_output=True, text=True, errors="replace")
    if res.returncode != 0:
        raise RuntimeError(f"PowerShell shortcut creation failed (code {res.returncode}): {res.stderr.strip()}")

def get_desktop_dir():
    # 1. Windows API (SHGetFolderPathW) でネイティブUnicode直接取得
    try:
        CSIDL_DESKTOPDIRECTORY = 0x0010
        buf = ctypes.create_unicode_buffer(wintypes.MAX_PATH)
        if ctypes.windll.shell32.SHGetFolderPathW(None, CSIDL_DESKTOPDIRECTORY, None, 0, buf) == 0:
            p = buf.value
            if p and os.path.exists(p):
                return p
    except Exception:
        pass

    # 2. PowerShell経由 (OEM/CP932でデコード)
    try:
        cmd = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", "[Environment]::GetFolderPath('Desktop')"]
        res = subprocess.run(cmd, capture_output=True)
        for enc in ["cp932", "utf-8"]:
            try:
                p = res.stdout.decode(enc).strip()
                if p and os.path.exists(p):
                    return p
            except Exception:
                pass
    except Exception:
        pass

    # 3. 一般的な環境変数フォールバック
    userprofile = os.environ.get("USERPROFILE", os.path.expanduser("~"))
    onedrive_desktop = os.path.join(userprofile, "OneDrive", "デスクトップ")
    if os.path.exists(onedrive_desktop):
        return onedrive_desktop
    local_desktop = os.path.join(userprofile, "Desktop")
    if os.path.exists(local_desktop):
        return local_desktop
    return os.path.expanduser("~")

def get_startup_dir():
    # 1. Windows API (SHGetFolderPathW) でネイティブUnicode直接取得
    try:
        CSIDL_STARTUP = 0x0007
        buf = ctypes.create_unicode_buffer(wintypes.MAX_PATH)
        if ctypes.windll.shell32.SHGetFolderPathW(None, CSIDL_STARTUP, None, 0, buf) == 0:
            p = buf.value
            if p and os.path.exists(p):
                return p
    except Exception:
        pass

    # 2. フォールバック
    appdata = os.environ.get("APPDATA", "")
    p = os.path.join(appdata, r"Microsoft\Windows\Start Menu\Programs\Startup")
    if os.path.exists(p):
        return p
    return os.path.expanduser("~")

def check_server_connectivity(base_url):
    test_url = base_url.rstrip("/") + "/api/kiosk-status"
    try:
        req = urllib.request.Request(test_url, headers={"User-Agent": "StudySpace-Setup/1.0"})
        with urllib.request.urlopen(req, timeout=5) as res:
            if res.status == 200:
                return True, "接続成功 (200 OK)"
            return True, f"接続確認 (HTTP {res.status})"
    except urllib.error.HTTPError as e:
        return True, f"サーバー応答あり (HTTP {e.code})"
    except Exception as e:
        return False, str(e)

def register_terminal_api(base_url, terminal_name):
    endpoint = base_url.rstrip("/") + "/api/terminals/register"
    payload = json.dumps({"name": terminal_name}).encode("utf-8")
    req = urllib.request.Request(
        endpoint,
        data=payload,
        headers={"Content-Type": "application/json; charset=utf-8", "User-Agent": "StudySpace-Setup/1.0"},
        method="POST"
    )
    with urllib.request.urlopen(req, timeout=10) as res:
        data = json.loads(res.read().decode("utf-8"))
        return data

def main():
    # ログ開始
    with open(LOG_FILE, "w", encoding="utf-8") as f:
        f.write(f"=== StudySpace セットアップウィザード開始: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} ===\n")

    print("\n" + "=" * 65)
    print("   StudySpace ICカードリーダー中継アプリ - かんたん初期セットアップ")
    print("=" * 65 + "\n")
    log("セットアップウィザードが起動しました。")

    try:
        # 1. サーバーURL設定
        print("【ステップ 1 / 4】StudySpace サーバーの接続先URLを設定します。")
        default_url = "http://127.0.0.1:8000"
        print("・自習室サーバーのURLを入力してください。")
        print("・ローカル実行の場合はそのまま Enter を押してください。")
        server_input = clean_str(input(f"接続先URL [デフォルト: {default_url}]: "))
        server_url = server_input if server_input else default_url
        server_url = server_url.rstrip("/")
        log(f"設定サーバーURL: {server_url}")

        # サーバー疎通テスト
        print(f"\n-> サーバー ({server_url}) への接続テストを実行中...")
        ok, msg = check_server_connectivity(server_url)
        if ok:
            log(f"サーバー接続テスト成功: {msg}")
            print(f"   [OK] {msg}")
        else:
            log(f"サーバー接続テスト警告: {msg}")
            print(f"   [警告] サーバーに接続できませんでした: {msg}")
            print("   ※サーバーが未起動の場合は、セットアップ完了後に起動してください。")
            proceed = clean_str(input("   このまま設定を続行しますか？ [Y/n]: ")).lower()
            if proceed == "n":
                log("ユーザーにより接続テスト失敗で中止されました。")
                print("\nセットアップを中止しました。")
                return

        # 2. 端末名の設定
        print("\n" + "-" * 65)
        print("【ステップ 2 / 4】受付端末（PC）の名前を設定します。")
        hostname = clean_str(socket.gethostname())
        default_name = f"受付PC-{hostname}"
        print("・管理ダッシュボードでこの端末を識別するための名前です。")
        name_input = clean_str(input(f"端末名 [デフォルト: {default_name}]: "))
        terminal_name = name_input if name_input else default_name
        log(f"設定端末名: {terminal_name}")

        # 3. 端末登録とAPIキーの発行
        print("\n" + "-" * 65)
        print("【ステップ 3 / 4】サーバーへの端末登録とAPIキー発行")
        api_key = None

        if ok:
            try:
                print("-> サーバーへ端末登録申請を送信中...")
                reg_data = register_terminal_api(server_url, terminal_name)
                api_key = reg_data.get("api_key")
                terminal_id = reg_data.get("terminal_id")
                log(f"端末登録API成功: terminal_id={terminal_id}, api_key={api_key[:8]}...")
                print(f"   [成功] 端末登録申請を受け付けました！ (端末ID: {terminal_id})")
                print("   ※管理画面の『端末管理』タブで【承認する】をクリックすると打刻が可能になります。")
            except Exception as e:
                log(f"端末登録API失敗: {e}\n{traceback.format_exc()}")
                print(f"   [注意] サーバーへの自動申請が完了できませんでした: {e}")
                print("   手動設定用のデフォルトキーで設定を続行します。")
                api_key = "test-terminal-api-key-12345"
        else:
            api_key = "test-terminal-api-key-12345"
            log("サーバー未接続のためデフォルトキーを設定")

        # config.json を安全に書き出し
        touch_api_url = f"{server_url}/api/touch"
        config_data = {
            "api_url": touch_api_url,
            "api_key": api_key,
            "terminal_name": terminal_name,
            "configured_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        }
        with open(CONFIG_FILE, "w", encoding="utf-8") as f:
            json.dump(config_data, f, ensure_ascii=False, indent=2)
        log(f"config.json を生成・保存しました: {CONFIG_FILE}")
        print(f"   [設定保存完了] config.json を生成しました。")

        # 4. デスクトップショートカット作成
        print("\n" + "-" * 65)
        print("【ステップ 4 / 4】ショートカット作成 ＆ 自動起動設定")
        desktop_dir = get_desktop_dir()
        shortcut_desktop = os.path.join(desktop_dir, "StudySpace カードリーダー.lnk")

        try:
            print(f"-> デスクトップにショートカットを作成中: {shortcut_desktop}")
            create_shortcut(START_BAT, shortcut_desktop)
            log(f"デスクトップショートカット作成成功: {shortcut_desktop}")
            print("   [成功] デスクトップに「StudySpace カードリーダー」を作成しました！")
        except Exception as e:
            log(f"デスクトップショートカット作成失敗: {e}\n{traceback.format_exc()}")
            print(f"   [警告] ショートカット作成に失敗しました: {e}")

        # スタートアップ自動起動の確認
        print("\nPC起動時に自動でカードリーダー中継を立ち上げますか？")
        autorun_input = clean_str(input("自動起動を有効にしますか？ [y/N (デフォルト: N)]: ")).lower()
        if autorun_input == "y":
            startup_dir = get_startup_dir()
            shortcut_startup = os.path.join(startup_dir, "StudySpace カードリーダー.lnk")
            try:
                create_shortcut(START_BAT, shortcut_startup)
                log(f"スタートアップショートカット作成成功: {shortcut_startup}")
                print("   [成功] Windows起動時の自動起動（スタートアップ）に登録しました！")
            except Exception as e:
                log(f"スタートアップショートカット作成失敗: {e}\n{traceback.format_exc()}")
                print(f"   [警告] スタートアップ登録に失敗しました: {e}")
        else:
            log("スタートアップ登録はスキップされました。")
            print("   [スキップ] 手動起動のみに設定しました。")

        # 完了案内
        print("\n" + "=" * 65)
        print("   すべてのセットアップが正常に完了しました！")
        print("=" * 65)
        print(f"・設定ログファイル: {LOG_FILE}")
        print("・デスクトップの「StudySpace カードリーダー」アイコンからいつでも起動できます。\n")
        log("セットアップウィザードが正常終了しました。")

        # 即時起動の確認
        launch_input = clean_str(input("今すぐカードリーダー中継アプリを起動しますか？ [Y/n (デフォルト: Y)]: ")).lower()
        if launch_input != "n":
            log("ユーザーの選択により中継アプリを即時起動します。")
            subprocess.Popen(["cmd.exe", "/c", START_BAT], cwd=BASE_DIR, creationflags=subprocess.CREATE_NEW_CONSOLE)

    except Exception as e:
        error_msg = f"予期せぬエラーが発生しました: {e}"
        log(f"{error_msg}\n{traceback.format_exc()}")
        print(f"\n[重大なエラー] {error_msg}")
        print(f"詳細なエラー情報はログファイルをご確認ください: {LOG_FILE}")
    finally:
        print("\nEnterキーを押すとこの画面を閉じます...")
        try:
            input()
        except Exception:
            pass

if __name__ == "__main__":
    main()
