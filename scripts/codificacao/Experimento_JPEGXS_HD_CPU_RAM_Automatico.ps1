# ============================================================
# EXPERIMENTO JPEG XS HD - UM VIDEO POR EXECUCAO
# Encoder / decoder: SVT-JPEG-XS
# Qualidade: VMAF (FFmpeg/libvmaf)
# Entrada e referencia: YUV420p 8-bit, 1280x720
# Preserva os .jxs e os .yuv decodificados para analise visual.
# Coleta CPU e RAM do processo a cada 250 ms (codificacao,
# decodificacao e VMAF), com CSV resumido e CSVs de telemetria.
# ============================================================

$ErrorActionPreference = 'Stop'

# ================== CONFIGURACAO ============================
# Para mudar de video, altere SOMENTE esta variavel.
$Video = 'Bosphorus'

$RaizTCC = 'C:\Users\pedro\Desktop\TCC2'
$PastaSVT = 'C:\JPEGXS\SVT-JPEG-XS-main\SVT-JPEG-XS-main\Bin\Release'

# O BPP minimo de triagem e empirico e NAO e um limite oficial do codec.
# A selecao dos bitrates e feita automaticamente depois da tabela de videos.
$BPPMinimoTriagem = 0.18

$CalcularVMAF = $true
$IntervaloAmostragemMs = 250
$Largura = 1280
$Altura = 720

$Videos = @{
    'Beauty'     = @{ FPS = 120; Duracao = 5.0  }
    'Bosphorus'  = @{ FPS = 120; Duracao = 5.0  }
    'HoneyBee'   = @{ FPS = 120; Duracao = 5.0  }
    'Jockey'     = @{ FPS = 120; Duracao = 5.0  }
    'ReadySetGo' = @{ FPS = 120; Duracao = 5.0  }
    'ShakeNDry'  = @{ FPS = 120; Duracao = 2.5  }
    'FlowerKids' = @{ FPS = 50;  Duracao = 12.0 }
    'FlowerPan'  = @{ FPS = 50;  Duracao = 12.0 }
    'Lips'       = @{ FPS = 120; Duracao = 5.0  }
    'RaceNight'  = @{ FPS = 50;  Duracao = 12.0 }
    'RiverBank'  = @{ FPS = 50;  Duracao = 12.0 }
    'SunBath'    = @{ FPS = 50;  Duracao = 6.0  }
}

# Selecao automatica dos bitrates por FPS.
# Em 120 FPS: 20, 30, 40 e 50 Mbps.
# Em 50 FPS: 10, 15, 20, 30, 40 e 50 Mbps.
# Cada tentativa ainda e validada pelo encoder e decoder.
if ($Videos[$Video].FPS -eq 120) {
    $BitratesMbps = @(20, 30, 40, 50)
} else {
    $BitratesMbps = @(10, 15, 20, 30, 40, 50)
}

function Quotar([string]$Valor) {
    return '"' + $Valor + '"'
}

# CPU % = fracao da capacidade TOTAL dos processadores logicos.
# Exemplo: em 8 processadores logicos, 100% de UM equivale a 12,5% total.
# RAM = Working Set (memoria fisica residente do processo), em MB.
function Executar-ComMonitoramento {
    param(
        [string]$Executavel,
        [string]$Argumentos,
        [string]$Trabalho,
        [string]$LogSaida,
        [string]$LogErro,
        [string]$LogTelemetria,
        [int]$IntervaloMs = 250,
        [int]$ProcessadoresLogicos = 1
    )

    foreach ($arquivo in @($LogSaida, $LogErro, $LogTelemetria)) {
        if (Test-Path -LiteralPath $arquivo) {
            Remove-Item -LiteralPath $arquivo -Force
        }
    }

    $amostras = New-Object 'System.Collections.Generic.List[object]'
    $cronometro = [System.Diagnostics.Stopwatch]::StartNew()
    $codigo = -1
    $falhaMonitor = ''
    $ultimoTempo = 0.0
    $ultimoCPU = 0.0
    $somaRAMxTempo = 0.0
    $tempoComRAM = 0.0
    $picoCPU = 0.0
    $picoRAM = 0.0
    $picoPrivada = 0.0
    $cpuUltimaAmostra = 0.0
    $processo = $null

    try {
        # ProcessStartInfo oferece leitura direta do ExitCode e das metricas.
        # ReadToEndAsync drena stdout/stderr para evitar bloqueios do encoder.
        $info = New-Object System.Diagnostics.ProcessStartInfo
        $info.FileName = $Executavel
        $info.Arguments = $Argumentos
        $info.WorkingDirectory = $Trabalho
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true

        $processo = New-Object System.Diagnostics.Process
        $processo.StartInfo = $info
        if (-not $processo.Start()) { throw 'Processo nao iniciou.' }
        $tarefaSaida = $processo.StandardOutput.ReadToEndAsync()
        $tarefaErro = $processo.StandardError.ReadToEndAsync()

        while (-not $processo.HasExited) {
            try {
                $processo.Refresh()
                $tempoAtual = $cronometro.Elapsed.TotalSeconds
                $cpuAtual = $processo.TotalProcessorTime.TotalSeconds
                $ramMB = $processo.WorkingSet64 / 1MB
                $privadaMB = $processo.PrivateMemorySize64 / 1MB
                $picoRAMProcesso = $processo.PeakWorkingSet64 / 1MB
                $deltaTempo = $tempoAtual - $ultimoTempo
                $deltaCPU = $cpuAtual - $ultimoCPU

                if ($deltaTempo -gt 0) {
                    $cpuPct = [math]::Max(0, ($deltaCPU / $deltaTempo) * 100.0 / $ProcessadoresLogicos)
                    $cpuPct = [math]::Min(100, $cpuPct)
                    $picoCPU = [math]::Max($picoCPU, $cpuPct)
                    $picoRAM = [math]::Max($picoRAM, $picoRAMProcesso)
                    $picoPrivada = [math]::Max($picoPrivada, $privadaMB)
                    $somaRAMxTempo += $ramMB * $deltaTempo
                    $tempoComRAM += $deltaTempo
                    $cpuUltimaAmostra = $cpuAtual
                    $amostras.Add([pscustomobject][ordered]@{
                        Instante = (Get-Date).ToString('o')
                        Segundos_Desde_Inicio = [math]::Round($tempoAtual, 3)
                        CPU_Pct_Total = [math]::Round($cpuPct, 3)
                        RAM_Residente_MB = [math]::Round($ramMB, 3)
                        Memoria_Privada_MB = [math]::Round($privadaMB, 3)
                    })
                    $ultimoTempo = $tempoAtual
                    $ultimoCPU = $cpuAtual
                }
            }
            catch {
                # O processo pode encerrar durante uma amostragem.
            }
            Start-Sleep -Milliseconds $IntervaloMs
        }

        $processo.WaitForExit()
        $codigo = $processo.ExitCode
        [System.IO.File]::WriteAllText($LogSaida, [string]$tarefaSaida.Result)
        [System.IO.File]::WriteAllText($LogErro, [string]$tarefaErro.Result)
    }
    catch {
        $falhaMonitor = $_.Exception.ToString()
        # Nunca esconder a excecao real: ela sera registrada no CSV e no log.
        Add-Content -LiteralPath $LogErro -Value ("`n[ERRO_MONITORAMENTO] " + $falhaMonitor)
    }
    finally {
        $cronometro.Stop()
        if ($null -ne $processo) { $processo.Dispose() }
    }

    if ($amostras.Count -gt 0) {
        $amostras | Export-Csv -LiteralPath $LogTelemetria -NoTypeInformation -Encoding UTF8
    }

    $duracao = $cronometro.Elapsed.TotalSeconds
    $mediaCPU = if ($duracao -gt 0 -and $amostras.Count -gt 0) {
        [math]::Min(100, ($cpuUltimaAmostra / $duracao) * 100.0 / $ProcessadoresLogicos)
    } else { $null }
    $mediaRAM = if ($tempoComRAM -gt 0) { $somaRAMxTempo / $tempoComRAM } else { $null }

    return [pscustomobject]@{
        Codigo = $codigo
        ErroMonitor = $falhaMonitor
        Segundos = [math]::Round($duracao, 3)
        CPU_Media_Pct_Total = if ($null -ne $mediaCPU) { [math]::Round($mediaCPU, 3) } else { $null }
        CPU_Pico_Pct_Total = if ($amostras.Count -gt 0) { [math]::Round($picoCPU, 3) } else { $null }
        CPU_Tempo_Segundos = [math]::Round($cpuUltimaAmostra, 3)
        RAM_Media_MB = if ($null -ne $mediaRAM) { [math]::Round($mediaRAM, 3) } else { $null }
        RAM_Pico_MB = if ($amostras.Count -gt 0) { [math]::Round($picoRAM, 3) } else { $null }
        Memoria_Privada_Pico_MB = if ($amostras.Count -gt 0) { [math]::Round($picoPrivada, 3) } else { $null }
        Amostras = $amostras.Count
    }
}

function Copiar-Metricas {
    param(
        [System.Collections.IDictionary]$Registro,
        [string]$Fase,
        $Medicao
    )
    $Registro["Tempo_${Fase}_Segundos"] = $Medicao.Segundos
    $Registro["CPU_${Fase}_Media_Pct_Total"] = $Medicao.CPU_Media_Pct_Total
    $Registro["CPU_${Fase}_Pico_Pct_Total"] = $Medicao.CPU_Pico_Pct_Total
    $Registro["CPU_${Fase}_Tempo_Segundos"] = $Medicao.CPU_Tempo_Segundos
    $Registro["RAM_${Fase}_Media_MB"] = $Medicao.RAM_Media_MB
    $Registro["RAM_${Fase}_Pico_MB"] = $Medicao.RAM_Pico_MB
    $Registro["Memoria_Privada_${Fase}_Pico_MB"] = $Medicao.Memoria_Privada_Pico_MB
    $Registro["Amostras_${Fase}"] = $Medicao.Amostras
}

function Log-ContemErroDeQuadro {
    param([string]$LogSaida, [string]$LogErro, [string]$Padrao)
    foreach ($caminho in @($LogSaida, $LogErro)) {
        if ((Test-Path -LiteralPath $caminho) -and
            (Select-String -LiteralPath $caminho -Pattern $Padrao -Quiet)) {
            return $true
        }
    }
    return $false
}

function Adicionar-Resultado {
    param($Registro)
    $script:Resultados += [pscustomobject]$Registro
    # Salva progressivamente: evita perder resultados se houver interrupcao.
    $script:Resultados | Export-Csv -LiteralPath $script:ArquivoCSV -NoTypeInformation -Encoding UTF8
}

# ================== VALIDACOES ==============================
if (-not $Videos.ContainsKey($Video)) {
    throw "Video '$Video' nao encontrado. Opcoes: $($Videos.Keys -join ', ')"
}
$Codificador = Join-Path $PastaSVT 'SvtJpegxsEncApp.exe'
$Decodificador = Join-Path $PastaSVT 'SvtJpegxsDecApp.exe'
$ComandoFFmpeg = Get-Command 'ffmpeg.exe' -ErrorAction SilentlyContinue
if (-not (Test-Path -LiteralPath $Codificador)) { throw "Encoder nao encontrado: $Codificador" }
if (-not (Test-Path -LiteralPath $Decodificador)) { throw "Decoder nao encontrado: $Decodificador" }
if (-not $ComandoFFmpeg) { throw 'ffmpeg.exe nao encontrado no PATH.' }
$FFmpeg = $ComandoFFmpeg.Source
$ProcessadoresLogicos = [Environment]::ProcessorCount

$FPS = [int]$Videos[$Video].FPS
$Duracao = [double]$Videos[$Video].Duracao
$Frames = [int][math]::Round($FPS * $Duracao)
$TamanhoYUV = [int64]($Frames * $Largura * $Altura * 3 / 2)
$PastaVideo = Join-Path $RaizTCC $Video
$Referencia = Join-Path $PastaVideo "${Video}_1280x720.yuv"
if (-not (Test-Path -LiteralPath $Referencia)) {
    throw "Referencia HD nao encontrada: $Referencia"
}
if ((Get-Item -LiteralPath $Referencia).Length -lt $TamanhoYUV) {
    throw "Referencia incompleta. Esperado ao menos $TamanhoYUV bytes para $Frames quadros."
}

$PastaSaida = Join-Path $PastaVideo 'JPEGXS'
$PastaJXS = Join-Path $PastaSaida 'bitstreams'
$PastaLogs = Join-Path $PastaSaida 'logs'
$PastaMetricas = Join-Path $PastaSaida 'metricas'
$PastaYUV = Join-Path $PastaSaida 'decodificados'
$PastaTelemetria = Join-Path $PastaSaida 'telemetria'
foreach ($p in @($PastaSaida, $PastaJXS, $PastaLogs, $PastaMetricas, $PastaYUV, $PastaTelemetria)) {
    New-Item -Path $p -ItemType Directory -Force | Out-Null
}
$ArquivoCSV = Join-Path $PastaSaida "resultados_jpegxs_${Video}_hd_cpu_ram.csv"
$Resultados = @()

Write-Host "`nVIDEO: $Video | ${Largura}x${Altura} | $FPS FPS | $Frames quadros" -ForegroundColor Cyan
Write-Host "CPU: $ProcessadoresLogicos processadores logicos | intervalo: $IntervaloAmostragemMs ms"
Write-Host "BPP minimo de triagem: $BPPMinimoTriagem (empirico; NAO e limite oficial)"
Write-Host "Referencia: $Referencia"

foreach ($BitrateAlvo in $BitratesMbps) {
    $BPP = [double]$BitrateAlvo * 1000000.0 / ([double]$Largura * $Altura * $FPS)
    $BPPTxt = $BPP.ToString('0.00000000', [System.Globalization.CultureInfo]::InvariantCulture)
    $NomeBase = "${Video}_jpegxs_HD_${BitrateAlvo}M"
    $ArquivoJXS = Join-Path $PastaJXS "$NomeBase.jxs"
    $ArquivoYUV = Join-Path $PastaYUV "${NomeBase}_decoded.yuv"
    $ArquivoJSON = Join-Path $PastaMetricas "${NomeBase}_vmaf.json"

    $LogEncOut = Join-Path $PastaLogs "${NomeBase}_encode_stdout.txt"
    $LogEncErr = Join-Path $PastaLogs "${NomeBase}_encode_stderr.txt"
    $LogDecOut = Join-Path $PastaLogs "${NomeBase}_decode_stdout.txt"
    $LogDecErr = Join-Path $PastaLogs "${NomeBase}_decode_stderr.txt"
    $LogVMAFOut = Join-Path $PastaLogs "${NomeBase}_vmaf_stdout.txt"
    $LogVMAFErr = Join-Path $PastaLogs "${NomeBase}_vmaf_stderr.txt"
    $TeleEnc = Join-Path $PastaTelemetria "${NomeBase}_codificacao_cpu_ram.csv"
    $TeleDec = Join-Path $PastaTelemetria "${NomeBase}_decodificacao_cpu_ram.csv"
    $TeleVMAF = Join-Path $PastaTelemetria "${NomeBase}_vmaf_cpu_ram.csv"

    $Registro = [ordered]@{
        Video = $Video
        FPS = $FPS
        Frames = $Frames
        Resolucao = "${Largura}x${Altura}"
        Processadores_Logicos = $ProcessadoresLogicos
        Bitrate_Alvo_Mbps = $BitrateAlvo
        BPP_Configurado = $BPPTxt
        Status = 'NAO_EXECUTADO'
        Codigo_Saida_Encoder = $null
        Erro_Monitor_Encoder = $null
        Erro_Quadro_Encoder = $null
        Codigo_Saida_Decoder = $null
        Erro_Monitor_Decoder = $null
        Codigo_Saida_VMAF = $null
        Erro_Monitor_VMAF = $null
        Tamanho_Bytes = $null
        Bitrate_Real_Mbps = $null
        VMAF = $null
        Arquivo_JXS = $ArquivoJXS
        Arquivo_YUV = $ArquivoYUV
        Arquivo_JSON = $ArquivoJSON
        Log_Encoder = $LogEncErr
        Telemetria_Codificacao = $TeleEnc
        Telemetria_Decodificacao = $TeleDec
        Telemetria_VMAF = $TeleVMAF
    }
    foreach ($Fase in @('Codificacao', 'Decodificacao', 'VMAF')) {
        foreach ($Campo in @('Tempo', 'CPU_Media', 'CPU_Pico', 'CPU_Tempo', 'RAM_Media', 'RAM_Pico', 'Memoria_Privada_Pico', 'Amostras')) {
            switch ($Campo) {
                'Tempo' { $Chave = "Tempo_${Fase}_Segundos" }
                'CPU_Media' { $Chave = "CPU_${Fase}_Media_Pct_Total" }
                'CPU_Pico' { $Chave = "CPU_${Fase}_Pico_Pct_Total" }
                'CPU_Tempo' { $Chave = "CPU_${Fase}_Tempo_Segundos" }
                'RAM_Media' { $Chave = "RAM_${Fase}_Media_MB" }
                'RAM_Pico' { $Chave = "RAM_${Fase}_Pico_MB" }
                'Memoria_Privada_Pico' { $Chave = "Memoria_Privada_${Fase}_Pico_MB" }
                'Amostras' { $Chave = "Amostras_${Fase}" }
            }
            $Registro[$Chave] = $null
        }
    }

    Write-Host "`n=== $BitrateAlvo Mbps | BPP = $BPPTxt ===" -ForegroundColor Yellow

    if ($BPP -lt $BPPMinimoTriagem) {
        $Registro.Status = 'NAO_TESTADO_BPP_BAIXO'
        Write-Host 'Ignorado pela triagem empirica de BPP; NAO significa falha do encoder.' -ForegroundColor DarkYellow
        Adicionar-Resultado $Registro
        continue
    }

    # Reexecutar o mesmo bitrate substitui seus arquivos, mas NUNCA
    # apaga o YUV apos o VMAF. Todos os YUV validos ficam salvos.
    foreach ($f in @($ArquivoJXS, $ArquivoYUV, $ArquivoJSON)) {
        if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force }
    }

    $ArgsEnc = '-i ' + (Quotar $Referencia) +
        " -w $Largura -h $Altura --colour-format yuv420 --input-depth 8" +
        " --bpp $BPPTxt -n $Frames --stream-profile main420" +
        ' -b ' + (Quotar $ArquivoJXS)
    $Enc = Executar-ComMonitoramento -Executavel $Codificador -Argumentos $ArgsEnc `
        -Trabalho $PastaSVT -LogSaida $LogEncOut -LogErro $LogEncErr `
        -LogTelemetria $TeleEnc -IntervaloMs $IntervaloAmostragemMs `
        -ProcessadoresLogicos $ProcessadoresLogicos
    Copiar-Metricas -Registro $Registro -Fase 'Codificacao' -Medicao $Enc
    $Registro.Codigo_Saida_Encoder = $Enc.Codigo
    $Registro.Erro_Monitor_Encoder = $Enc.ErroMonitor

    $ErroFrame = Log-ContemErroDeQuadro -LogSaida $LogEncOut -LogErro $LogEncErr `
        -Padrao 'Error encode frame|Failed to encode|Error while encoding'
    $Registro.Erro_Quadro_Encoder = $ErroFrame
    $TamanhoJXS = if (Test-Path -LiteralPath $ArquivoJXS) {
        (Get-Item -LiteralPath $ArquivoJXS).Length
    } else { 0 }
    # Nao classificar como falha apenas por um ExitCode suspeito:
    # decodificacao completa pode demonstrar que o bitstream e valido.
    if ($ErroFrame -or ($TamanhoJXS -le 0)) {
        $Registro.Status = 'FALHA_CODIFICACAO'
        Write-Host "Falha real: erro de quadro=$ErroFrame, bytes=$TamanhoJXS, exit=$($Enc.Codigo)" -ForegroundColor Red
        Write-Host "Log: $LogEncErr" -ForegroundColor Yellow
        Adicionar-Resultado $Registro
        continue
    }
    $AvisoExecucao = (($Enc.Codigo -ne 0) -or -not [string]::IsNullOrEmpty($Enc.ErroMonitor))
    if ($AvisoExecucao) {
        Write-Host "Aviso: encoder exit=$($Enc.Codigo). Arquivo existe; validando por decodificacao." -ForegroundColor Yellow
        Write-Host "Log: $LogEncErr" -ForegroundColor Yellow
    }

    Write-Host "Encoder: exit=$($Enc.Codigo) | tamanho=$TamanhoJXS bytes | erros de quadro=$ErroFrame" -ForegroundColor Cyan
    $Registro.Tamanho_Bytes = $TamanhoJXS
    $Registro.Bitrate_Real_Mbps = [math]::Round(($TamanhoJXS * 8.0) / $Duracao / 1000000.0, 6)

    $ArgsDec = '-i ' + (Quotar $ArquivoJXS) + " -n $Frames -o " + (Quotar $ArquivoYUV)
    $Dec = Executar-ComMonitoramento -Executavel $Decodificador -Argumentos $ArgsDec `
        -Trabalho $PastaSVT -LogSaida $LogDecOut -LogErro $LogDecErr `
        -LogTelemetria $TeleDec -IntervaloMs $IntervaloAmostragemMs `
        -ProcessadoresLogicos $ProcessadoresLogicos
    Copiar-Metricas -Registro $Registro -Fase 'Decodificacao' -Medicao $Dec
    $Registro.Codigo_Saida_Decoder = $Dec.Codigo
    $Registro.Erro_Monitor_Decoder = $Dec.ErroMonitor

    $ErroDec = Log-ContemErroDeQuadro -LogSaida $LogDecOut -LogErro $LogDecErr `
        -Padrao 'Error decode frame|Failed to decode|Error while decoding'
    $TamanhoDec = if (Test-Path -LiteralPath $ArquivoYUV) {
        (Get-Item -LiteralPath $ArquivoYUV).Length
    } else { 0 }
    if ($ErroDec -or ($TamanhoDec -ne $TamanhoYUV)) {
        $Registro.Status = 'FALHA_DECODIFICACAO'
        Write-Host "Decodificacao incompleta: $TamanhoDec bytes (esperado: $TamanhoYUV)." -ForegroundColor Red
        Adicionar-Resultado $Registro
        continue
    }

    if (-not $CalcularVMAF) {
        $Registro.Status = 'DECODIFICACAO_OK_SEM_VMAF'
        Write-Host "Decodificacao OK; bitrate real: $($Registro.Bitrate_Real_Mbps) Mbps" -ForegroundColor Green
        Adicionar-Resultado $Registro
        continue
    }

    # JSON com caminho RELATIVO: evita interpretar o 'C:' como filtro.
    $NomeJSON = "${NomeBase}_vmaf.json"
    $Filtro = "[0:v][1:v]libvmaf=log_fmt=json:log_path=$NomeJSON"
    $ArgsVMAF = '-nostdin -hide_banner -y -f rawvideo -pixel_format yuv420p' +
        " -video_size ${Largura}x${Altura} -framerate $FPS -i " + (Quotar $ArquivoYUV) +
        ' -f rawvideo -pixel_format yuv420p' +
        " -video_size ${Largura}x${Altura} -framerate $FPS -i " + (Quotar $Referencia) +
        ' -lavfi ' + (Quotar $Filtro) + " -frames:v $Frames -f null NUL"
    $V = Executar-ComMonitoramento -Executavel $FFmpeg -Argumentos $ArgsVMAF `
        -Trabalho $PastaMetricas -LogSaida $LogVMAFOut -LogErro $LogVMAFErr `
        -LogTelemetria $TeleVMAF -IntervaloMs $IntervaloAmostragemMs `
        -ProcessadoresLogicos $ProcessadoresLogicos
    Copiar-Metricas -Registro $Registro -Fase 'VMAF' -Medicao $V
    $Registro.Codigo_Saida_VMAF = $V.Codigo
    $Registro.Erro_Monitor_VMAF = $V.ErroMonitor

    if (-not (Test-Path -LiteralPath $ArquivoJSON)) {
        $Registro.Status = 'FALHA_VMAF'
        Write-Host 'Erro ao calcular VMAF (ver logs).' -ForegroundColor Red
        Adicionar-Resultado $Registro
        continue
    }

    try {
        $Json = Get-Content -LiteralPath $ArquivoJSON -Raw | ConvertFrom-Json
        $Score = [double]$Json.pooled_metrics.vmaf.mean
        if ([double]::IsNaN($Score) -or $Score -lt 0 -or $Score -gt 100) {
            throw 'VMAF fora do intervalo esperado.'
        }
        $Registro.VMAF = [math]::Round($Score, 6)
        $Registro.Status = if ($AvisoExecucao -or ($Dec.Codigo -ne 0) -or ($V.Codigo -ne 0) -or $Dec.ErroMonitor -or $V.ErroMonitor) { 'OK_COM_AVISO_PROCESSO' } else { 'OK' }
        Write-Host "$($Registro.Status): $($Registro.Bitrate_Real_Mbps) Mbps | VMAF $($Registro.VMAF)" -ForegroundColor Green
        Write-Host "CPU encoder media: $($Registro.CPU_Codificacao_Media_Pct_Total)% | RAM pico: $($Registro.RAM_Codificacao_Pico_MB) MB"
    }
    catch {
        $Registro.Status = 'FALHA_LEITURA_JSON'
        Write-Host "Nao foi possivel ler VMAF do JSON: $($_.Exception.Message)" -ForegroundColor Red
    }

    Adicionar-Resultado $Registro
}

Write-Host "`nExperimento finalizado. CSV: $ArquivoCSV" -ForegroundColor Cyan
$Resultados | Format-Table Bitrate_Alvo_Mbps, BPP_Configurado, Status, Bitrate_Real_Mbps, VMAF, CPU_Codificacao_Media_Pct_Total, RAM_Codificacao_Pico_MB -AutoSize