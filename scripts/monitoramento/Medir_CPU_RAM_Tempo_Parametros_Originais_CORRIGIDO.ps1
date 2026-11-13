#requires -Version 5.1
<#
 COLETA DE CPU, RAM E TEMPO - H.264, H.265 e AV1 - 12 videos
 Executa uma NOVA codificacao ABR de 2 passagens para cada video/bitrate.
 NAO altera arquivos MP4, logs, metricas, referencias ou JPEG XS existentes.
 Os arquivos produzidos nesta recodificacao sao TEMPORARIOS e, por padrao,
 sao apagados DEPOIS de confirmada a medicao. Logs e CSVs sao mantidos.
 PARAMETROS: reproduz Codificador.ps1 enviado, inclusive cpu-used 6,
 GOP, H264 keyint_min/sc_threshold, perfis, tags e container MP4.
#>
$ErrorActionPreference = 'Stop'

# ===================== AJUSTE AQUI ==========================
$RaizTCC = 'C:\Users\pedro\Desktop\TCC2'
$FFmpeg = 'ffmpeg.exe'      # ou caminho absoluto de ffmpeg.exe
$Largura = 1280
$Altura = 720
$BitratesMbps = @(1, 3, 5, 7, 10, 15, 50)
$Codecs = @('H264', 'H265', 'AV1')
$IntervaloMs = 250
$PularConcluidos = $true
$ApagarArquivosTemporariosAposSucesso = $true  # false para guardar novos MP4; nunca apaga MP4 originais
$ApagarArquivosTemporariosAposFalha = $false  # manter para diagnostico

# Configuracoes EXATAS declaradas no Codificador.ps1 original
$PresetH264 = 'medium'
$PresetH265 = 'medium'
$CpuUsedAV1 = 6             # igual ao Codificador.ps1 original

# Para iniciar por apenas um video/codec/bitrate, restrinja as listas
# acima e abaixo. Depois retorne as listas completas; o CSV permite retomar.
$Videos = @(
    @{ Nome='Beauty';     FPS=120; Segundos=5.0 },
    @{ Nome='Bosphorus';  FPS=120; Segundos=5.0 },
    @{ Nome='HoneyBee';   FPS=120; Segundos=5.0 },
    @{ Nome='Jockey';     FPS=120; Segundos=5.0 },
    @{ Nome='ReadySetGo'; FPS=120; Segundos=5.0 },
    @{ Nome='ShakeNDry';  FPS=120; Segundos=2.5 },
    @{ Nome='FlowerKids'; FPS=50;  Segundos=12.0 },
    @{ Nome='FlowerPan';  FPS=50;  Segundos=12.0 },
    @{ Nome='Lips';       FPS=120; Segundos=5.0 },
    @{ Nome='RaceNight';  FPS=50;  Segundos=12.0 },
    @{ Nome='RiverBank';  FPS=50;  Segundos=12.0 },
    @{ Nome='SunBath';    FPS=50;  Segundos=6.0 }
)
# ============================================================

$PastaResultado = Join-Path $RaizTCC '_Telemetria_Parametros_Originais'
$PastaTemporaria = Join-Path $PastaResultado 'temporarios'
$PastaLogs = Join-Path $PastaResultado 'logs'
$PastaAmostras = Join-Path $PastaResultado 'amostras'
$CSVResumo = Join-Path $PastaResultado 'resultados_cpu_ram_tempo.csv'
$CSVPassagens = Join-Path $PastaResultado 'resultados_por_passagem.csv'
$NLogicos = [Environment]::ProcessorCount
$Cultura = [Globalization.CultureInfo]::InvariantCulture

function Numero([double]$x) { return $x.ToString('0.######', $Cultura) }
function Arquivo-Completo([string]$p) { return [IO.Path]::GetFullPath($p) }
function Q([string]$texto) { return '"' + $texto.Replace('"','\"') + '"' }
function Gravar-CsvLinha([string]$caminho, [object]$linha) {
    if (Test-Path -LiteralPath $caminho) {
        $linha | Export-Csv -LiteralPath $caminho -Encoding UTF8 -Delimiter ';' -NoTypeInformation -Append
    } else {
        $linha | Export-Csv -LiteralPath $caminho -Encoding UTF8 -Delimiter ';' -NoTypeInformation
    }
}
function Novo-Diretorio([string]$caminho) {
    [void][IO.Directory]::CreateDirectory($caminho)
}

# Mede o processo FFmpeg em intervalos; CPU calculada pela diferenca entre
# TotalProcessorTime e o tempo real, normalizada pelo total de CPUs logicas.
# RAM (WorkingSet64) = memoria fisica residente do processo, nao RAM do PC.
function Medir-Processo {
    param(
        [string]$Exe, [string]$ArgumentosFFmpeg, [string]$Dir,
        [string]$Id, [string]$Fase
    )
    $logOut = Join-Path $PastaLogs ($Id + '_' + $Fase + '.stdout.log')
    $logErr = Join-Path $PastaLogs ($Id + '_' + $Fase + '.stderr.log')
    $csvAmostras = Join-Path $PastaAmostras ($Id + '_' + $Fase + '.csv')
    $logComando = Join-Path $PastaLogs ($Id + '_' + $Fase + '.comando.txt')
    [IO.File]::WriteAllText($logComando, $Exe + ' ' + $ArgumentosFFmpeg)
    $amostras = New-Object 'System.Collections.Generic.List[object]'
    $inicio = Get-Date
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $proc = $null
    $exitCode = -1
    $erroExecucao = ''
    $ultimoSeg = 0.0
    $ultimoCpu = 0.0
    $somaRamPonderada = 0.0
    $somaTempoRam = 0.0
    $picoCpu = 0.0
    $picoRam = 0.0
    $cpuFinal = 0.0
    try {
        if ([string]::IsNullOrWhiteSpace($ArgumentosFFmpeg)) { throw 'Argumentos do FFmpeg estao vazios.' }
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = $Exe
        $psi.Arguments = $ArgumentosFFmpeg
        $psi.WorkingDirectory = $Dir
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $proc = New-Object Diagnostics.Process
        $proc.StartInfo = $psi
        if (-not $proc.Start()) { throw 'Nao foi possivel iniciar o FFmpeg.' }
        # Drenar ambos os streams em paralelo evita deadlock nos encoders.
        $tOut = $proc.StandardOutput.ReadToEndAsync()
        $tErr = $proc.StandardError.ReadToEndAsync()
        while (-not $proc.HasExited) {
            try {
                $proc.Refresh()
                $agora = $sw.Elapsed.TotalSeconds
                $cpu = $proc.TotalProcessorTime.TotalSeconds
                $ram = $proc.WorkingSet64 / 1MB
                $ramPicoProcesso = $proc.PeakWorkingSet64 / 1MB
                $dt = $agora - $ultimoSeg
                if ($dt -gt 0) {
                    $cpuPct = [math]::Min(100.0, [math]::Max(0, (($cpu - $ultimoCpu) / $dt) * 100.0 / $NLogicos))
                    $picoCpu = [math]::Max($picoCpu, $cpuPct)
                    $picoRam = [math]::Max($picoRam, $ramPicoProcesso)
                    $somaRamPonderada += $ram * $dt
                    $somaTempoRam += $dt
                    $amostras.Add([pscustomobject][ordered]@{
                        Instante = (Get-Date).ToString('o')
                        Segundos = (Numero $agora)
                        CPU_Pct_Total = (Numero $cpuPct)
                        RAM_Residente_MB = (Numero $ram)
                    })
                    $ultimoSeg = $agora
                    $ultimoCpu = $cpu
                    $cpuFinal = $cpu
                }
            } catch { } # o processo pode encerrar entre duas leituras
            Start-Sleep -Milliseconds $IntervaloMs
        }
        $proc.WaitForExit()
        $exitCode = $proc.ExitCode
        try { $cpuFinal = $proc.TotalProcessorTime.TotalSeconds } catch { }
        try { $picoRam = [math]::Max($picoRam, $proc.PeakWorkingSet64 / 1MB) } catch { }
        [IO.File]::WriteAllText($logOut, [string]$tOut.GetAwaiter().GetResult())
        [IO.File]::WriteAllText($logErr, [string]$tErr.GetAwaiter().GetResult())
    } catch {
        $erroExecucao = $_.Exception.Message
        [IO.File]::WriteAllText($logErr, "ERRO: $erroExecucao")
    } finally {
        $sw.Stop()
        if ($null -ne $proc) { $proc.Dispose() }
    }
    if ($amostras.Count -gt 0) {
        $amostras | Export-Csv -LiteralPath $csvAmostras -NoTypeInformation -Delimiter ';' -Encoding UTF8
    }
    $seg = $sw.Elapsed.TotalSeconds
    $mediaCPU = if ($seg -gt 0 -and $amostras.Count -gt 0) {
        [math]::Min(100.0, ($cpuFinal / $seg) * 100.0 / $NLogicos)
    } else { $null }
    $mediaRAM = if ($somaTempoRam -gt 0) { $somaRamPonderada / $somaTempoRam } else { $null }
    return [pscustomobject]@{
        Inicio = $inicio.ToString('o'); ExitCode = $exitCode; Erro = $erroExecucao
        Segundos = $seg; CPU_Segundos = $cpuFinal
        CPU_Media = $mediaCPU; CPU_Pico = $picoCpu
        RAM_Media = $mediaRAM; RAM_Pico = $picoRam
        Amostras = $amostras.Count
    }
}

function Valor-OuVazio($v) {
    if ($null -eq $v) { return '' }
    return Numero ([double]$v)
}

if (-not (Test-Path -LiteralPath $RaizTCC -PathType Container)) {
    throw "Pasta raiz nao encontrada: $RaizTCC"
}
if ($FFmpeg -notmatch '[\\/]') {
    $cmd = Get-Command $FFmpeg -ErrorAction SilentlyContinue
    if ($null -eq $cmd) { throw "ffmpeg.exe nao localizado no PATH. Defina `$FFmpeg com caminho absoluto." }
    $FFmpeg = $cmd.Source
}
if (-not (Test-Path -LiteralPath $FFmpeg -PathType Leaf)) { throw "FFmpeg nao encontrado: $FFmpeg" }
foreach ($dir in @($PastaResultado, $PastaTemporaria, $PastaLogs, $PastaAmostras)) { Novo-Diretorio $dir }

$Concluidos = @{}
if ($PularConcluidos -and (Test-Path -LiteralPath $CSVResumo)) {
    foreach ($r in @(Import-Csv -LiteralPath $CSVResumo -Delimiter ';')) {
        if ($r.Status -eq 'OK') { $Concluidos[($r.Video + '|' + $r.Codec + '|' + $r.Bitrate_Alvo_Mbps)] = $true }
    }
}

Write-Host "RAIZ: $RaizTCC"
Write-Host "FFmpeg: $FFmpeg"
Write-Host "CPUs logicas: $NLogicos | Amostragem: $IntervaloMs ms"
Write-Host "Codecs: $($Codecs -join ', ') | Bitrates: $($BitratesMbps -join ', ') Mbps"
Write-Host "RESULTADOS: $PastaResultado"
Write-Host 'Parametros reproduzidos do Codificador.ps1 original; nova codificacao isolada.'

foreach ($v in $Videos) {
    $nome = [string]$v.Nome
    $fps = [int]$v.FPS
    $frames = [int][math]::Round($fps * [double]$v.Segundos)
    $ref = Join-Path (Join-Path $RaizTCC $nome) ($nome + '_1280x720.yuv')
    if (-not (Test-Path -LiteralPath $ref -PathType Leaf)) {
        Write-Warning "PULADO $nome : referencia ausente: $ref"
        continue
    }
    $tamanhoEsperado = [int64]$frames * [int64]$Largura * [int64]$Altura * 3 / 2
    $tamanhoReal = (Get-Item -LiteralPath $ref).Length
    if ($tamanhoReal -ne $tamanhoEsperado) {
        Write-Warning "PULADO $nome : referencia tem $tamanhoReal bytes; esperados $tamanhoEsperado (YUV420p 8-bit, $frames frames)."
        continue
    }

    Write-Host "`n======== $nome | $fps FPS | $frames quadros ========" -ForegroundColor Cyan
    foreach ($codec in $Codecs) {
        foreach ($br in $BitratesMbps) {
            $chave = "$nome|$codec|$br"
            if ($PularConcluidos -and $Concluidos.ContainsKey($chave)) {
                Write-Host "PULANDO ja concluido: $chave"
                continue
            }
            $id = "${nome}_${codec}_${br}M"
            $dir = Join-Path $PastaTemporaria $id
            Novo-Diretorio $dir
            $videoSaida = Join-Path $dir 'video_teste.mp4'
            if (Test-Path -LiteralPath $videoSaida) { Remove-Item -LiteralPath $videoSaida -Force }
            $logPasses = Join-Path $dir 'estatisticas'
            # Input YUV raw: informamos formato, dimensao e FPS explicitamente.
            $base = '-hide_banner -nostdin -loglevel error -nostats -y ' +
                '-f rawvideo -pixel_format yuv420p -video_size ' + "${Largura}x${Altura}" +
                ' -framerate ' + $fps + ' -i ' + (Q $ref) +
                ' -frames:v ' + $frames
            $alvo = "${br}M"
            # Reproduz os mesmos parametros de encoder, GOP e container
            # do Codificador.ps1 enviado pelo usuario.
            switch ($codec) {
                'H264' {
                    $comum = ' -c:v libx264 -preset ' + $PresetH264 +
                        ' -b:v ' + $alvo + ' -g ' + $fps +
                        ' -keyint_min ' + $fps + ' -sc_threshold 0 -pix_fmt yuv420p'
                    $p1 = $base + $comum + ' -pass 1 -passlogfile ' + (Q $logPasses) +
                        ' -an -f null NUL'
                    $p2 = $base + $comum + ' -pass 2 -passlogfile ' + (Q $logPasses) +
                        ' -an -movflags +faststart ' + (Q $videoSaida)
                }
                'H265' {
                    $comum = ' -c:v libx265 -preset ' + $PresetH265 +
                        ' -profile:v main -b:v ' + $alvo + ' -g ' + $fps + ' -pix_fmt yuv420p'
                    # Stats relativo a pasta temporaria exclusiva para este teste.
                    $p1 = $base + $comum + ' -x265-params pass=1:stats=x265_stats' +
                        ' -an -f null NUL'
                    $p2 = $base + $comum + ' -x265-params pass=2:stats=x265_stats' +
                        ' -tag:v hvc1 -an -movflags +faststart ' + (Q $videoSaida)
                }
                'AV1' {
                    $comum = ' -c:v libaom-av1 -cpu-used ' + $CpuUsedAV1 +
                        ' -profile:v 0 -b:v ' + $alvo + ' -g ' + $fps + ' -pix_fmt yuv420p'
                    $p1 = $base + $comum + ' -pass 1 -passlogfile ' + (Q $logPasses) +
                        ' -an -f null NUL'
                    $p2 = $base + $comum + ' -pass 2 -passlogfile ' + (Q $logPasses) +
                        ' -tag:v av01 -an -movflags +faststart ' + (Q $videoSaida)
                }
                default { throw "Codec desconhecido: $codec" }
            }

            Write-Host "`n>>> $id : primeira passagem"
            $m1 = Medir-Processo -Exe $FFmpeg -ArgumentosFFmpeg $p1 -Dir $dir -Id $id -Fase 'pass1'
            $m2 = $null
            if ($m1.ExitCode -eq 0 -and -not $m1.Erro) {
                Write-Host ">>> $id : segunda passagem"
                $m2 = Medir-Processo -Exe $FFmpeg -ArgumentosFFmpeg $p2 -Dir $dir -Id $id -Fase 'pass2'
            }
            $arquivoOK = ($null -ne $m2 -and (Test-Path -LiteralPath $videoSaida -PathType Leaf))
            $bytes = if ($arquivoOK) { (Get-Item -LiteralPath $videoSaida).Length } else { 0 }
            $status = if ($arquivoOK -and $bytes -gt 0 -and $m1.ExitCode -eq 0 -and $m2.ExitCode -eq 0 -and -not $m2.Erro) { 'OK' } else { 'FALHA' }

            foreach ($par in @(@('Pass1', $m1), @('Pass2', $m2))) {
                $m = $par[1]
                if ($null -eq $m) { continue }
                Gravar-CsvLinha $CSVPassagens ([pscustomobject][ordered]@{
                    Video=$nome; Codec=$codec; Bitrate_Alvo_Mbps=$br; Passagem=$par[0]
                    Status= $(if ($m.ExitCode -eq 0 -and -not $m.Erro) {'OK'} else {'FALHA'})
                    ExitCode=$m.ExitCode; Inicio=$m.Inicio; Tempo_Segundos=(Numero $m.Segundos)
                    CPU_Media_Pct_Total=(Valor-OuVazio $m.CPU_Media)
                    CPU_Pico_Pct_Total=(Valor-OuVazio $m.CPU_Pico)
                    RAM_Media_MB=(Valor-OuVazio $m.RAM_Media)
                    RAM_Pico_MB=(Valor-OuVazio $m.RAM_Pico)
                    Amostras=$m.Amostras; Erro=$m.Erro
                })
            }
            $tempoTotal = $m1.Segundos
            $cpuSegTotal = $m1.CPU_Segundos
            $ramSomado = 0.0
            $ramTempo = 0.0
            if ($null -ne $m1.RAM_Media) { $ramSomado += ($m1.RAM_Media * $m1.Segundos); $ramTempo += $m1.Segundos }
            $picoRAM = $m1.RAM_Pico
            $picoCPU = $m1.CPU_Pico
            if ($null -ne $m2) {
                $tempoTotal += $m2.Segundos
                $cpuSegTotal += $m2.CPU_Segundos
                if ($null -ne $m2.RAM_Media) { $ramSomado += ($m2.RAM_Media * $m2.Segundos); $ramTempo += $m2.Segundos }
                $picoRAM = [math]::Max($picoRAM, $m2.RAM_Pico)
                $picoCPU = [math]::Max($picoCPU, $m2.CPU_Pico)
            }
            $cpuMediaTotal = if ($tempoTotal -gt 0) { 100.0 * $cpuSegTotal / ($tempoTotal * $NLogicos) } else { $null }
            $ramMediaTotal = if ($ramTempo -gt 0) { $ramSomado / $ramTempo } else { $null }
            $bitrateReal = if ($status -eq 'OK') { $bytes * 8.0 / ($frames / [double]$fps) / 1e6 } else { $null }
            $linha = [pscustomobject][ordered]@{
                Video=$nome; Codec=$codec; FPS=$fps; Quadros=$frames; Bitrate_Alvo_Mbps=$br
                Status=$status; Inicio=$m1.Inicio
                Tempo_Pass1_Segundos=(Numero $m1.Segundos)
                Tempo_Pass2_Segundos=$(if ($null -ne $m2) { Numero $m2.Segundos } else { '' })
                Tempo_Total_Segundos=(Numero $tempoTotal)
                CPU_Media_Pct_Total=(Valor-OuVazio $cpuMediaTotal)
                CPU_Pico_Pct_Total=(Numero $picoCPU)
                RAM_Media_MB=(Valor-OuVazio $ramMediaTotal)
                RAM_Pico_MB=(Numero $picoRAM)
                Bitrate_Real_Teste_Mbps=(Valor-OuVazio $bitrateReal)
                Bytes_Teste=$bytes
                ExitCode_Pass1=$m1.ExitCode
                ExitCode_Pass2=$(if ($null -ne $m2) {$m2.ExitCode} else {''})
                Preset_Config=$(switch($codec){'H264'{$PresetH264};'H265'{$PresetH265};'AV1'{"cpu-used=$CpuUsedAV1"}})
                Erro=($m1.Erro + $(if ($null -ne $m2) { $m2.Erro } else { '' }))
            }
            Gravar-CsvLinha $CSVResumo $linha
            if ($status -eq 'OK') {
                $Concluidos[$chave] = $true
                Write-Host ("OK $id | {0:N2}s | CPU {1:N2}% | RAM pico {2:N2} MB" -f $tempoTotal, $cpuMediaTotal, $picoRAM) -ForegroundColor Green
            } else {
                Write-Warning "FALHA: $id (pass1 exit=$($m1.ExitCode), erro=$($m1.Erro)). Verifique logs: $PastaLogs"
            }
            $limpar = (($status -eq 'OK' -and $ApagarArquivosTemporariosAposSucesso) -or
                       ($status -ne 'OK' -and $ApagarArquivosTemporariosAposFalha))
            if ($limpar -and (Test-Path -LiteralPath $dir)) {
                # Exclui SOMENTE pasta temporaria criada por este experimento.
                Remove-Item -LiteralPath $dir -Recurse -Force
            }
        }
    }
}
Write-Host "`nCONCLUIDO. Resumo: $CSVResumo" -ForegroundColor Cyan
Write-Host "Passagens: $CSVPassagens"
Write-Host "Amostras: $PastaAmostras"