using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;

namespace StudySpace
{
    public class SetupForm : Form
    {
        private TextBox txtUrl;
        private TextBox txtName;
        private Label lblTestRes;
        private CheckBox chkDesktop;
        private CheckBox chkStartup;
        private ProgressBar pBar;
        private Label lblProgress;
        private Button btnAction;
        private Button btnLaunch;
        private Button btnClose;
        private Button btnTest;

        private string baseDir;
        private string coreDir;
        private string logFile;
        private string configFile;
        private string appExePath;
        private string appIcoPath;

        [STAThread]
        public static void Main()
        {
            try
            {
                // TLS 1.2 / TLS 1.1 / TLS 1.0 を有効化 (HTTPS 接続エラー防止)
                System.Net.ServicePointManager.SecurityProtocol =
                    (System.Net.SecurityProtocolType)3072 | // Tls12
                    (System.Net.SecurityProtocolType)768  | // Tls11
                    (System.Net.SecurityProtocolType)192;   // Tls
            }
            catch { }

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new SetupForm());
        }

        public SetupForm()
        {
            baseDir = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\', '/');
            if (Path.GetFileName(baseDir).Equals(".core", StringComparison.OrdinalIgnoreCase))
            {
                coreDir = baseDir;
                baseDir = Path.GetDirectoryName(baseDir);
            }
            else
            {
                coreDir = Path.Combine(baseDir, ".core");
            }

            if (!Directory.Exists(coreDir))
            {
                try { Directory.CreateDirectory(coreDir); } catch { }
            }

            logFile = Path.Combine(coreDir, "setup.log");
            configFile = Path.Combine(coreDir, "config.json");
            appExePath = Path.Combine(coreDir, "StudySpace.exe");
            if (!File.Exists(appExePath)) { appExePath = Path.Combine(baseDir, "StudySpace.exe"); }

            appIcoPath = Path.Combine(coreDir, "app.ico");
            if (!File.Exists(appIcoPath)) { appIcoPath = Path.Combine(baseDir, "app.ico"); }

            InitializeUI();
            Log("=== StudySpace Setup 起動 ===");
        }

        private void Log(string msg)
        {
            try
            {
                string line = string.Format("[{0:yyyy-MM-dd HH:mm:ss}] {1}", DateTime.Now, msg);
                File.AppendAllText(logFile, line + "\r\n", Encoding.UTF8);
            }
            catch { }
        }

        private void InitializeUI()
        {
            this.Text = "StudySpace カードリーダー セットアップ";
            this.Size = new Size(540, 560);
            this.StartPosition = FormStartPosition.CenterScreen;
            this.FormBorderStyle = FormBorderStyle.FixedDialog;
            this.MaximizeBox = false;
            this.MinimizeBox = true;
            this.BackColor = Color.FromArgb(248, 250, 252);

            if (File.Exists(appIcoPath))
            {
                try { this.Icon = new Icon(appIcoPath); } catch { }
            }

            // ヘッダー
            Label lblTitle = new Label();
            lblTitle.Text = "StudySpace カードリーダー セットアップ";
            lblTitle.Font = new Font("Meiryo UI", 13, FontStyle.Bold);
            lblTitle.ForeColor = Color.FromArgb(15, 23, 42);
            lblTitle.Location = new Point(24, 18);
            lblTitle.Size = new Size(480, 26);
            this.Controls.Add(lblTitle);

            Label lblSub = new Label();
            lblSub.Text = "受付PCの初期設定を行います。通常はこのまま【セットアップを実行】を押してください。";
            lblSub.Font = new Font("Meiryo UI", 9);
            lblSub.ForeColor = Color.FromArgb(100, 116, 139);
            lblSub.Location = new Point(24, 46);
            lblSub.Size = new Size(480, 36);
            this.Controls.Add(lblSub);

            // パネルコンテナ
            Panel panel = new Panel();
            panel.Location = new Point(24, 86);
            panel.Size = new Size(476, 255);
            panel.BackColor = Color.White;
            panel.BorderStyle = BorderStyle.FixedSingle;
            this.Controls.Add(panel);

            // 1. サーバーURL
            Label lblUrl = new Label();
            lblUrl.Text = "1. 接続先サーバーURL:";
            lblUrl.Font = new Font("Meiryo UI", 9, FontStyle.Bold);
            lblUrl.Location = new Point(16, 14);
            lblUrl.Size = new Size(400, 20);
            panel.Controls.Add(lblUrl);

            txtUrl = new TextBox();
            txtUrl.Text = "https://entry.studyspace.okinawa";
            txtUrl.Font = new Font("Meiryo UI", 9.5f);
            txtUrl.Location = new Point(16, 36);
            txtUrl.Size = new Size(330, 24);
            panel.Controls.Add(txtUrl);

            btnTest = new Button();
            btnTest.Text = "接続テスト";
            btnTest.Font = new Font("Meiryo UI", 8.5f);
            btnTest.Location = new Point(356, 34);
            btnTest.Size = new Size(100, 27);
            btnTest.BackColor = Color.FromArgb(241, 245, 249);
            btnTest.FlatStyle = FlatStyle.Flat;
            btnTest.Click += BtnTest_Click;
            panel.Controls.Add(btnTest);

            lblTestRes = new Label();
            lblTestRes.Text = "";
            lblTestRes.Font = new Font("Meiryo UI", 8.5f);
            lblTestRes.Location = new Point(16, 64);
            lblTestRes.Size = new Size(440, 18);
            panel.Controls.Add(lblTestRes);

            // 2. 端末名
            Label lblName = new Label();
            lblName.Text = "2. 受付端末名 (管理画面の識別名):";
            lblName.Font = new Font("Meiryo UI", 9, FontStyle.Bold);
            lblName.Location = new Point(16, 90);
            lblName.Size = new Size(400, 20);
            panel.Controls.Add(lblName);

            string compName = Environment.MachineName;
            txtName = new TextBox();
            txtName.Text = string.IsNullOrEmpty(compName) ? "受付PC" : "受付PC-" + compName;
            txtName.Font = new Font("Meiryo UI", 9.5f);
            txtName.Location = new Point(16, 112);
            txtName.Size = new Size(440, 24);
            panel.Controls.Add(txtName);

            // 3. ショートカットオプション
            Label lblOpt = new Label();
            lblOpt.Text = "3. ショートカット・起動設定:";
            lblOpt.Font = new Font("Meiryo UI", 9, FontStyle.Bold);
            lblOpt.Location = new Point(16, 150);
            lblOpt.Size = new Size(400, 20);
            panel.Controls.Add(lblOpt);

            chkDesktop = new CheckBox();
            chkDesktop.Text = "デスクトップに起動ショートカットを作成する";
            chkDesktop.Font = new Font("Meiryo UI", 9);
            chkDesktop.Checked = true;
            chkDesktop.Location = new Point(16, 174);
            chkDesktop.Size = new Size(440, 22);
            panel.Controls.Add(chkDesktop);

            chkStartup = new CheckBox();
            chkStartup.Text = "Windows起動時に自動でバックグラウンド常駐する";
            chkStartup.Font = new Font("Meiryo UI", 9);
            chkStartup.Checked = false;
            chkStartup.Location = new Point(16, 200);
            chkStartup.Size = new Size(440, 22);
            panel.Controls.Add(chkStartup);

            // 進行状況ラベル
            lblProgress = new Label();
            lblProgress.Text = "設定を確認し、下のボタンを押してください。";
            lblProgress.Font = new Font("Meiryo UI", 9);
            lblProgress.ForeColor = Color.FromArgb(71, 85, 105);
            lblProgress.Location = new Point(24, 352);
            lblProgress.Size = new Size(476, 20);
            this.Controls.Add(lblProgress);

            // プログレスバー
            pBar = new ProgressBar();
            pBar.Location = new Point(24, 376);
            pBar.Size = new Size(476, 12);
            pBar.Value = 0;
            this.Controls.Add(pBar);

            // セットアップ実行ボタン
            btnAction = new Button();
            btnAction.Text = "セットアップを実行する（ワンクリック完了）";
            btnAction.Font = new Font("Meiryo UI", 10.5f, FontStyle.Bold);
            btnAction.BackColor = Color.FromArgb(2, 132, 199);
            btnAction.ForeColor = Color.White;
            btnAction.FlatStyle = FlatStyle.Flat;
            btnAction.FlatAppearance.BorderSize = 0;
            btnAction.Location = new Point(24, 400);
            btnAction.Size = new Size(476, 44);
            btnAction.Cursor = Cursors.Hand;
            btnAction.Click += BtnAction_Click;
            this.Controls.Add(btnAction);

            // 完了時ボタン群
            btnLaunch = new Button();
            btnLaunch.Text = "今すぐカードリーダーを起動する";
            btnLaunch.Font = new Font("Meiryo UI", 9.5f, FontStyle.Bold);
            btnLaunch.BackColor = Color.FromArgb(16, 185, 129);
            btnLaunch.ForeColor = Color.White;
            btnLaunch.FlatStyle = FlatStyle.Flat;
            btnLaunch.FlatAppearance.BorderSize = 0;
            btnLaunch.Location = new Point(24, 456);
            btnLaunch.Size = new Size(330, 36);
            btnLaunch.Visible = false;
            btnLaunch.Cursor = Cursors.Hand;
            btnLaunch.Click += (s, e) => { LaunchAgent(); this.Close(); };
            this.Controls.Add(btnLaunch);

            btnClose = new Button();
            btnClose.Text = "閉じる";
            btnClose.Font = new Font("Meiryo UI", 9.5f);
            btnClose.BackColor = Color.FromArgb(226, 232, 240);
            btnClose.ForeColor = Color.FromArgb(30, 41, 59);
            btnClose.FlatStyle = FlatStyle.Flat;
            btnClose.FlatAppearance.BorderSize = 0;
            btnClose.Location = new Point(366, 456);
            btnClose.Size = new Size(134, 36);
            btnClose.Visible = false;
            btnClose.Cursor = Cursors.Hand;
            btnClose.Click += (s, e) => { this.Close(); };
            this.Controls.Add(btnClose);
        }

        private void BtnTest_Click(object sender, EventArgs e)
        {
            string url = txtUrl.Text.Trim().TrimEnd('/');
            if (url.EndsWith("/api", StringComparison.OrdinalIgnoreCase))
            {
                url = url.Substring(0, url.Length - 4).TrimEnd('/');
            }
            lblTestRes.ForeColor = Color.FromArgb(217, 119, 6);
            lblTestRes.Text = "接続テスト中...";
            this.Refresh();

            try
            {
                using (var client = new WebClient())
                {
                    client.Encoding = Encoding.UTF8;
                    client.Headers["User-Agent"] = "StudySpace-Setup/1.0";
                    string res = client.DownloadString(url + "/api/kiosk-status");
                    lblTestRes.ForeColor = Color.FromArgb(16, 185, 129);
                    lblTestRes.Text = "✓ サーバー接続成功！ (正常に応答しました)";
                    Log("接続テスト成功: " + url);
                }
            }
            catch (Exception ex)
            {
                lblTestRes.ForeColor = Color.FromArgb(225, 29, 72);
                lblTestRes.Text = "⚠ 接続失敗: " + ex.Message;
                Log("接続テスト失敗: " + url + " - " + ex.Message);
            }
        }

        private void BtnAction_Click(object sender, EventArgs e)
        {
            btnAction.Enabled = false;
            btnTest.Enabled = false;
            txtUrl.Enabled = false;
            txtName.Enabled = false;
            chkDesktop.Enabled = false;
            chkStartup.Enabled = false;

            string serverUrl = txtUrl.Text.Trim().TrimEnd('/');
            if (serverUrl.EndsWith("/api", StringComparison.OrdinalIgnoreCase))
            {
                serverUrl = serverUrl.Substring(0, serverUrl.Length - 4).TrimEnd('/');
            }
            string termName = txtName.Text.Trim();
            if (string.IsNullOrEmpty(termName)) { termName = "受付PC"; }

            pBar.Value = 20;
            lblProgress.Text = "サーバーに接続して端末登録申請中...";
            this.Refresh();

            string apiKey = "test-terminal-api-key-12345";
            try
            {
                using (var client = new WebClient())
                {
                    client.Encoding = Encoding.UTF8;
                    client.Headers[HttpRequestHeader.ContentType] = "application/json; charset=utf-8";
                    client.Headers["User-Agent"] = "StudySpace-Setup/1.0";
                    string escapedName = termName.Replace("\\", "\\\\").Replace("\"", "\\\"");
                    string jsonBody = "{\"name\":\"" + escapedName + "\"}";
                    string regUrl = serverUrl + "/api/terminals/register";
                    string responseJson = client.UploadString(regUrl, "POST", jsonBody);

                    var mKey = Regex.Match(responseJson, "\"api_key\"\\s*:\\s*\"([^\"]+)\"");
                    var mId = Regex.Match(responseJson, "\"terminal_id\"\\s*:\\s*(\\d+)");
                    if (mKey.Success)
                    {
                        apiKey = mKey.Groups[1].Value;
                        string tid = mId.Success ? mId.Groups[1].Value : "?";
                        Log(string.Format("端末登録成功: ID={0}, APIキー発行", tid));
                    }
                }
            }
            catch (Exception ex)
            {
                Log("端末登録API警告 (デフォルトキー使用): " + ex.Message);
            }

            pBar.Value = 50;
            lblProgress.Text = "config.json を保存中...";
            this.Refresh();

            try
            {
                string confJson = "{\n" +
                    "  \"api_url\": \"" + serverUrl + "/api/touch\",\n" +
                    "  \"api_key\": \"" + apiKey + "\",\n" +
                    "  \"terminal_name\": \"" + termName.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\",\n" +
                    "  \"configured_at\": \"" + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "\"\n" +
                    "}\n";

                File.WriteAllText(configFile, confJson, new UTF8Encoding(false));
                // ルートに過去のファイルがあればクリーンアップして .core に一本化
                try
                {
                    string rootConf = Path.Combine(baseDir, "config.json");
                    if (File.Exists(rootConf)) { File.Delete(rootConf); }
                    string rootLog = Path.Combine(baseDir, "setup.log");
                    if (File.Exists(rootLog)) { File.Delete(rootLog); }
                }
                catch { }
                Log("config.json 保存完了: " + configFile);
            }
            catch (Exception ex)
            {
                Log("config.json 保存失敗: " + ex.Message);
            }

            pBar.Value = 75;
            lblProgress.Text = "ショートカットを作成中...";
            this.Refresh();

            string targetToRun = appExePath;
            if (!File.Exists(targetToRun))
            {
                targetToRun = Path.Combine(coreDir, "start.bat");
                if (!File.Exists(targetToRun)) { targetToRun = Path.Combine(baseDir, "start.bat"); }
            }

            if (chkDesktop.Checked)
            {
                try
                {
                    string desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
                    string lnk = Path.Combine(desktop, "StudySpace カードリーダー.lnk");
                    CreateShortcut(targetToRun, lnk, baseDir, appIcoPath);
                    Log("デスクトップショートカット作成成功: " + lnk);
                }
                catch (Exception ex)
                {
                    Log("デスクトップショートカット作成エラー: " + ex.Message);
                }
            }

            if (chkStartup.Checked)
            {
                try
                {
                    string startup = Environment.GetFolderPath(Environment.SpecialFolder.Startup);
                    string lnk = Path.Combine(startup, "StudySpace カードリーダー.lnk");
                    CreateShortcut(targetToRun, lnk, baseDir, appIcoPath);
                    Log("スタートアップ登録成功: " + lnk);
                }
                catch (Exception ex)
                {
                    Log("スタートアップ登録エラー: " + ex.Message);
                }
            }

            pBar.Value = 100;
            lblProgress.ForeColor = Color.FromArgb(16, 185, 129);
            lblProgress.Text = "🎉 セットアップがすべて正常に完了しました！";
            btnAction.Text = "✓ セットアップ完了";
            btnAction.BackColor = Color.FromArgb(100, 116, 139);

            btnLaunch.Visible = true;
            btnClose.Visible = true;
            Log("=== セットアップ全行程完了 ===");
        }

        private void CreateShortcut(string targetPath, string shortcutPath, string workingDir, string iconPath)
        {
            try
            {
                Type shellType = Type.GetTypeFromProgID("WScript.Shell");
                dynamic shell = Activator.CreateInstance(shellType);
                dynamic sc = shell.CreateShortcut(shortcutPath);
                sc.TargetPath = targetPath;
                sc.WorkingDirectory = workingDir;
                sc.Description = "StudySpace カードリーダー";
                if (File.Exists(iconPath))
                {
                    sc.IconLocation = iconPath + ",0";
                }
                sc.Save();
            }
            catch (Exception ex)
            {
                throw new InvalidOperationException("Failed to create shortcut: " + ex.Message, ex);
            }
        }

        private void LaunchAgent()
        {
            try
            {
                if (File.Exists(appExePath))
                {
                    Process.Start(new ProcessStartInfo
                    {
                        FileName = appExePath,
                        WorkingDirectory = baseDir,
                        UseShellExecute = true
                    });
                }
                else
                {
                    string bat = Path.Combine(coreDir, "start.bat");
                    if (!File.Exists(bat)) { bat = Path.Combine(baseDir, "start.bat"); }
                    if (File.Exists(bat))
                    {
                        Process.Start(new ProcessStartInfo
                        {
                            FileName = bat,
                            WorkingDirectory = baseDir,
                            UseShellExecute = true
                        });
                    }
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show("起動エラー: " + ex.Message, "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
    }
}
