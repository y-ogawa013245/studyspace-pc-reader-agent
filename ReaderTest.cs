using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace StudySpace {
    class Program {
        const uint SCARD_SCOPE_USER = 0;
        const uint SCARD_SHARE_SHARED = 2;
        const uint SCARD_PROTOCOL_T0 = 1;
        const uint SCARD_PROTOCOL_T1 = 2;
        const uint SCARD_STATE_UNAWARE = 0x00000000;
        const uint SCARD_STATE_CHANGED = 0x00000002;
        const uint SCARD_STATE_PRESENT = 0x00000020;
        const uint SCARD_STATE_EMPTY = 0x00000010;

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

        static void Main(string[] args) {
            Console.OutputEncoding = Encoding.UTF8;
            Console.WriteLine("==================================================");
            Console.WriteLine("   StudySpace RC-S300 FeliCa 読取テスト");
            Console.WriteLine("==================================================");

            IntPtr hContext;
            int ret = SCardEstablishContext(SCARD_SCOPE_USER, IntPtr.Zero, IntPtr.Zero, out hContext);
            if (ret != 0) {
                Console.WriteLine("エラー: SCardEstablishContext 失敗 (コード: 0x" + ret.ToString("X") + ")");
                return;
            }

            uint pcchReaders = 2048;
            byte[] mszReaders = new byte[pcchReaders];
            ret = SCardListReaders(hContext, null, mszReaders, ref pcchReaders);
            if (ret != 0) {
                Console.WriteLine("エラー: カードリーダーが見つかりません (コード: 0x" + ret.ToString("X") + ")");
                SCardReleaseContext(hContext);
                return;
            }

            string readersStr = Encoding.Unicode.GetString(mszReaders, 0, (int)pcchReaders * 2).TrimEnd('\0');
            string[] readers = readersStr.Split(new char[] { '\0' }, StringSplitOptions.RemoveEmptyEntries);

            Console.WriteLine("\n[検出されたカードリーダー]");
            foreach (var r in readers) {
                Console.WriteLine(" -> " + r);
            }

            if (readers.Length == 0) {
                Console.WriteLine("利用可能なカードリーダーがありません。");
                SCardReleaseContext(hContext);
                return;
            }

            string targetReader = readers[0];
            Console.WriteLine("\n対象リーダー: " + targetReader);
            Console.WriteLine("--------------------------------------------------");
            Console.WriteLine(">>> ICカード（Suica / PASMO / 学生証等）をかざしてください <<<");
            Console.WriteLine("（※30秒間待機します。Ctrl+Cで終了）\n");

            var state = new SCARD_READERSTATE();
            state.szReader = targetReader;
            state.dwCurrentState = SCARD_STATE_UNAWARE;
            var states = new SCARD_READERSTATE[] { state };

            // 初期状態取得
            SCardGetStatusChange(hContext, 0, states, 1);
            states[0].dwCurrentState = states[0].dwEventState;

            DateTime start = DateTime.Now;
            bool detected = false;

            while ((DateTime.Now - start).TotalSeconds < 30) {
                ret = SCardGetStatusChange(hContext, 500, states, 1);
                if (ret == 0) {
                    bool isPresent = (states[0].dwEventState & SCARD_STATE_PRESENT) != 0;
                    bool wasPresent = (states[0].dwCurrentState & SCARD_STATE_PRESENT) != 0;

                    if (isPresent && !wasPresent) {
                        Console.WriteLine("\n[検知] カードがかざされました！読み取り中...");
                        ReadCardIdm(hContext, targetReader);
                        detected = true;
                        break;
                    }
                    states[0].dwCurrentState = states[0].dwEventState;
                }
                Thread.Sleep(100);
            }

            if (!detected) {
                Console.WriteLine("\nタイムアウト: カードが検出されませんでした。");
            }

            SCardReleaseContext(hContext);
            Console.WriteLine("\nテスト終了。");
        }

        static void ReadCardIdm(IntPtr hContext, string readerName) {
            IntPtr hCard;
            uint activeProtocol;
            int ret = SCardConnect(hContext, readerName, SCARD_SHARE_SHARED, SCARD_PROTOCOL_T0 | SCARD_PROTOCOL_T1, out hCard, out activeProtocol);
            if (ret != 0) {
                Console.WriteLine("カード接続エラー (コード: 0x" + ret.ToString("X") + ")");
                return;
            }

            try {
                var ioReq = new SCARD_IO_REQUEST();
                ioReq.dwProtocol = activeProtocol;
                ioReq.cbPciLength = (uint)Marshal.SizeOf(ioReq);

                // FeliCa / Type-F / Type-A UID取得APDU: FF CA 00 00 00
                byte[] apdu = new byte[] { 0xFF, 0xCA, 0x00, 0x00, 0x00 };
                byte[] recv = new byte[256];
                int recvLen = recv.Length;

                ret = SCardTransmit(hCard, ref ioReq, apdu, apdu.Length, IntPtr.Zero, recv, ref recvLen);
                if (ret == 0 && recvLen >= 2) {
                    byte sw1 = recv[recvLen - 2];
                    byte sw2 = recv[recvLen - 1];

                    if (sw1 == 0x90 && sw2 == 0x00) {
                        byte[] idm = new byte[recvLen - 2];
                        Array.Copy(recv, 0, idm, 0, recvLen - 2);
                        string idmHex = BitConverter.ToString(idm).Replace("-", "");

                        Console.ForegroundColor = ConsoleColor.Green;
                        Console.WriteLine("\n========================================");
                        Console.WriteLine(" ★ 読取成功！");
                        Console.WriteLine(" カードIDm (UID): " + idmHex);
                        Console.WriteLine(" (バイト長: " + idm.Length + " bytes)");
                        Console.WriteLine("========================================\n");
                        Console.ResetColor();
                    } else {
                        Console.WriteLine("APDU応答ステータスエラー: SW1=" + sw1.ToString("X2") + " SW2=" + sw2.ToString("X2"));
                    }
                } else {
                    Console.WriteLine("SCardTransmit 送信エラー (コード: 0x" + ret.ToString("X") + ")");
                }
            } finally {
                SCardDisconnect(hCard, 0);
            }
        }
    }
}
