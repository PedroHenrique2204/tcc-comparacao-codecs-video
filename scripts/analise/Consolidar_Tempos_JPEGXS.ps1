# ============================================================
# CONSOLIDAR TEMPOS DO JPEG XS - TODOS OS 12 VIDEOS
# Le exclusivamente os CSVs existentes; nao codifica nem apaga nada.
# Compativel com Windows PowerShell 5.1 e PowerShell 7.
# Execute na pasta TCC2, ou ajuste $RaizTCC abaixo.
# ============================================================

$ErrorActionPreference = 'Stop'
$RaizTCC = 'C:\Users\pedro\Desktop\TCC2'
$Saida = Join-Path $RaizTCC 'tempos_processamento_JPEGXS_todos_videos.csv'

$Videos = @(
    'Beauty', 'Bosphorus', 'HoneyBee', 'Jockey',
    'ReadySetGo', 'ShakeNDry', 'FlowerKids', 'FlowerPan',
    'Lips', 'RaceNight', 'RiverBank', 'SunBath'
)

# Aceita numeros com ponto ou virgula, independentemente da localidade do Windows.
function Ler-Numero {
    param($Valor)
    if ($null -eq $Valor) { return $null }
    $Texto = ([string]$Valor).Trim()
    if ([string]::IsNullOrWhiteSpace($Texto)) { return $null }
    $Numero = 0.0
    $Cultura = [System.Globalization.CultureInfo]::InvariantCulture
    $Texto = $Texto.Replace(',', '.')
    if ([double]::TryParse($Texto, [System.Globalization.NumberStyles]::Float, $Cultura, [ref]$Numero)) {
        return $Numero
    }
    return $null
}

# Excel em pt-BR: separador ; e virgula decimal.
function Formatar-Numero {
    param($Valor, [int]$Casas = 3)
    if ($null -eq $Valor) { return '' }
    $Cultura = [System.Globalization.CultureInfo]::GetCultureInfo('pt-BR')
    return ([double]$Valor).ToString('F' + $Casas, $Cultura)
}

if (-not (Test-Path -LiteralPath $RaizTCC -PathType Container)) {
    throw "Pasta raiz nao encontrada: $RaizTCC"
}

$Linhas = New-Object 'System.Collections.Generic.List[object]'
$Faltando = New-Object 'System.Collections.Generic.List[string]'

foreach ($Video in $Videos) {
    $Arquivo = Join-Path (Join-Path $RaizTCC $Video) "JPEGXS\resultados_jpegxs_${Video}_hd_cpu_ram.csv"
    if (-not (Test-Path -LiteralPath $Arquivo -PathType Leaf)) {
        Write-Warning "CSV nao encontrado para ${Video}: $Arquivo"
        $Faltando.Add($Video)
        continue
    }

    try {
        $Dados = @(Import-Csv -LiteralPath $Arquivo -Delimiter ',')
    } catch {
        Write-Warning "Falha ao ler CSV de ${Video}: $($_.Exception.Message)"
        $Faltando.Add($Video)
        continue
    }
    if ($Dados.Count -eq 0) {
        Write-Warning "CSV vazio para $Video"
        $Faltando.Add($Video)
        continue
    }

    $Colunas = @($Dados[0].PSObject.Properties.Name)
    foreach ($Obrigatoria in @('Bitrate_Alvo_Mbps', 'Tempo_Codificacao_Segundos', 'Tempo_Decodificacao_Segundos')) {
        if ($Colunas -notcontains $Obrigatoria) {
            throw "O arquivo $Arquivo nao contem a coluna '$Obrigatoria'. Confira a versao do CSV."
        }
    }

    foreach ($Item in ($Dados | Sort-Object { Ler-Numero $_.Bitrate_Alvo_Mbps })) {
        $TempoEnc = Ler-Numero $Item.Tempo_Codificacao_Segundos
        $TempoDec = Ler-Numero $Item.Tempo_Decodificacao_Segundos
        $TempoVmaf = Ler-Numero $Item.Tempo_VMAF_Segundos
        $SomaCodDec = if ($null -ne $TempoEnc -and $null -ne $TempoDec) { $TempoEnc + $TempoDec } else { $null }
        $SomaPipeline = if ($null -ne $SomaCodDec -and $null -ne $TempoVmaf) { $SomaCodDec + $TempoVmaf } else { $null }
        $Linhas.Add([pscustomobject][ordered]@{
            Video = $Video
            FPS = $Item.FPS
            Frames = $Item.Frames
            Bitrate_Alvo_Mbps = $Item.Bitrate_Alvo_Mbps
            Bitrate_Real_Mbps = $Item.Bitrate_Real_Mbps
            Status = $Item.Status
            Tempo_Codificacao_Segundos = Formatar-Numero $TempoEnc
            Tempo_Decodificacao_Segundos = Formatar-Numero $TempoDec
            Tempo_VMAF_Segundos = Formatar-Numero $TempoVmaf
            Tempo_Codificacao_Mais_Decodificacao_Segundos = Formatar-Numero $SomaCodDec
            Tempo_Pipeline_Incluindo_VMAF_Segundos = Formatar-Numero $SomaPipeline
        })
    }
    Write-Host "OK: $Video - $($Dados.Count) registros" -ForegroundColor Green
}

if ($Linhas.Count -eq 0) {
    throw 'Nenhum resultado encontrado. Nenhum CSV consolidado foi criado.'
}

$Linhas | Export-Csv -LiteralPath $Saida -NoTypeInformation -Delimiter ';' -Encoding UTF8
Write-Host "`nCONCLUIDO: $($Linhas.Count) registros reunidos." -ForegroundColor Cyan
Write-Host "Arquivo gerado: $Saida" -ForegroundColor Cyan
if ($Faltando.Count -gt 0) {
    Write-Warning "Videos sem CSV valido: $($Faltando -join ', ')"
}
Write-Host 'Tempos vazios indicam dados ausentes; nao foram considerados zero.'