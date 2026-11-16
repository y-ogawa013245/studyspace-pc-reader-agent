# StudySpace PC接続型カードリーダー中継アプリ 配布用ZIP生成スクリプト (Windows / macOS)
param(
    [string]$AgentRepoDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
    [string]$DistDir = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")).Path "dist")
)

$ErrorActionPreference = "Stop"

$src = Join-Path $AgentRepoDir "reader-agent"
$tempDir = Join-Path $env:TEMP "studyspace_pc_reader_win_pkg"
$zipPath = Join-Path $DistDir "studyspace-reader-agent.zip"
$coreDir = Join-Path $tempDir ".core"

Write-Host "=== StudySpace PC Reader Agent Package Builder ==="
Write-Host "Source Dir : $src"
Write-Host "Output Dir : $DistDir"

if (-not (Test-Path $DistDir)) {
    New-Item -ItemType Directory -Path $DistDir -Force | Out-Null
}

# Python Embeddable 環境が未配置の場合は公式から自動取得
$pyDir = Join-Path $src "python"
$pyExe = Join-Path $pyDir "python.exe"
if (-not (Test-Path $pyExe)) {
    Write-Host "Downloading Python 3.11.9 embeddable package (amd64)..."
    $pyZip = Join-Path $env:TEMP "python-embed.zip"
    Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.11.9/python-3.11.9-embed-amd64.zip" -OutFile $pyZip
    New-Item -ItemType Directory -Path $pyDir -Force | Out-Null
    Expand-Archive -Path $pyZip -DestinationPath $pyDir -Force
    Remove-Item -Force $pyZip
}

if (Test-Path $tempDir) {
    Remove-Item -Recurse -Force $tempDir
}
New-Item -ItemType Directory -Path $coreDir -Force | Out-Null

Write-Host "Compiling setup.exe and StudySpace.exe with app.ico..."
$csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$ico = Join-Path $src "app.ico"

# setup.exe (ネイティブ C# WinForms アプリケーション)
$setupExePath = Join-Path $src "setup.exe"
$setupWizardCs = Join-Path $src "SetupWizard.cs"
& $csc /nologo /codepage:65001 /target:winexe /win32icon:$ico /out:$setupExePath $setupWizardCs

# StudySpace.exe (カードリーダー常駐ランチャー)
$agentCs = @"
using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;
namespace StudySpace {
    static class AgentLauncher {
        [STAThread]
        static void Main() {
            string baseDir = AppDomain.CurrentDomain.BaseDirectory;
            string pyExe = Path.Combine(baseDir, ".core", "python", "python.exe");
            if (!File.Exists(pyExe)) { pyExe = Path.Combine(baseDir, "python", "python.exe"); }
            string agentPy = Path.Combine(baseDir, ".core", "reader_agent.py");
            if (!File.Exists(agentPy)) { agentPy = Path.Combine(baseDir, "reader_agent.py"); }
            string configFile = Path.Combine(baseDir, ".core", "config.json");
            if (!File.Exists(configFile)) { configFile = Path.Combine(baseDir, "config.json"); }

            if (!File.Exists(pyExe)) {
                MessageBox.Show("Python environment not found. Please run setup.exe first.", "StudySpace Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }
            if (!File.Exists(configFile)) {
                string setupExe = Path.Combine(baseDir, "setup.exe");
                if (File.Exists(setupExe)) { Process.Start(setupExe); return; }
            }
            ProcessStartInfo psi = new ProcessStartInfo {
                FileName = pyExe,
                Arguments = "-u \"" + agentPy + "\"",
                WorkingDirectory = baseDir,
                WindowStyle = ProcessWindowStyle.Normal,
                CreateNoWindow = false,
                UseShellExecute = true
            };
            try { Process.Start(psi); }
            catch (Exception ex) { MessageBox.Show("Launch error: " + ex.Message, "Error", MessageBoxButtons.OK, MessageBoxIcon.Error); }
        }
    }
}
"@
$agentCsPath = Join-Path $src "temp_agent.cs"
Set-Content -Path $agentCsPath -Value $agentCs -Encoding UTF8
$agentExePath = Join-Path $src "StudySpace.exe"
& $csc /nologo /codepage:65001 /target:winexe /win32icon:$ico /out:$agentExePath $agentCsPath
Remove-Item $agentCsPath

if (-not (Test-Path $setupExePath)) {
    throw "setup.exe was not created at $setupExePath"
}
Copy-Item -Path $setupExePath -Destination (Join-Path $tempDir "setup.exe") -Force

# 内部ファイルはすべて .core に格納
Copy-Item -Recurse -Path $pyDir -Destination (Join-Path $coreDir "python")
Copy-Item -Path (Join-Path $src "reader_agent.py") -Destination $coreDir
Copy-Item -Path (Join-Path $src "setup_wizard.py") -Destination $coreDir
Copy-Item -Path (Join-Path $src "setup_gui.ps1") -Destination $coreDir
Copy-Item -Path (Join-Path $src "start.bat") -Destination $coreDir
Copy-Item -Path $agentExePath -Destination $coreDir
Copy-Item -Path $ico -Destination $coreDir
Copy-Item -Path (Join-Path $src "README.txt") -Destination $coreDir

if (Test-Path $zipPath) {
    Remove-Item -Force $zipPath
}

Write-Host "Compressing Windows archive to: $zipPath"
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($tempDir, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)

Remove-Item -Recurse -Force $tempDir
$zipWinPath = Join-Path $DistDir "studyspace-reader-agent-win.zip"
Copy-Item -Path $zipPath -Destination $zipWinPath -Force

# ==============================================================================
# 2. macOS 向けパッケージ生成 (studyspace-reader-agent-mac.zip)
# ==============================================================================
Write-Host "`n--- Generating macOS Package ---"
$tempDirMac = Join-Path $env:TEMP "studyspace_pc_reader_mac_pkg"
$zipMacPath = Join-Path $DistDir "studyspace-reader-agent-mac.zip"
$coreDirMac = Join-Path $tempDirMac ".core"

if (Test-Path $tempDirMac) {
    Remove-Item -Recurse -Force $tempDirMac
}
New-Item -ItemType Directory -Path $coreDirMac -Force | Out-Null

$macSetupCmd = Join-Path $src "setup_mac.command"
if (-not (Test-Path $macSetupCmd)) {
    throw "setup_mac.command not found at $macSetupCmd"
}
Copy-Item -Path $macSetupCmd -Destination (Join-Path $tempDirMac "setup.command") -Force

Copy-Item -Path (Join-Path $src "reader_agent.py") -Destination $coreDirMac
Copy-Item -Path (Join-Path $src "start_mac.command") -Destination $coreDirMac
Copy-Item -Path $ico -Destination $coreDirMac
Copy-Item -Path (Join-Path $src "README.txt") -Destination $coreDirMac

if (Test-Path $zipMacPath) {
    Remove-Item -Force $zipMacPath
}

Write-Host "Compressing macOS archive to: $zipMacPath"
[System.IO.Compression.ZipFile]::CreateFromDirectory($tempDirMac, $zipMacPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)
Remove-Item -Recurse -Force $tempDirMac

Write-Host "✅ Generated PC Reader Agent packages successfully:"
Get-Item (Join-Path $DistDir "studyspace-reader-agent*.zip") | Select-Object Name, Length
