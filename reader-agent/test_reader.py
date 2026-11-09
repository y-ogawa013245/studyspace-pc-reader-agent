"""
StudySpace - RC-S300 FeliCa IDm 常時読取テストスクリプト
Windows標準のスマートカードAPI (winscard.dll) を使用
"""

import ctypes
import time
import sys
import os
import json
import urllib.request
import urllib.error

# API設定（ローカルサーバー）
API_URL = os.environ.get("STUDYSPACE_API_URL", "http://127.0.0.1:8000/api/touch")
TERMINAL_API_KEY = os.environ.get("STUDYSPACE_API_KEY", "test-terminal-api-key-12345")

def send_touch_api(idm):
    payload = json.dumps({"idm": idm}).encode("utf-8")
    req = urllib.request.Request(
        API_URL,
        data=payload,
        headers={
            "Content-Type": "application/json",
            "X-Api-Key": TERMINAL_API_KEY,
            "User-Agent": "StudySpace-RC-S300-Agent/1.0",
            "Connection": "close",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as res:
            data = json.loads(res.read().decode("utf-8"))
            status_type = data.get("type", "")
            msg = data.get("message", "")
            print(f"  [API送信成功] {msg}", flush=True)
            return data
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8")
        try:
            err = json.loads(body)
            print(f"  [API通知: {err.get('status')}] {err.get('message', e.reason)}", flush=True)
            return err
        except Exception:
            print(f"  [APIエラー] HTTP {e.code}: {e.reason}", flush=True)
    except Exception as e:
        print(f"  [API通信失敗] {e}", flush=True)
    return None

# Windowsコンソールの文字化け対策 (UTF-8)
if sys.platform == 'win32':
    os.system('chcp 65001 > nul')

SCARD_SCOPE_USER = 0
SCARD_SHARE_SHARED = 2
SCARD_PROTOCOL_T0 = 1
SCARD_PROTOCOL_T1 = 2
SCARD_STATE_UNAWARE = 0x00000000
SCARD_STATE_PRESENT = 0x00000020
SCARD_STATE_EMPTY = 0x00000010

winscard = ctypes.windll.winscard

class SCARD_IO_REQUEST(ctypes.Structure):
    _fields_ = [
        ("dwProtocol", ctypes.c_ulong),
        ("cbPciLength", ctypes.c_ulong),
    ]

class SCARD_READERSTATE(ctypes.Structure):
    _fields_ = [
        ("szReader", ctypes.c_wchar_p),
        ("pvUserData", ctypes.c_void_p),
        ("dwCurrentState", ctypes.c_ulong),
        ("dwEventState", ctypes.c_ulong),
        ("cbAtr", ctypes.c_ulong),
        ("rgbAtr", ctypes.c_ubyte * 36),
    ]

def read_idm(hContext, reader_name):
    hCard = ctypes.c_void_p()
    active_proto = ctypes.c_ulong()

    ret = winscard.SCardConnectW(
        hContext,
        reader_name,
        SCARD_SHARE_SHARED,
        SCARD_PROTOCOL_T0 | SCARD_PROTOCOL_T1,
        ctypes.byref(hCard),
        ctypes.byref(active_proto)
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
            ctypes.byref(recv_len)
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
    print("=======================================================", flush=True)
    print("   StudySpace - Sony RC-S300 FeliCa Reader Monitor", flush=True)
    print("=======================================================", flush=True)

    hContext = ctypes.c_void_p()
    ret = winscard.SCardEstablishContext(SCARD_SCOPE_USER, None, None, ctypes.byref(hContext))
    if ret != 0:
        print(f"[Error] SCardEstablishContext failed (0x{ret:X})", flush=True)
        return

    try:
        pcchReaders = ctypes.c_ulong()
        ret = winscard.SCardListReadersW(hContext, None, None, ctypes.byref(pcchReaders))
        if ret != 0:
            print("[Error] No card reader detected. Please connect RC-S300 via USB.", flush=True)
            return

        mszReaders = ctypes.create_unicode_buffer(pcchReaders.value)
        winscard.SCardListReadersW(hContext, None, mszReaders, ctypes.byref(pcchReaders))
        readers = [r for r in mszReaders.value.split("\x00") if r]

        if not readers:
            print("[Error] No valid reader found.", flush=True)
            return

        target_reader = readers[0]
        print(f"[OK] Reader Detected: {target_reader}", flush=True)
        print("-------------------------------------------------------", flush=True)
        print("Waiting for IC Card (Suica / PASMO / Student ID)...", flush=True)
        print("Place your card on the RC-S300. (Press Ctrl+C to stop)", flush=True)
        print("-------------------------------------------------------\n", flush=True)

        reader_state = SCARD_READERSTATE()
        reader_state.szReader = target_reader
        reader_state.dwCurrentState = SCARD_STATE_UNAWARE

        states = (SCARD_READERSTATE * 1)(reader_state)
        winscard.SCardGetStatusChangeW(hContext, 0, states, 1)
        states[0].dwCurrentState = states[0].dwEventState

        last_idm = None

        while True:
            ret = winscard.SCardGetStatusChangeW(hContext, 200, states, 1)
            if ret == 0:
                is_present = bool(states[0].dwEventState & SCARD_STATE_PRESENT)
                was_present = bool(states[0].dwCurrentState & SCARD_STATE_PRESENT)

                if is_present and not was_present:
                    # カードがかざされた瞬間
                    time.sleep(0.05)
                    idm = read_idm(hContext, target_reader)
                    if idm and idm != last_idm:
                        last_idm = idm
                        print(">> CARD DETECTED! <<", flush=True)
                        print(f"========================================", flush=True)
                        print(f"  IDm (UID): {idm}", flush=True)
                        print(f"  Time     : {time.strftime('%Y-%m-%d %H:%M:%S')}", flush=True)
                        print(f"========================================\n", flush=True)
                        send_touch_api(idm)
                        print("\nWaiting for next touch (remove and touch again)...\n", flush=True)

                elif not is_present and was_present:
                    # カードが離された
                    last_idm = None

                states[0].dwCurrentState = states[0].dwEventState
            time.sleep(0.1)

    except KeyboardInterrupt:
        print("\nStopped.", flush=True)
    finally:
        winscard.SCardReleaseContext(hContext)

if __name__ == "__main__":
    main()
