# StudySpace カードリーダー中継アプリ 配布用ZIP生成スクリプト
$ErrorActionPreference = "Stop"

$src = "C:\Users\user\.gemini\antigravity-ide\scratch\studyspace-entry-system\reader-agent"
$distDir = "C:\Users\user\.gemini\antigravity-ide\scratch\studyspace-entry-system\server\public\downloads"
$tempDir = "C:\Users\user\.gemini\antigravity-ide\scratch\studyspace-entry-system\reader-agent-dist"
$zipPath = Join-Path $distDir "studyspace-reader-agent.zip"
$coreDir = Join-Path $tempDir ".core"

Write-Host "Creating output directory: $distDir"
if (-not (Test-Path $distDir)) {
    New-Item -ItemType Directory -Path $distDir -Force | Out-Null
}

Write-Host "Preparing temporary files in: $tempDir"
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

# StudySpace.exe
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

Write-Host "Copying setup.exe to root (only setup.exe is visible to users)..."
if (-not (Test-Path $setupExePath)) {
    throw "setup.exe was not created at $setupExePath"
}
Copy-Item -Path $setupExePath -Destination (Join-Path $tempDir "setup.exe") -Force

# 内部ファイルはすべて .core に格納
Write-Host "Copying python directory..."
Copy-Item -Recurse -Path (Join-Path $src "python") -Destination (Join-Path $coreDir "python")
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

Write-Host "Compressing archive to: $zipPath"
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($tempDir, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)

# Windows用ZIPの複製（-win.zipとしても保存）
Remove-Item -Recurse -Force $tempDir
$zipWinPath = Join-Path $distDir "studyspace-reader-agent-win.zip"
Copy-Item -Path $zipPath -Destination $zipWinPath -Force

# ==============================================================================
# 2. macOS 向けパッケージ生成 (studyspace-reader-agent-mac.zip)
# ==============================================================================
Write-Host "`n--- Generating macOS Package ---"
$tempDirMac = "C:\Users\user\.gemini\antigravity-ide\scratch\studyspace-entry-system\reader-agent-dist-mac"
$zipMacPath = Join-Path $distDir "studyspace-reader-agent-mac.zip"
$coreDirMac = Join-Path $tempDirMac ".core"

if (Test-Path $tempDirMac) {
    Remove-Item -Recurse -Force $tempDirMac
}
New-Item -ItemType Directory -Path $coreDirMac -Force | Out-Null

$macSetupCmd = Join-Path $src "setup_mac.command"
Write-Host "macSetupCmd is: $macSetupCmd"
if (-not (Test-Path $macSetupCmd)) {
    throw "setup_mac.command not found at $macSetupCmd"
}
Copy-Item -Path $macSetupCmd -Destination (Join-Path $tempDirMac "setup.command") -Force

# 内部ファイルは .core に格納
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

$zipMacItem = Get-Item $zipMacPath
$sizeMacMb = [math]::Round($zipMacItem.Length / 1KB, 1)
Write-Host "Successfully generated macOS package: $zipMacPath ($sizeMacMb KB, $($zipMacItem.Length) bytes)"
Write-Host "`nAll Windows and macOS packages generated successfully in: $distDir"
