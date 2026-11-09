"""
StudySpace - ICカードリーダー中継アプリ (本番配布用)
Sony Pasori RC-S300 / FeliCa 対応
"""

import ctypes
import json
import os
import sys
import time
import urllib.error
import urllib.request

# 設定ファイルのパス
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if os.path.basename(SCRIPT_DIR) == ".core":
    CORE_DIR = SCRIPT_DIR
    BASE_DIR = os.path.dirname(SCRIPT_DIR)
else:
    BASE_DIR = SCRIPT_DIR
    CORE_DIR = os.path.join(SCRIPT_DIR, ".core")

CONFIG_PATH = os.path.join(CORE_DIR, "config.json")
if not os.path.exists(CONFIG_PATH) and os.path.exists(os.path.join(BASE_DIR, "config.json")):
    CONFIG_PATH = os.path.join(BASE_DIR, "config.json")

# デフォルト設定
DEFAULT_CONFIG = {
    "api_url": "http://127.0.0.1:8000/api/touch",
    "api_key": "test-terminal-api-key-12345",
    "terminal_name": "受付端末",
}

def load_config():
    global CONFIG_PATH
    if not os.path.exists(CONFIG_PATH):
        if os.path.exists(os.path.join(CORE_DIR, "config.json")):
            CONFIG_PATH = os.path.join(CORE_DIR, "config.json")
        elif os.path.exists(os.path.join(BASE_DIR, "config.json")):
            CONFIG_PATH = os.path.join(BASE_DIR, "config.json")

    if not os.path.exists(CONFIG_PATH):
        print("=======================================================", flush=True)
        print(" [初期設定未完了] config.json が見つかりません。", flush=True)
        print(" 先に「setup.exe」または「setup.bat」を実行して初期セットアップを行ってください。", flush=True)
        print("=======================================================", flush=True)
        wizard_path = os.path.join(SCRIPT_DIR, "setup_wizard.py")
        if not os.path.exists(wizard_path):
            wizard_path = os.path.join(BASE_DIR, "setup_wizard.py")
        if os.path.exists(wizard_path):
            print("セットアップウィザードを起動します...\n", flush=True)
            try:
                import setup_wizard
                setup_wizard.main()
            except Exception as e:
                print(f"ウィザード起動エラー: {e}", flush=True)
        if os.path.exists(CONFIG_PATH):
            return load_config()
        print("初期設定が完了していないため終了します。", flush=True)
        sys.exit(1)

    try:
        with open(CONFIG_PATH, "r", encoding="utf-8-sig") as f:
            data = json.load(f)
            # 必須フィールドのチェック
            if not data.get("api_url"):
                data["api_url"] = DEFAULT_CONFIG["api_url"]
            if not data.get("api_key"):
                data["api_key"] = DEFAULT_CONFIG["api_key"]
            return data
    except Exception as e:
        print(f"[警告] config.json 読み込み失敗、デフォルト値を使用します: {e}", flush=True)
        return DEFAULT_CONFIG

IS_WIN = sys.platform == "win32"
IS_MAC = sys.platform == "darwin"

# Windowsコンソールの文字化け対策 (UTF-8)
if IS_WIN:
    os.system("chcp 65001 > nul")

SCARD_SCOPE_USER = 0
SCARD_SHARE_SHARED = 2
SCARD_PROTOCOL_T0 = 1
SCARD_PROTOCOL_T1 = 2
SCARD_STATE_UNAWARE = 0x00000000
SCARD_STATE_PRESENT = 0x00000020
SCARD_STATE_EMPTY = 0x00000010

if IS_WIN:
    winscard = ctypes.windll.winscard
    ReaderStringType = ctypes.c_wchar_p
    def create_readers_buffer(size):
        return ctypes.create_unicode_buffer(size)
    def parse_readers(buffer):
        return [r for r in buffer.value.split("\x00") if r]
    def to_reader_param(name):
        return name
    fn_ListReaders = winscard.SCardListReadersW
    fn_Connect = winscard.SCardConnectW
    fn_GetStatusChange = winscard.SCardGetStatusChangeW
elif IS_MAC:
    winscard = ctypes.cdll.LoadLibrary("/System/Library/Frameworks/PCSC.framework/PCSC")
    ReaderStringType = ctypes.c_char_p
    def create_readers_buffer(size):
        return ctypes.create_string_buffer(size)
    def parse_readers(buffer):
        raw = bytes(buffer.raw)
        return [r.decode("utf-8", "ignore") for r in raw.split(b"\x00") if r]
    def to_reader_param(name):
        return name.encode("utf-8")
    fn_ListReaders = winscard.SCardListReaders
    fn_Connect = winscard.SCardConnect
    fn_GetStatusChange = winscard.SCardGetStatusChange
else:
    try:
        winscard = ctypes.cdll.LoadLibrary("libpcsclite.so.1")
    except Exception:
        winscard = ctypes.cdll.LoadLibrary("libpcsclite.so")
    ReaderStringType = ctypes.c_char_p
    def create_readers_buffer(size):
        return ctypes.create_string_buffer(size)
    def parse_readers(buffer):
        raw = bytes(buffer.raw)
        return [r.decode("utf-8", "ignore") for r in raw.split(b"\x00") if r]
    def to_reader_param(name):
        return name.encode("utf-8")
    fn_ListReaders = winscard.SCardListReaders
    fn_Connect = winscard.SCardConnect
    fn_GetStatusChange = winscard.SCardGetStatusChange

class SCARD_IO_REQUEST(ctypes.Structure):
    _fields_ = [
        ("dwProtocol", ctypes.c_ulong),
        ("cbPciLength", ctypes.c_ulong),
    ]

class SCARD_READERSTATE(ctypes.Structure):
    _fields_ = [
        ("szReader", ReaderStringType),
        ("pvUserData", ctypes.c_void_p),
        ("dwCurrentState", ctypes.c_ulong),
        ("dwEventState", ctypes.c_ulong),
        ("cbAtr", ctypes.c_ulong),
        ("rgbAtr", ctypes.c_ubyte * 36),
    ]

def send_touch_api(api_url, api_key, idm):
    payload = json.dumps({"idm": idm}).encode("utf-8")
    req = urllib.request.Request(
        api_url,
        data=payload,
        headers={
            "Content-Type": "application/json",
            "X-Api-Key": api_key,
            "User-Agent": "StudySpace-RC-S300-Agent/1.0",
            "Connection": "close",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as res:
            data = json.loads(res.read().decode("utf-8"))
            msg = data.get("message", "打刻が記録されました")
            member_name = data.get("member_name", "")
            action = "入室" if data.get("type") == "entry" else "退室"
            print(f"  [成功] {member_name} 様 ({action}): {msg}", flush=True)
            return data
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8")
        try:
            err = json.loads(body)
            status = err.get("status", "")
            msg = err.get("message", e.reason)
            if status == "unregistered":
                print(f"  [未登録カード] IDm: {idm} は未登録です。管理画面から登録してください。", flush=True)
            else:
                print(f"  [サーバー通知: {status}] {msg}", flush=True)
            return err
        except Exception:
            print(f"  [エラー] HTTP {e.code}: {e.reason}", flush=True)
    except Exception as e:
        print(f"  [通信エラー] サーバーに接続できませんでした: {e}", flush=True)
    return None

def read_idm(hContext, reader_name):
    hCard = ctypes.c_void_p()
    active_proto = ctypes.c_ulong()

    ret = fn_Connect(
        hContext,
        to_reader_param(reader_name),
        SCARD_SHARE_SHARED,
        SCARD_PROTOCOL_T0 | SCARD_PROTOCOL_T1,
        ctypes.byref(hCard),
        ctypes.byref(active_proto),
    )
    if ret != 0:
        return None

    try:
        io_req = SCARD_IO_REQUEST()
        io_req.dwProtocol = active_proto.value
        io_req.cbPciLength = ctypes.sizeof(io_req)

        # APDU: Get UID / IDm
        apdu = (ctypes.c_ubyte * 5)(0xFF, 0xCA, 0x00, 0x00, 0x00)
        recv_buf = (ctypes.c_ubyte * 256)()
        recv_len = ctypes.c_ulong(len(recv_buf))

        ret = winscard.SCardTransmit(
            hCard,
            ctypes.byref(io_req),
            apdu,
            len(apdu),
            None,
            recv_buf,
            ctypes.byref(recv_len),
        )

        if ret == 0 and recv_len.value >= 2:
            sw1 = recv_buf[recv_len.value - 2]
            sw2 = recv_buf[recv_len.value - 1]
            if sw1 == 0x90 and sw2 == 0x00:
                idm_bytes = bytes(recv_buf[:recv_len.value - 2])
                return idm_bytes.hex().upper()
    finally:
        winscard.SCardDisconnect(hCard, 0)
    return None

def main():
    config = load_config()

    print("=======================================================", flush=True)
    print("   StudySpace - ICカードリーダー中継アプリ (RC-S300)", flush=True)
    print("=======================================================", flush=True)
    print(f" 端末名       : {config.get('terminal_name')}", flush=True)
    print(f" 接続先URL    : {config.get('api_url')}", flush=True)
    print("-------------------------------------------------------", flush=True)

    while True:
        hContext = ctypes.c_void_p()
        ret = winscard.SCardEstablishContext(SCARD_SCOPE_USER, None, None, ctypes.byref(hContext))
        if ret != 0:
            print(f"[待機] スマートカードサービスを待機中... (0x{ret:X})", flush=True)
            time.sleep(3)
            continue

        try:
            # リーダーの検出ループ
            target_reader = None
            while not target_reader:
                pcchReaders = ctypes.c_ulong()
                ret = fn_ListReaders(hContext, None, None, ctypes.byref(pcchReaders))
                if ret == 0 and pcchReaders.value > 0:
                    mszReaders = create_readers_buffer(pcchReaders.value)
                    fn_ListReaders(hContext, None, mszReaders, ctypes.byref(pcchReaders))
                    readers = parse_readers(mszReaders)
                    if readers:
                        target_reader = readers[0]
                        break
                print("[未検出] カードリーダーが見つかりません。USBにRC-S300を接続してください...", flush=True)
                time.sleep(3)

            print(f"\n[接続完了] リーダーを認識しました: {target_reader}", flush=True)
            print("ICカード（学生証、Suica/PASMO等）をリーダーにかざしてください。\n", flush=True)

            reader_state = SCARD_READERSTATE()
            reader_state.szReader = to_reader_param(target_reader)
            reader_state.dwCurrentState = SCARD_STATE_UNAWARE

            states = (SCARD_READERSTATE * 1)(reader_state)
            fn_GetStatusChange(hContext, 0, states, 1)
            states[0].dwCurrentState = states[0].dwEventState

            last_idm = None

            while True:
                ret = fn_GetStatusChange(hContext, 200, states, 1)
                u_ret = ctypes.c_ulong(ret).value

                # タイムアウト (200ms間カード変化なし) は正常な待機状態
                if u_ret == 0x8010000A:
                    time.sleep(0.05)
                    continue

                # リーダーが取り外された場合や致命的エラー
                if u_ret != 0 or bool(states[0].dwEventState & 0x00001000): # SCARD_STATE_UNAVAILABLE
                    print("\n[切断] カードリーダーとの接続が切れました。再接続を待機します...", flush=True)
                    break

                is_present = bool(states[0].dwEventState & SCARD_STATE_PRESENT)
                was_present = bool(states[0].dwCurrentState & SCARD_STATE_PRESENT)

                if is_present and not was_present:
                    # カードがかざされた瞬間
                    time.sleep(0.05)
                    idm = read_idm(hContext, target_reader)
                    if idm and idm != last_idm:
                        last_idm = idm
                        now_str = time.strftime('%Y-%m-%d %H:%M:%S')
                        print(f"[{now_str}] カード検知: IDm={idm}", flush=True)
                        send_touch_api(config.get("api_url"), config.get("api_key"), idm)

                elif not is_present and was_present:
                    # カードが離された
                    last_idm = None

                states[0].dwCurrentState = states[0].dwEventState
                time.sleep(0.1)

        except KeyboardInterrupt:
            print("\n終了します。", flush=True)
            break
        except Exception as e:
            print(f"[例外発生] {e} - 3秒後に再試行します...", flush=True)
            time.sleep(3)
        finally:
            if hContext:
                winscard.SCardReleaseContext(hContext)

if __name__ == "__main__":
    main()
