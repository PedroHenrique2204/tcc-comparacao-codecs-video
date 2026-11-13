# Comparacao experimental de codecs de video em HD

Scripts PowerShell para estudo de H.264/AVC, H.265/HEVC, AV1 e JPEG XS (SVT-JPEG-XS) em 1280 x 720, com analise de bitrate, VMAF, uso de CPU, memoria RAM e tempo de processamento.

> Repositorio de **scripts**, sem os videos originais ou derivados. Os dados utilizados no estudo devem ser obtidos conforme as licencas e condicoes das respectivas fontes.

## Ambiente

- Windows e PowerShell 5.1 ou superior.
- FFmpeg com `libx264`, `libx265`, `libaom-av1` e `libvmaf` no PATH.
- Para JPEG XS, binarios `SvtJpegxsEncApp.exe` e `SvtJpegxsDecApp.exe` compilados do projeto SVT-JPEG-XS.
- Referencias HD YUV420p 8-bit de 1280 x 720 por sequencia.

## Scripts

| Script | Funcao |
| --- | --- |
| `scripts/codificacao/Codificador.ps1` | Codificacao original com H.264, H.265 e AV1, uma sequencia por vez, ABR em duas passagens. |
| `scripts/codificacao/Experimento_JPEGXS_HD_CPU_RAM_Automatico.ps1` | Codificacao/decodificacao JPEG XS, VMAF, CPU/RAM e logs, uma sequencia por vez. Preserva os arquivos decodificados. |
| `scripts/monitoramento/Medir_CPU_RAM_Tempo_Parametros_Originais_CORRIGIDO.ps1` | Recodificacao automatica de 12 sequencias com os parametros dos codecs tradicionais e coleta CPU/RAM/tempo. |
| `scripts/monitoramento/Medir_JPEGXS_Lossless_HoneyBee.ps1` | Teste adicional do HoneyBee em modo JPEG XS lossless com telemetria. |
| `scripts/analise/Consolidar_Tempos_JPEGXS.ps1` | Consolida tempos ja registrados nos CSVs de JPEG XS; nao recodifica. |

## Estrutura esperada dos dados locais

Cada pasta de sequencia, como `Beauty`, `Bosphorus`, `HoneyBee`, `Jockey`, `ReadySetGo`, `ShakeNDry`, `FlowerKids`, `FlowerPan`, `Lips`, `RaceNight`, `RiverBank` e `SunBath`, deve conter a referencia `NomeDoVideo_1280x720.yuv`. Para os procedimentos que partem do 4K, o arquivo de entrada e `NomeDoVideo_3840x2160.yuv`.

As pastas de dados nao acompanham este repositorio.

## Como executar

1. Abra o script desejado e **ajuste os caminhos locais** nas variaveis iniciais (`$RaizTCC`, `$PastaSVT`, `$Base`, `$Encoder` ou `$Video`, conforme o script).
2. Confirme que o FFmpeg esta disponivel (`ffmpeg -version`) e, para JPEG XS, que os executaveis SVT-JPEG-XS estao no caminho indicado.
3. Execute o script num terminal PowerShell. Exemplo:

   ```powershell
   .\scripts\monitoramento\Medir_CPU_RAM_Tempo_Parametros_Originais_CORRIGIDO.ps1
   ```

4. Execute inicialmente uma unica combinacao de video, codec e bitrate para validar o ambiente.

**Atencao:** `Codificador.ps1` usa `$PSScriptRoot` como pasta de trabalho: ao executa-lo, mantenha o arquivo ao lado dos dados do video desejado ou adapte `$BaseFolder` para a pasta correta. Os scripts de monitoramento fazem novas codificacoes para medir os recursos; arquivos finais e logs sao gravados em pastas locais especificas.

## Parametros do experimento

- H.264: `libx264`, preset `medium`.
- H.265: `libx265`, preset `medium`.
- AV1: `libaom-av1`, `cpu-used 6`.
- Codecs tradicionais: ABR de duas passagens; bitrates alvo de 1, 3, 5, 7, 10, 15 e 50 Mbps; GOP definido a partir do FPS.
- JPEG XS: YUV420 8-bit, perfil `main420`, controle de taxa em `--bpp`; testes adicionais `--lossless 1`.
- Limite de 600 quadros por sequencia, respeitando duracoes menores.

**Nota metodologica:** taxas *reais* podem diferir das taxas-alvo. Os valores de BPP e as faixas testadas no JPEG XS sao escolhas empiricas dos experimentos, nao requisitos oficiais do codec. Comparacoes de tempo devem separar codificacao, decodificacao e calculo do VMAF, bem como considerar as duas passagens dos codecs tradicionais.

## Privacidade e dados

O `.gitignore` exclui arquivos de video, imagens, bitstreams, CSVs, logs, JSONs e dados experimentais produzidos localmente. Revise `git status` antes de publicar. Os caminhos de instalacao nos scripts sao exemplos de ambiente Windows e devem ser ajustados em outra maquina.