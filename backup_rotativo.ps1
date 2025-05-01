<#
.SYNOPSIS
Script de backup rotativo com configuração interativa, validação, auto-instalação e agendamento.
#>

# Carrega assemblies para interface gráfica
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName PresentationFramework

# Verifica se está rodando como administrador
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show("Este script precisa ser executado como Administrador. Ele será reiniciado com privilégios elevados.", "Permissão necessária", "OK", "Warning") | Out-Null

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $psi.Verb = "runas"
    try {
        [System.Diagnostics.Process]::Start($psi) | Out-Null
    } catch {
        [System.Windows.MessageBox]::Show("Execução como administrador cancelada pelo usuário.", "Cancelado", "OK", "Error") | Out-Null
    }
    exit
}

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
            ([int]$config.intervaloExecucao -lt 1 -or [int]$config.intervaloExecucao -gt 1440 -and $config.modo -eq "intervalo") -or
            ($config.horarioFixo -notmatch '^\d{2}:\d{2}$' -and $config.modo -eq "horario")) {
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
        $retention = Show-InputBox -Title "Configuração de Retenção" -Prompt "Quantos backups deseja manter? (1-31)" -DefaultValue "3"
    } until ($retention -match '^\d+$' -and [int]$retention -ge 1 -and [int]$retention -le 31)

    do {
        $modoAgendamento = Show-InputBox -Title "Modo de Agendamento" `
            -Prompt "Digite 1 para agendar por intervalo em minutos, ou 2 para agendar em horário fixo a cada 12h (hh:mm):" `
            -DefaultValue "1"
    } until ($modoAgendamento -eq "1" -or $modoAgendamento -eq "2")

    if ($modoAgendamento -eq "1") {
        do {
            $intervalo = Show-InputBox -Title "Intervalo de Execução" -Prompt "Intervalo entre backups (minutos, 1-1440)" -DefaultValue "120"
        } until ($intervalo -match '^\d+$' -and [int]$intervalo -ge 1 -and [int]$intervalo -le 1440)
        $configAgendamento = @{
            modo = "intervalo"
            intervaloExecucao = [int]$intervalo
        }
    } else {
        do {
            $horaFixa = Show-InputBox -Title "Horário Fixo" -Prompt "Digite o horário para rodar (hh:mm, 24h)" -DefaultValue "04:00"
        } until ($horaFixa -match '^\d{2}:\d{2}$')
        $configAgendamento = @{
            modo = "horario"
            horarioFixo = $horaFixa
        }
    }

    if (-not (Test-Path $pastaDestino)) {
        New-Item -Path $pastaDestino -ItemType Directory -Force | Out-Null
    }

    @{
        pastaMonitorada   = $pastaMonitorada
        pastaDestino      = $pastaDestino
        retention         = [int]$retention
        modo              = $configAgendamento.modo
        intervaloExecucao = $configAgendamento.intervaloExecucao
        horarioFixo       = $configAgendamento.horarioFixo
    } | ConvertTo-Json | Set-Content $configPath

    $config = Get-Content $configPath -Raw | ConvertFrom-Json
}

# --- AUTO-INSTALAÇÃO ---
$scriptName = "backup_rotativo.ps1"
$caminhoDestinoScript = Join-Path $pastaScripts $scriptName

if ($MyInvocation.MyCommand.Path -ne $caminhoDestinoScript) {
    Copy-Item -Path $MyInvocation.MyCommand.Path -Destination $caminhoDestinoScript -Force
    if (-not (Test-Path $configPath)) {
        @{
            pastaMonitorada   = $config.pastaMonitorada
            pastaDestino      = $config.pastaDestino
            retention         = [int]$config.retention
            modo              = $config.modo
            intervaloExecucao = $config.intervaloExecucao
            horarioFixo       = $config.horarioFixo
        } | ConvertTo-Json | Set-Content $configPath
    }
}

# --- AGENDAMENTO AUTOMÁTICO ---
$taskName = "BackupRotativoRodolfo"
$taskExists = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

if (-not $taskExists) {
    if ($config.modo -eq "intervalo") {
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
            -RepetitionInterval (New-TimeSpan -Minutes $config.intervaloExecucao)
    } else {
        $hora = [datetime]::ParseExact($config.horarioFixo, "HH:mm", $null)
        $trigger = New-ScheduledTaskTrigger -Daily -At $hora
    }
    
    $action = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument "-WindowStyle Hidden -File `"$caminhoDestinoScript`""
    
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" `
        -LogonType ServiceAccount -RunLevel Highest
    
    Register-ScheduledTask -TaskName $taskName `
        -Trigger $trigger `
        -Action $action `
        -Principal $principal | Out-Null
}

# --- LOGGING ---
$logPath = Join-Path $pastaScripts "backup_log.txt"
function Write-Log($mensagem) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp $mensagem" | Out-File -FilePath $logPath -Append -Encoding utf8
}

try {
    # --- LÓGICA DE BACKUP ---
    $arquivoControle = Join-Path $config.pastaDestino "ultimo_backup.txt"
    $nomeArquivoControle = [IO.Path]::GetFileName($arquivoControle)
    $arquivoMaisRecente = Get-ChildItem -Path $config.pastaMonitorada -File | 
                         Sort-Object LastWriteTime -Descending | 
                         Select-Object -First 1

    if ($arquivoMaisRecente) {
        $infoAtual = "$($arquivoMaisRecente.Name)|$($arquivoMaisRecente.LastWriteTimeUtc.Ticks)"
        $infoAnterior = if (Test-Path $arquivoControle) { Get-Content $arquivoControle -Raw } else { $null }

        if ($infoAtual -ne $infoAnterior) {
            # Copia o arquivo mantendo o mesmo nome do arquivo original
            $nomeBackup = $arquivoMaisRecente.Name
            $caminhoDestino = Join-Path $config.pastaDestino $nomeBackup
            try {
                Copy-Item -Path $arquivoMaisRecente.FullName -Destination $caminhoDestino -Force
                Set-Content -Path $arquivoControle -Value $infoAtual
                Write-Log "Backup realizado: $nomeBackup"
            } catch {
                Write-Log "Erro ao copiar arquivo de backup: $_"
                throw
            }

            try {
                Get-ChildItem -Path $config.pastaDestino -File -Exclude $nomeArquivoControle |
                    Sort-Object LastWriteTime -Descending |
                    Select-Object -Skip $config.retention |
                    Remove-Item -Force
                Write-Log "Backups antigos removidos, mantendo $($config.retention) arquivos."
            } catch {
                Write-Log "Erro ao remover backups antigos: $_"
            }        
        } else {
            Write-Log "Nenhuma alteração detectada, backup não necessário."
        }
    } else {
        Write-Log "Nenhum arquivo encontrado na pasta monitorada."
    }

    [System.Windows.MessageBox]::Show("Backup rotativo concluído com sucesso!", "Backup Concluído", "OK", "Information") | Out-Null
} catch {
    Write-Log "Erro global: $_"
    [System.Windows.MessageBox]::Show("Erro ao executar o backup rotativo: $_", "Erro no Backup", "OK", "Error") | Out-Null
}

exit
# --- FIM DO SCRIPT ---
