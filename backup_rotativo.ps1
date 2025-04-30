#Requires -RunAsAdministrator
<#
.SYNOPSIS
Script de backup rotativo com configuração interativa, validação, auto-instalação, agendamento e verificação do MEGAsync.
#>

# Carrega assemblies para interface gráfica
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName PresentationFramework

function Show-FolderDialog {
    param([string]$Description)
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $true
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    }
    return $null
}

function Show-InputBox {
    param([string]$Title, [string]$Prompt, [string]$DefaultValue)
    Add-Type -AssemblyName Microsoft.VisualBasic
    return [Microsoft.VisualBasic.Interaction]::InputBox($Prompt, $Title, $DefaultValue)
}

# --- DEFINIÇÃO DE PASTAS PADRÃO ---
$pastaScripts = "C:\RodolfoScriptBackup\"
if (-not (Test-Path $pastaScripts)) {
    New-Item -Path $pastaScripts -ItemType Directory -Force | Out-Null
}
$configPath = Join-Path $pastaScripts "config_backup.json"

# --- CONFIGURAÇÃO INTERATIVA E VALIDAÇÃO ---
$precisaConfigurar = $false

if (Test-Path $configPath) {
    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        if (-not (Test-Path $config.pastaMonitorada) -or -not (Test-Path $config.pastaDestino) -or
            [int]$config.retention -lt 1 -or [int]$config.retention -gt 365 -or
            [int]$config.intervaloExecucao -lt 1 -or [int]$config.intervaloExecucao -gt 1440) {
            $precisaConfigurar = $true
        }
    } catch {
        $precisaConfigurar = $true
    }
} else {
    $precisaConfigurar = $true
}

if ($precisaConfigurar) {
    [System.Windows.MessageBox]::Show("Configuração inicial necessária. Por favor selecione as pastas e parâmetros.", "Configuração do Backup", "OK", "Information") | Out-Null

    do {
        $pastaMonitorada = Show-FolderDialog -Description "Selecione a pasta com os backups originais"
    } until ($pastaMonitorada -and (Test-Path $pastaMonitorada))

    do {
        $pastaDestino = Show-FolderDialog -Description "Selecione a pasta para armazenar backups rotativos"
    } until ($pastaDestino -and (Test-Path $pastaDestino))

    do {
        $retention = Show-InputBox -Title "Configuração de Retenção" -Prompt "Quantos backups deseja manter? (1-365)" -DefaultValue "31"
    } until ($retention -match '^\d+$' -and [int]$retention -ge 1 -and [int]$retention -le 365)

    do {
        $intervalo = Show-InputBox -Title "Intervalo de Execução" -Prompt "Intervalo entre backups (minutos, 1-1440)" -DefaultValue "30"
    } until ($intervalo -match '^\d+$' -and [int]$intervalo -ge 1 -and [int]$intervalo -le 1440)

    if (-not (Test-Path $pastaDestino)) {
        New-Item -Path $pastaDestino -ItemType Directory -Force | Out-Null
    }

    @{
        pastaMonitorada   = $pastaMonitorada
        pastaDestino      = $pastaDestino
        retention         = [int]$retention
        intervaloExecucao = [int]$intervalo
    } | ConvertTo-Json | Set-Content $configPath

    $config = Get-Content $configPath -Raw | ConvertFrom-Json
}

# --- VERIFICAÇÃO DO MEGASYNC ---
function Test-MEGAsyncInstalled {
    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\MEGAsync"
    $exePath = "${env:ProgramFiles}\MEGA\MEGAsync\MEGAsync.exe"
    return (Test-Path $regPath) -or (Test-Path $exePath)
}

if (-not (Test-MEGAsyncInstalled)) {
    $msgResult = [System.Windows.MessageBox]::Show(
        "MEGAsync não está instalado. Deseja abrir a página de download?",
        "Instalação Necessária",
        "YesNo",
        "Warning"
    )
    
    if ($msgResult -eq "Yes") {
        Start-Process "https://mega.io/desktop"
        [System.Windows.MessageBox]::Show(
            "Após a instalação, configure a sincronização da pasta:`n$($config.pastaDestino)",
            "Configuração do MEGA",
            "OK",
            "Information"
        ) | Out-Null
    }
    else {
        [System.Windows.MessageBox]::Show(
            "O backup local funcionará, mas a sincronização com a nuvem não ocorrerá sem o MEGAsync.",
            "Aviso",
            "OK",
            "Warning"
        ) | Out-Null
    }
}

# --- AUTO-INSTALAÇÃO ---
$scriptName = "backup_rotativo.ps1"
$caminhoDestinoScript = Join-Path $pastaScripts $scriptName

if ($MyInvocation.MyCommand.Path -ne $caminhoDestinoScript) {
    Copy-Item -Path $MyInvocation.MyCommand.Path -Destination $caminhoDestinoScript -Force
    # Também garante que o arquivo de configuração está na pasta de destino
    if (-not (Test-Path $configPath)) {
        # (Já foi criado acima, mas por segurança)
        @{
            pastaMonitorada   = $config.pastaMonitorada
            pastaDestino      = $config.pastaDestino
            retention         = [int]$config.retention
            intervaloExecucao = [int]$config.intervaloExecucao
        } | ConvertTo-Json | Set-Content $configPath
    }
}

# --- AGENDAMENTO AUTOMÁTICO ---
$taskName = "BackupRotativoRodolfo"
$taskExists = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

if (-not $taskExists) {
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
        -RepetitionInterval (New-TimeSpan -Minutes $config.intervaloExecucao)
    
    $action = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument "-WindowStyle Hidden -File `"$caminhoDestinoScript`""
    
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" `
        -LogonType ServiceAccount -RunLevel Highest
    
    Register-ScheduledTask -TaskName $taskName `
        -Trigger $trigger `
        -Action $action `
        -Principal $principal | Out-Null
}

# --- INICIALIZAÇÃO DO WINDOWS ---
$startupFolder = [Environment]::GetFolderPath("Startup")
$shortcutName = "BackupRotativo.lnk"
$shortcutPath = Join-Path $startupFolder $shortcutName

if (-not (Test-Path $shortcutPath)) {
    $WScriptShell = New-Object -ComObject WScript.Shell
    $shortcut = $WScriptShell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = "powershell.exe"
    $shortcut.Arguments = "-WindowStyle Hidden -File `"$caminhoDestinoScript`""
    $shortcut.Save()
}

# --- LÓGICA DE BACKUP ---
$arquivoControle = Join-Path $config.pastaDestino "ultimo_backup.txt"
$arquivoMaisRecente = Get-ChildItem -Path $config.pastaMonitorada -File | 
                     Sort-Object LastWriteTime -Descending | 
                     Select-Object -First 1

if ($arquivoMaisRecente) {
    $infoAtual = "$($arquivoMaisRecente.Name)|$($arquivoMaisRecente.LastWriteTimeUtc.Ticks)"
    $infoAnterior = if (Test-Path $arquivoControle) { Get-Content $arquivoControle -Raw } else { $null }

    if ($infoAtual -ne $infoAnterior) {
        $nomeBackup = "$(Get-Date -Format 'yyyyMMdd_HHmmss')_$($arquivoMaisRecente.Name)"
        $caminhoDestino = Join-Path $config.pastaDestino $nomeBackup
        Copy-Item -Path $arquivoMaisRecente.FullName -Destination $caminhoDestino -Force
        Set-Content -Path $arquivoControle -Value $infoAtual

        Get-ChildItem -Path $config.pastaDestino -File -Exclude $arquivoControle |
            Sort-Object LastWriteTime -Descending |
            Select-Object -Skip $config.retention |
            Remove-Item -Force
    }
}
