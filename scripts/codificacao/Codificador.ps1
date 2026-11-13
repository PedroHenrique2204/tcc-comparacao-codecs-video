
# ============================================================
# EXPERIMENTO COMPARATIVO DE CODECS - HD
# Codecs: H.264 / AVC, H.265 / HEVC e AV1
# Entrada: YUV 3840x2160, 8-bit, 4:2:0
# Saida: 1280x720, yuv420p, MP4
# Codificacao: 2 passes por bitrate
# Processa UM VIDEO por execucao
# ============================================================

$ErrorActionPreference = "Continue"

# ------------------------------------------------------------
# 1. CONFIGURACOES GERAIS
# ------------------------------------------------------------

$BaseFolder = $PSScriptRoot

# ESCOLHA AQUI O VIDEO QUE SERA PROCESSADO
$Video = "Beauty"

$InputWidth   = 3840
$InputHeight  = 2160
$OutputWidth  = 1280
$OutputHeight = 720

# Configuracoes individuais de cada sequencia
$VideoConfigs = @{
    Beauty     = @{ FPS = 120; MaxSeconds = 5 }
    Bosphorus  = @{ FPS = 120; MaxSeconds = 5 }
    HoneyBee   = @{ FPS = 120; MaxSeconds = 5 }
    Jockey     = @{ FPS = 120; MaxSeconds = 5 }
    ReadySetGo = @{ FPS = 120; MaxSeconds = 5 }
    ShakeNDry  = @{ FPS = 120; MaxSeconds = 2.5 }
    FlowerPan  = @{ FPS = 50;  MaxSeconds = 12 }
    FlowerKids = @{ FPS = 50;  MaxSeconds = 12 }
    Lips       = @{ FPS = 120; MaxSeconds = 5 }
    RaceNight  = @{ FPS = 50;  MaxSeconds = 12 }
    RiverBank  = @{ FPS = 50;  MaxSeconds = 12 }
    SunBath    = @{ FPS = 50;  MaxSeconds = 6 }
}

# Bitrates de teste em Mbps
$Bitrates = @(1, 3, 5, 7, 10, 15, 50)

# Configuracoes dos encoders
$H264Preset = "medium"
$H265Preset = "medium"
$AV1CpuUsed = 6

$CodecFolders = @{
    H264 = "H264_Bitrates_HD"
    H265 = "H265_Bitrates_HD"
    AV1  = "AV1_Bitrates_HD"
}

# ------------------------------------------------------------
# 2. VALIDAR VIDEO ESCOLHIDO
# ------------------------------------------------------------

if (-not $VideoConfigs.ContainsKey($Video)) {
    throw "Video '$Video' nao cadastrado. Confira a variavel `$Video."
}

$FPS = [int]$VideoConfigs[$Video].FPS
$MaxSeconds = [double]$VideoConfigs[$Video].MaxSeconds
$GOP = $FPS

$InputFile = Join-Path $BaseFolder "${Video}_3840x2160.yuv"
$HDInputFile = Join-Path $BaseFolder "${Video}_1280x720.yuv"
$PreparationLog = Join-Path $BaseFolder "${Video}_preparacao_HD.log"

$ConsolidatedCsv = Join-Path $BaseFolder "resultados_codificacao_hd.csv"

Write-Host ""
Write-Host "=================================================="
Write-Host "VIDEO SELECIONADO: $Video"
Write-Host "FPS: $FPS | Duracao maxima: $MaxSeconds s"
Write-Host "GOP: $GOP"
Write-Host "=================================================="

# ------------------------------------------------------------
# 3. VERIFICAR PROGRAMAS
# ------------------------------------------------------------

if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    throw "ERRO: ffmpeg nao foi encontrado no PATH."
}

if (-not (Get-Command ffprobe -ErrorAction SilentlyContinue)) {
    throw "ERRO: ffprobe nao foi encontrado no PATH."
}

$EncoderList = (& ffmpeg -hide_banner -encoders 2>&1 | Out-String)

if ($LASTEXITCODE -ne 0) {
    throw "ERRO ao consultar os encoders do FFmpeg."
}

foreach ($Encoder in @("libx264", "libx265", "libaom-av1")) {
    if ($EncoderList -notmatch [regex]::Escape($Encoder)) {
        throw "ERRO: encoder $Encoder nao esta disponivel."
    }
}

if (-not (Test-Path -LiteralPath $InputFile)) {
    throw "Arquivo original nao encontrado: $InputFile"
}

# ------------------------------------------------------------
# 4. CALCULAR QUANTIDADE DE FRAMES
# ------------------------------------------------------------

# YUV420P de 8 bits ocupa 1,5 byte por pixel.
$BytesPerInputFrame = [int64]($InputWidth * $InputHeight * 3 / 2)
$BytesPerHDFrame = [int64]($OutputWidth * $OutputHeight * 3 / 2)

$InputInfo = Get-Item -LiteralPath $InputFile

if (($InputInfo.Length % $BytesPerInputFrame) -ne 0) {
    throw "Tamanho do YUV original invalido: $InputFile"
}

$AvailableFrames = [int64]($InputInfo.Length / $BytesPerInputFrame)
$MaxFrames = [int64][math]::Floor($MaxSeconds * $FPS)
$Frames = [int][math]::Min($AvailableFrames, $MaxFrames)

if ($Frames -le 0) {
    throw "Nenhum quadro valido encontrado para $Video."
}

$ExpectedDuration = [math]::Round($Frames / $FPS, 3)
$ExpectedHDBytes = [int64]($BytesPerHDFrame * $Frames)

Write-Host "Frames disponiveis: $AvailableFrames"
Write-Host "Frames utilizados: $Frames"
Write-Host "Duracao utilizada: $ExpectedDuration segundos"

# ------------------------------------------------------------
# 5. GERAR OU VALIDAR A REFERENCIA HD
# ------------------------------------------------------------

$CreateHD = $true

if (Test-Path -LiteralPath $HDInputFile) {
    $HDInfo = Get-Item -LiteralPath $HDInputFile

    if ($HDInfo.Length -eq $ExpectedHDBytes) {
        $CreateHD = $false
        Write-Host "Referencia HD existente e compativel."
    }
    else {
        Write-Host "Referencia HD com tamanho incorreto. Sera recriada."
    }
}

if ($CreateHD) {
    Write-Host "Gerando referencia HD para $Video..."

    $PrepOutput = & ffmpeg `
        -hide_banner `
        -y `
        -loglevel info `
        -f rawvideo `
        -pixel_format yuv420p `
        -video_size "${InputWidth}x${InputHeight}" `
        -framerate $FPS `
        -i $InputFile `
        -frames:v $Frames `
        -vf "scale=${OutputWidth}:${OutputHeight}:flags=lanczos" `
        -pix_fmt yuv420p `
        -f rawvideo `
        $HDInputFile 2>&1

    $PrepExitCode = $LASTEXITCODE
    $PrepOutput | Out-File -LiteralPath $PreparationLog -Encoding utf8

    if ($PrepExitCode -ne 0 -or -not (Test-Path -LiteralPath $HDInputFile)) {
        throw "Falha ao gerar a referencia HD. Consulte $PreparationLog"
    }

    $HDInfo = Get-Item -LiteralPath $HDInputFile

    if ($HDInfo.Length -ne $ExpectedHDBytes) {
        throw "A referencia HD tem tamanho inesperado."
    }
}

# ------------------------------------------------------------
# 6. PREPARAR PASTAS E RESULTADOS
# ------------------------------------------------------------

foreach ($CodecName in @("H264", "H265", "AV1")) {
    $Folder = Join-Path $BaseFolder $CodecFolders[$CodecName]
    $LogFolder = Join-Path $Folder "logs"

    New-Item -ItemType Directory -Force -Path $Folder, $LogFolder |
        Out-Null
}

$Results = [System.Collections.Generic.List[object]]::new()

# ------------------------------------------------------------
# 7. EXPERIMENTO PARA O VIDEO SELECIONADO
# ------------------------------------------------------------

foreach ($CodecName in @("H264", "H265", "AV1")) {

    $OutputFolder = Join-Path $BaseFolder $CodecFolders[$CodecName]
    $LogFolder = Join-Path $OutputFolder "logs"

    $CodecCsv = Join-Path $OutputFolder "resultados_$($CodecName.ToLower())_hd.csv"

    $CodecSuffix = switch ($CodecName) {
        "H264" { "h264" }
        "H265" { "h265" }
        "AV1"  { "av1" }
    }

    Write-Host ""
    Write-Host "=================================================="
    Write-Host "CODEC: $CodecName | VIDEO: $Video"
    Write-Host "=================================================="

    foreach ($Bitrate in $Bitrates) {

        $BaseName = "${Video}_${CodecName}_HD_${Bitrate}M"

        $OutputFile = Join-Path $OutputFolder "${Video}_${CodecSuffix}_HD_${Bitrate}M.mp4"
        $LogFile = Join-Path $LogFolder "${BaseName}.txt"

        # Arquivos auxiliares dos passes ficam em logs.
        $PassLog = Join-Path $LogFolder "${BaseName}_pass"
        $X265StatsRaw = Join-Path $LogFolder "${BaseName}_stats"

        # Escapar o caminho para os parametros do x265.
        $X265Stats = $X265StatsRaw.Replace("\", "/")
        $X265Stats = $X265Stats -replace '^([A-Za-z]):', '$1\:'
        $X265Stats = $X265Stats.Replace("'", "\'")

        Write-Host ""
        Write-Host "VIDEO: $Video | CODEC: $CodecName | BITRATE: $Bitrate Mbps"

        # Remover somente os arquivos auxiliares e a saida
        # correspondentes a este teste.
        if (Test-Path -LiteralPath $OutputFile) {
            Remove-Item -LiteralPath $OutputFile -Force
        }

        if (Test-Path -LiteralPath $LogFile) {
            Remove-Item -LiteralPath $LogFile -Force
        }

        Get-ChildItem -LiteralPath $LogFolder `
            -Filter "${BaseName}_pass*" `
            -ErrorAction SilentlyContinue |
            Remove-Item -Force

        Get-ChildItem -LiteralPath $LogFolder `
            -Filter "${BaseName}_stats*" `
            -ErrorAction SilentlyContinue |
            Remove-Item -Force

        $StartTime = Get-Date

        $InputArgs = @(
            "-hide_banner",
            "-y",
            "-f", "rawvideo",
            "-pixel_format", "yuv420p",
            "-video_size", "${OutputWidth}x${OutputHeight}",
            "-framerate", "$FPS",
            "-i", $HDInputFile,
            "-frames:v", "$Frames"
        )

        # ----------------------------------------------------
        # 7.1. CONFIGURAR ENCODER
        # ----------------------------------------------------

        switch ($CodecName) {

            "H264" {
                $CommonArgs = @(
                    "-c:v", "libx264",
                    "-preset", $H264Preset,
                    "-b:v", "${Bitrate}M",
                    "-g", "$GOP",
                    "-keyint_min", "$GOP",
                    "-sc_threshold", "0",
                    "-pix_fmt", "yuv420p"
                )

                $Pass1Args = @(
                    "-pass", "1",
                    "-passlogfile", $PassLog,
                    "-an",
                    "-f", "null", "NUL"
                )

                $Pass2Args = @(
                    "-pass", "2",
                    "-passlogfile", $PassLog,
                    "-an",
                    "-movflags", "+faststart",
                    $OutputFile
                )
            }

            "H265" {
                $CommonArgs = @(
                    "-c:v", "libx265",
                    "-preset", $H265Preset,
                    "-profile:v", "main",
                    "-b:v", "${Bitrate}M",
                    "-g", "$GOP",
                    "-pix_fmt", "yuv420p"
                )

                $Pass1Args = @(
                    "-x265-params", "pass=1:stats=$X265Stats",
                    "-an",
                    "-f", "null", "NUL"
                )

                $Pass2Args = @(
                    "-x265-params", "pass=2:stats=$X265Stats",
                    "-tag:v", "hvc1",
                    "-an",
                    "-movflags", "+faststart",
                    $OutputFile
                )
            }

            "AV1" {
                $CommonArgs = @(
                    "-c:v", "libaom-av1",
                    "-cpu-used", "$AV1CpuUsed",
                    "-profile:v", "0",
                    "-b:v", "${Bitrate}M",
                    "-g", "$GOP",
                    "-pix_fmt", "yuv420p"
                )

                $Pass1Args = @(
                    "-pass", "1",
                    "-passlogfile", $PassLog,
                    "-an",
                    "-f", "null", "NUL"
                )

                $Pass2Args = @(
                    "-pass", "2",
                    "-passlogfile", $PassLog,
                    "-tag:v", "av01",
                    "-an",
                    "-movflags", "+faststart",
                    $OutputFile
                )
            }
        }

        # ----------------------------------------------------
        # 7.2. PRIMEIRO PASSE
        # ----------------------------------------------------

        Write-Host "Passo 1/2 - Analise..."

        $ArgsPass1 = @($InputArgs) + @($CommonArgs) + @($Pass1Args)
        $Pass1Output = & ffmpeg @ArgsPass1 2>&1
        $Pass1ExitCode = $LASTEXITCODE

        $Pass1Output |
            Out-File -LiteralPath $LogFile -Encoding utf8

        if ($Pass1ExitCode -ne 0) {
            Write-Warning "Falha no primeiro passe: $Video / $CodecName / ${Bitrate}M"
            continue
        }

        # ----------------------------------------------------
        # 7.3. SEGUNDO PASSE
        # ----------------------------------------------------

        Write-Host "Passo 2/2 - Codificacao final..."

        $ArgsPass2 = @($InputArgs) + @($CommonArgs) + @($Pass2Args)
        $Pass2Output = & ffmpeg @ArgsPass2 2>&1
        $Pass2ExitCode = $LASTEXITCODE

        $Pass2Output |
            Out-File -LiteralPath $LogFile -Append -Encoding utf8

        if ($Pass2ExitCode -ne 0) {
            Write-Warning "Falha no segundo passe: $Video / $CodecName / ${Bitrate}M"
            continue
        }

        $ElapsedSeconds = [math]::Round(
            ((Get-Date) - $StartTime).TotalSeconds, 3
        )

        # ----------------------------------------------------
        # 7.4. VALIDAR VIDEO GERADO
        # ----------------------------------------------------

        if (-not (Test-Path -LiteralPath $OutputFile)) {
            Write-Warning "Arquivo final nao encontrado: $OutputFile"
            continue
        }

        $ProbeOutput = & ffprobe `
            -v error `
            -show_entries "format=size,duration,bit_rate:stream=codec_name,width,height,pix_fmt,avg_frame_rate,nb_frames" `
            -select_streams v:0 `
            -of json `
            $OutputFile 2>&1

        if ($LASTEXITCODE -ne 0 -or -not $ProbeOutput) {
            Write-Warning "FFprobe nao conseguiu ler: $OutputFile"
            continue
        }

        try {
            $Probe = ($ProbeOutput -join "`n") | ConvertFrom-Json
            $Stream = $Probe.streams | Select-Object -First 1
            $Format = $Probe.format
        }
        catch {
            Write-Warning "Falha ao interpretar FFprobe: $OutputFile"
            continue
        }

        if (-not $Stream -or [int64]$Format.size -le 0) {
            Write-Warning "Arquivo sem fluxo de video valido: $OutputFile"
            continue
        }

        if ($Stream.width -ne $OutputWidth -or $Stream.height -ne $OutputHeight) {
            Write-Warning "Resolucao inesperada: $OutputFile"
            continue
        }

        $ExpectedCodec = switch ($CodecName) {
            "H264" { "h264" }
            "H265" { "hevc" }
            "AV1"  { "av1" }
        }

        if ($Stream.codec_name -ne $ExpectedCodec) {
            Write-Warning "Codec inesperado: $($Stream.codec_name)"
            continue
        }

        $SizeBytes = [int64]$Format.size

        $Duration = [double]::Parse(
            [string]$Format.duration,
            [Globalization.CultureInfo]::InvariantCulture
        )

        $BitrateRealMbps = 0

        if ($Format.bit_rate) {
            $BitrateRealMbps = [math]::Round(
                ([double]$Format.bit_rate / 1000000), 3
            )
        }

        # ----------------------------------------------------
        # 7.5. REGISTRAR RESULTADO
        # ----------------------------------------------------

        $Row = [PSCustomObject]@{
            Video               = $Video
            Codec               = $CodecName
            CodecFFprobe        = $Stream.codec_name
            BitrateAlvoMbps     = $Bitrate
            BitrateRealMbps     = $BitrateRealMbps
            TempoCodificacaoSeg = $ElapsedSeconds
            TamanhoBytes        = $SizeBytes
            DuracaoSeg          = [math]::Round($Duration, 3)
            FramesEsperados     = $Frames
            FPS                 = $FPS
            Largura             = $Stream.width
            Altura              = $Stream.height
            PixelFormat         = $Stream.pix_fmt
            FPSMedio            = $Stream.avg_frame_rate
            Arquivo             = $OutputFile
            Log                 = $LogFile
        }

        $Results.Add($Row)

        # Atualiza o CSV consolidado e o CSV do codec.
        # O consolidado deste script contem somente os
        # resultados validos desta execucao.
        $Results |
            Export-Csv -LiteralPath $ConsolidatedCsv `
                -NoTypeInformation -Encoding UTF8

        $Results |
            Where-Object { $_.Codec -eq $CodecName } |
            Export-Csv -LiteralPath $CodecCsv `
                -NoTypeInformation -Encoding UTF8

        Write-Host "Concluido: $Video | $CodecName | $Bitrate Mbps"
        Write-Host "Duracao: $Duration s"
        Write-Host "Tamanho: $SizeBytes bytes"
        Write-Host "Bitrate real: $BitrateRealMbps Mbps"
        Write-Host "Arquivo: $OutputFile"
        Write-Host "Log: $LogFile"
    }
}

# ------------------------------------------------------------
# 8. RESUMO FINAL
# ------------------------------------------------------------

Write-Host ""
Write-Host "=================================================="
Write-Host " EXPERIMENTO FINALIZADO"
Write-Host "=================================================="
Write-Host "Video processado: $Video"
Write-Host "Resultados validos: $($Results.Count)"
Write-Host "CSV consolidado: $ConsolidatedCsv"
Write-Host ""

if ($Results.Count -gt 0) {
    $Results |
        Sort-Object Codec, BitrateAlvoMbps |
        Format-Table Video, Codec, BitrateAlvoMbps,
            BitrateRealMbps, TempoCodificacaoSeg,
            TamanhoBytes, DuracaoSeg -AutoSize
}
else {
    Write-Host "ATENCAO: nenhum resultado foi concluido com sucesso."
}

Write-Host ""
Write-Host "Os logs e arquivos auxiliares dos passes ficam dentro"
Write-Host "da pasta logs de cada codec."
Write-Host "=================================================="