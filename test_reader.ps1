Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class WinSCard {
    public const uint SCARD_SCOPE_USER = 0;
    public const uint SCARD_SHARE_SHARED = 2;
    public const uint SCARD_PROTOCOL_T0 = 1;
    public const uint SCARD_PROTOCOL_T1 = 2;
    public const uint SCARD_STATE_UNAWARE = 0x00000000;
    public const uint SCARD_STATE_PRESENT = 0x00000020;
    public const uint SCARD_STATE_EMPTY = 0x00000010;
    public const uint INFINITE = 0xFFFFFFFF;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public struct SCARD_READERSTATE {
        public string szReader;
        public IntPtr pvUserData;
        public uint dwCurrentState;
        public uint dwEventState;
        public uint cbAtr;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 36)]
        public byte[] rgbAtr;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct SCARD_IO_REQUEST {
        public uint dwProtocol;
        public uint cbPciLength;
    }

    [DllImport("winscard.dll", SetLastError = true)]
    public static extern int SCardEstablishContext(uint dwScope, IntPtr pvReserved1, IntPtr pvReserved2, out IntPtr phContext);

    [DllImport("winscard.dll", SetLastError = true)]
    public static extern int SCardReleaseContext(IntPtr hContext);

    [DllImport("winscard.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern int SCardListReaders(IntPtr hContext, string mszGroups, byte[] mszReaders, ref uint pcchReaders);

    [DllImport("winscard.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern int SCardConnect(IntPtr hContext, string szReader, uint dwShareMode, uint dwPreferredProtocols, out IntPtr phCard, out uint pdwActiveProtocol);

    [DllImport("winscard.dll", SetLastError = true)]
    public static extern int SCardDisconnect(IntPtr hCard, uint dwDisposition);

    [DllImport("winscard.dll", SetLastError = true)]
    public static extern int SCardTransmit(IntPtr hCard, ref SCARD_IO_REQUEST pioSendPci, byte[] pbSendBuffer, int cbSendLength, IntPtr pioRecvPci, byte[] pbRecvBuffer, ref int pcbRecvLength);

    [DllImport("winscard.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern int SCardGetStatusChange(IntPtr hContext, uint dwTimeout, [In, Out] SCARD_READERSTATE[] rgReaderStates, uint cReaders);
}
"@

Write-Host "=== RC-S300 FeliCa 読取テスト ===" -ForegroundColor Cyan

$hContext = [IntPtr]::Zero
$res = [WinSCard]::SCardEstablishContext([WinSCard]::SCARD_SCOPE_USER, [IntPtr]::Zero, [IntPtr]::Zero, [ref]$hContext)
if ($res -ne 0) {
    Write-Host "SCardEstablishContext 失敗: $res" -ForegroundColor Red
    exit 1
}

$pcchReaders = 2048
$mszReaders = New-Object byte[] $pcchReaders
$res = [WinSCard]::SCardListReaders($hContext, $null, $mszReaders, [ref]$pcchReaders)
if ($res -ne 0) {
    Write-Host "リーダーが見つかりません: $res" -ForegroundColor Red
    [WinSCard]::SCardReleaseContext($hContext) | Out-Null
    exit 1
}

$readersStr = [System.Text.Encoding]::Unicode.GetString($mszReaders, 0, $pcchReaders * 2).Trim([char]0)
$readers = $readersStr -split "`0" | Where-Object { $_ -ne "" }

Write-Host "検出されたカードリーダー:" -ForegroundColor Green
foreach ($r in $readers) {
    Write-Host " - $r" -ForegroundColor Yellow
}

if ($readers.Count -eq 0) {
    Write-Host "有効なリーダーがありません。" -ForegroundColor Red
    [WinSCard]::SCardReleaseContext($hContext) | Out-Null
    exit 1
}

$targetReader = $readers[0]
Write-Host "`nリーダー [$targetReader] でカードの待機を開始します..." -ForegroundColor Cyan
Write-Host "※カード（Suica / PASMO / 学生証など）をカードリーダーにかざしてください（Ctrl+Cで終了）`n" -ForegroundColor White

$readerState = New-Object WinSCard+SCARD_READERSTATE
$readerState.szReader = $targetReader
$readerState.dwCurrentState = [WinSCard]::SCARD_STATE_UNAWARE
$states = [WinSCard+SCARD_READERSTATE[]]@($readerState)

# 初期状態を取得
[WinSCard]::SCardGetStatusChange($hContext, 0, $states, 1) | Out-Null
$states[0].dwCurrentState = $states[0].dwEventState

# 10秒間待機ループ（テスト用）
$startTime = Get-Date
while (((Get-Date) - $startTime).TotalSeconds -lt 20) {
    $res = [WinSCard]::SCardGetStatusChange($hContext, 1000, $states, 1)
    if ($res -eq 0 -and ($states[0].dwEventState -band [WinSCard]::SCARD_STATE_PRESENT) -and !($states[0].dwCurrentState -band [WinSCard]::SCARD_STATE_PRESENT)) {
        Write-Host ">>> カードを検知しました！ <<<" -ForegroundColor Green
        
        $hCard = [IntPtr]::Zero
        $activeProto = 0
        $connRes = [WinSCard]::SCardConnect($hContext, $targetReader, [WinSCard]::SCARD_SHARE_SHARED, ([WinSCard]::SCARD_PROTOCOL_T0 -bor [WinSCard]::SCARD_PROTOCOL_T1), [ref]$hCard, [ref]$activeProto)
        if ($connRes -eq 0) {
            $ioReq = New-Object WinSCard+SCARD_IO_REQUEST
            $ioReq.dwProtocol = $activeProto
            $ioReq.cbPciLength = [System.Runtime.InteropServices.Marshal]::SizeOf($ioReq)

            # Get Card UID (IDm) APDU: FF CA 00 00 00
            $apdu = [byte[]]@(0xFF, 0xCA, 0x00, 0x00, 0x00)
            $recvBuf = New-Object byte[] 256
            $recvLen = 256

            $txRes = [WinSCard]::SCardTransmit($hCard, [ref]$ioReq, $apdu, $apdu.Length, [IntPtr]::Zero, $recvBuf, [ref]$recvLen)
            if ($txRes -eq 0 -and $recvLen -ge 2) {
                $sw1 = $recvBuf[$recvLen - 2]
                $sw2 = $recvBuf[$recvLen - 1]
                if ($sw1 -eq 0x90 -and $sw2 -eq 0x00) {
                    $idmBytes = New-Object byte[] ($recvLen - 2)
                    [Array]::Copy($recvBuf, $idmBytes, $recvLen - 2)
                    $idmHex = [BitConverter]::ToString($idmBytes) -replace "-"
                    Write-Host "【成功】カードIDm (UID): $idmHex" -ForegroundColor Yellow -BackgroundColor DarkBlue
                    Write-Host "テスト成功！カードの読み取りが正常に行えました。" -ForegroundColor Green
                    [WinSCard]::SCardDisconnect($hCard, 0) | Out-Null
                    break
                } else {
                    Write-Host "APDU 応答エラー: SW1=$($sw1.ToString('X2')) SW2=$($sw2.ToString('X2'))" -ForegroundColor Red
                }
            } else {
                Write-Host "SCardTransmit 失敗: $txRes" -ForegroundColor Red
            }
            [WinSCard]::SCardDisconnect($hCard, 0) | Out-Null
        } else {
            Write-Host "SCardConnect 失敗: $connRes" -ForegroundColor Red
        }
    }
    $states[0].dwCurrentState = $states[0].dwEventState
}

[WinSCard]::SCardReleaseContext($hContext) | Out-Null
Write-Host "テスト完了。" -ForegroundColor Cyan
