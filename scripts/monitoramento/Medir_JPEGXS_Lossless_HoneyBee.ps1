# =============================================================
# MEDICAO JPEG XS LOSSLESS - HoneyBee
# SVT-JPEG-XS no Windows / PowerShell 5.1 ou 7+
# Codifica novamente com os mesmos parametros do teste lossless
# e mede CPU (normalizada por todos os processadores logicos),
# memoria RAM residente e tempo de parede.
# Nao substitui os arquivos .jxs ja existentes.
# =============================================================

$ErrorActionPreference = 'Stop'

$Base = 'C:\Users\pedro\Desktop\TCC2\HoneyBee'
$Encoder = 'C:\JPEGXS\SVT-JPEG-XS-main\SVT-JPEG-XS-main\Bin\Release\SvtJpegxsEncApp.exe'
$Entrada = Join-Path $Base 'HoneyBee_1280x720.yuv'
$SaidaDir = Join-Path $Base 'JPEGXS\teste_lossless_telemetria'
$SaidaJXS = Join-Path $SaidaDir 'HoneyBee_lossless_monitorado.jxs'
$AmostrasCSV = Join-Path $SaidaDir 'amostras_lossless.csv'
$ResumoCSV = Join-Path $SaidaDir 'resumo_lossless.csv'
$LogStdout = Join-Path $SaidaDir 'encoder_stdout.log'
$LogStderr = Join-Path $SaidaDir 'encoder_stderr.log'
$IntervaloMs = 250
$FPS = 120
$Quadros = 600

foreach ($Arquivo in @($Encoder, $Entrada)) {
    if (-not (Test-Path -LiteralPath $Arquivo -PathType Leaf)) {
        throw "Arquivo nao encontrado: $Arquivo"
    }
}
New-Item -ItemType Directory -Path $SaidaDir -Force | Out-Null

# Os caminhos de entrada e saida ficam entre aspas para evitar erros
# quando ha espacos no nome das pastas.
function Quote-Arg([string]$Value) {
    return '"' + $Value.Replace('"', '\"') + '"'
}

$ListaArgumentos = @(
    '-i', (Quote-Arg $Entrada),
    '-w', '1280',
    '-h', '720',
    '--colour-format', 'yuv420',
    '--input-depth', '8',
    '--lossless', '1',
    '--coding-raw', '0',
    '--stream-profile', 'auto',
    '-n', "$Quadros",
    '-b', (Quote-Arg $SaidaJXS)
)
$LinhaArgumentos = $ListaArgumentos -join ' '

$Info = New-Object System.Diagnostics.ProcessStartInfo
$Info.FileName = $Encoder
$Info.Arguments = $LinhaArgumentos
$Info.WorkingDirectory = Split-Path -Parent $Encoder
$Info.UseShellExecute = $false
$Info.CreateNoWindow = $true
$Info.RedirectStandardOutput = $true
$Info.RedirectStandardError = $true

$Processo = New-Object System.Diagnostics.Process
$Processo.StartInfo = $Info
$Logical = [Environment]::ProcessorCount
$Amostras = New-Object 'System.Collections.Generic.List[object]'
$Cronometro = [System.Diagnostics.Stopwatch]::StartNew()

Write-Host "HoneyBee | JPEG XS LOSSLESS | $Quadros quadros | $FPS FPS"
Write-Host "CPU: $Logical processadores logicos | amostragem: $IntervaloMs ms"
Write-Host "Comando: $Encoder $LinhaArgumentos"
Write-Host "Saida: $SaidaJXS"

try {
    if (-not $Processo.Start()) { throw 'Nao foi possivel iniciar o encoder.' }
    # Ler ambos os fluxos de forma assincrona evita bloqueio por buffer cheio.
    $TarefaOut = $Processo.StandardOutput.ReadToEndAsync()
    $TarefaErr = $Processo.StandardError.ReadToEndAsync()

    $Processo.Refresh()
    $CPUAnterior = $Processo.TotalProcessorTime.TotalMilliseconds
    $TempoAnterior = $Cronometro.Elapsed.TotalMilliseconds
    $RamPicoBytes = [double]$Processo.WorkingSet64
    $RamAcumuladaBytesTempo = 0.0
    $TempoRAMms = 0.0
    $CPUAcumuladoMs = 0.0
    $CPUPercentualPico = 0.0

    while (-not $Processo.WaitForExit($IntervaloMs)) {
        $Processo.Refresh()
        $TempoAtual = $Cronometro.Elapsed.TotalMilliseconds
        $Deltat = $TempoAtual - $TempoAnterior
        $CPUNovo = $Processo.TotalProcessorTime.TotalMilliseconds
        $Deltacpu = [math]::Max(0.0, ($CPUNovo - $CPUAnterior))
        $CPUAnterior = $CPUNovo
        $TempoAnterior = $TempoAtual

        $RAMAtual = [double]$Processo.WorkingSet64
        $RamPicoBytes = [math]::Max($RamPicoBytes, $RAMAtual)
        if ($Deltat -gt 0) {
            $CPUPct = 100.0 * $Deltacpu / ($Deltat * $Logical)
            $CPUPercentualPico = [math]::Max($CPUPercentualPico, $CPUPct)
            $CPUAcumuladoMs += $Deltacpu
            $RamAcumuladaBytesTempo += $RAMAtual * $Deltat
            $TempoRAMms += $Deltat
            $Amostras.Add([pscustomobject]@{
                Tempo_s = [math]::Round(($TempoAtual / 1000), 3)
                CPU_Pct_Total = [math]::Round($CPUPct, 3)
                RAM_MB = [math]::Round(($RAMAtual / 1MB), 3)
            })
        }
    }

    $Cronometro.Stop()
    $Processo.Refresh()
    $ExitCode = $Processo.ExitCode
    # TotalProcessorTime e PeakWorkingSet64 refletem o processo todo,
    # inclusive o trecho inicial/final entre duas amostras.
    $CPUmsTotal = $Processo.TotalProcessorTime.TotalMilliseconds
    $RamPicoBytes = [math]::Max($RamPicoBytes, [double]$Processo.PeakWorkingSet64)
    $DuracaoSeg = $Cronometro.Elapsed.TotalSeconds
    $CpuMediaPct = if ($DuracaoSeg -gt 0) { 100.0 * $CPUmsTotal / ($DuracaoSeg * 1000 * $Logical) } else { 0 }
    $RamMediaMB = if ($TempoRAMms -gt 0) { $RamAcumuladaBytesTempo / $TempoRAMms / 1MB } else { $null }

    $TarefaOut.Wait()
    $TarefaErr.Wait()
    [System.IO.File]::WriteAllText($LogStdout, $TarefaOut.Result)
    [System.IO.File]::WriteAllText($LogStderr, $TarefaErr.Result)

    $Tamanho = if (Test-Path -LiteralPath $SaidaJXS) { (Get-Item -LiteralPath $SaidaJXS).Length } else { 0 }
    $Bitrate = if ($Tamanho -gt 0) { ($Tamanho * 8.0 * $FPS) / ($Quadros * 1000000) } else { $null }
    $ErrosQuadro = ($TarefaOut.Result + "`n" + $TarefaErr.Result) -match 'Error encode frame'
    $Status = if (($ExitCode -eq 0) -and ($Tamanho -gt 0) -and (-not $ErrosQuadro)) { 'OK' } else { 'FALHA' }

    $Resumo = [pscustomobject]@{
        Video = 'HoneyBee'
        Codec = 'JPEGXS'
        Modo = 'lossless'
        Quadros = $Quadros
        FPS = $FPS
        Status = $Status
        ExitCode = $ExitCode
        Tempo_Codificacao_s = [math]::Round($DuracaoSeg, 3)
        CPU_Media_Pct_Total = [math]::Round($CpuMediaPct, 3)
        CPU_Pico_Amostrado_Pct_Total = [math]::Round($CPUPercentualPico, 3)
        RAM_Media_MB = if ($null -ne $RamMediaMB) { [math]::Round($RamMediaMB, 3) } else { $null }
        RAM_Pico_MB = [math]::Round(($RamPicoBytes / 1MB), 3)
        Bitrate_Real_Mbps = if ($null -ne $Bitrate) { [math]::Round($Bitrate, 3) } else { $null }
        Tamanho_Bytes = $Tamanho
        Arquivo = $SaidaJXS
    }
    $Resumo | Export-Csv -LiteralPath $ResumoCSV -NoTypeInformation -Delimiter ';' -Encoding UTF8
    if ($Amostras.Count -gt 0) {
        $Amostras | Export-Csv -LiteralPath $AmostrasCSV -NoTypeInformation -Delimiter ';' -Encoding UTF8
    }

    Write-Host ""
    Write-Host '===== RESULTADO ====='
    $Resumo | Format-List
    Write-Host "Resumo: $ResumoCSV"
    Write-Host "Amostras: $AmostrasCSV"
    Write-Host "Logs: $LogStdout | $LogStderr"
    if ($Status -ne 'OK') { Write-Warning 'Codificacao nao validada; veja os logs.' }
} finally {
    if (-not $Processo.HasExited) {
        try { $Processo.Kill() } catch { }
    }
    $Processo.Dispose()
}