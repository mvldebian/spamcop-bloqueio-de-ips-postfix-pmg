#!/bin/bash
#
# bloqueio_ips_postfix.sh
# - Pergunta o TLD via dialog
# - Varre o log padrão do Postfix
# - Ignora IPv6 (processa apenas IPv4)
# - Mostra cada IP sendo inserido (VERDE = novo, VERMELHO = já existia)
# - Sempre grava em /scripts/ips_coletados_postfix.txt (append)
# - Pergunta se deseja aplicar os IPs no bloqueio do Postfix
# - Se sim: reescreve /etc/postfix/local_ipblacklist e roda 5 comandos
#

set -uo pipefail

# ========================== CONFIGURAÇÕES ==========================
LOG_PADRAO="/var/log/mail.log"
ARQ_SAIDA="/scripts/ips_coletados_postfix.txt"
ARQ_BLACKLIST="/etc/postfix/local_ipblacklist"
TITULO="PMG - Bloqueio de IPs Postfix"
MOSTRAR_LINHAS=15
DELAY=0.40

# Mensagem anexada após cada IP no arquivo de bloqueio
MOTIVO="REJECT Rejeitado por envio abusivo - Delist em abuse@spamcop.com.br"

# -------- COMANDOS EXECUTADOS APÓS APLICAR O BLOQUEIO --------
# Personalize conforme sua necessidade. Serão rodados em ordem.
CMD_1='postmap /etc/postfix/local_ipblacklist'
CMD_2='sleep 10'
CMD_3='systemctl reload postfix'
CMD_4='pmgconfig sync --restart 1'
CMD_5='systemctl restart pmg-smtp-filter'
# ------------------------------------------------------------
# ===================================================================

# Dependências
for bin in dialog grep sed sort; do
    command -v "$bin" >/dev/null 2>&1 || {
        echo "Erro: '$bin' não está instalado." >&2
        exit 1
    }
done

mkdir -p "$(dirname "$ARQ_SAIDA")"
touch "$ARQ_SAIDA"

# Fallback de log
if [[ ! -r "$LOG_PADRAO" ]]; then
    for alt in /var/log/mail.log /var/log/maillog /var/log/postfix.log; do
        [[ -r "$alt" ]] && { LOG_PADRAO="$alt"; break; }
    done
fi

if [[ ! -r "$LOG_PADRAO" ]]; then
    dialog --title "$TITULO" --msgbox \
        "Não foi possível ler o log do Postfix.\n\nCaminhos testados:\n/var/log/mail.log\n/var/log/maillog\n/var/log/postfix.log\n\nTalvez precise rodar como root." 14 60
    clear
    exit 1
fi

# ------------------------- 1) PERGUNTA O TLD -------------------------
TLD=$(dialog --title "$TITULO" \
             --inputbox "Qual TLD deseja buscar no log do Postfix?\n\nExemplos:\n  cf\n  envios.cf\n  com.br\n  ru" \
             14 60 "" \
             3>&1 1>&2 2>&3)
RC=$?

if [[ $RC -ne 0 || -z "${TLD:-}" ]]; then
    clear
    echo "Operação cancelada."
    exit 0
fi

if [[ ! "$TLD" =~ ^[A-Za-z0-9.-]+$ ]]; then
    dialog --title "$TITULO" --msgbox "TLD inválido: '$TLD'\n\nUse apenas letras, números, ponto e hífen." 9 60
    clear
    exit 1
fi

# ------------------------- 2) PROCURA OS IPs (somente IPv4) ----------
IPV4="((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])"
REGEX="[A-Za-z0-9._-]+\.${TLD//./\\.}\[${IPV4}\]"

NOVOS=$(grep -aEo "$REGEX" "$LOG_PADRAO" 2>/dev/null \
        | grep -aEo "$IPV4" \
        | sort -u || true)

NOVOS=$(printf '%s\n' "$NOVOS" | grep -v ':' || true)

if [[ -z "$NOVOS" ]]; then
    dialog --title "$TITULO" --msgbox \
        "Nenhum IP (IPv4) encontrado para o TLD '.$TLD'\n\nLog pesquisado: $LOG_PADRAO\nArquivo de saída: $ARQ_SAIDA" 10 70
    clear
    exit 0
fi

# ------------------------- 3) INSERE E MOSTRA COM CORES --------------
ADICIONADOS=0
EXISTENTES=0
IGNORADOS=0
DISPLAY_ARR=()

while IFS= read -r ip <&3; do
    [[ -z "$ip" ]] && continue

    if ! [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        IGNORADOS=$((IGNORADOS + 1))
        continue
    fi

    if grep -qxF "$ip" "$ARQ_SAIDA"; then
        NOVA_LINHA="\\Z1[EXISTE]\\Zn  $ip"
        EXISTENTES=$((EXISTENTES + 1))
    else
        echo "$ip" >> "$ARQ_SAIDA"
        NOVA_LINHA="\\Z2[NOVO]\\Zn     $ip"
        ADICIONADOS=$((ADICIONADOS + 1))
    fi

    DISPLAY_ARR+=("$NOVA_LINHA")
    if (( ${#DISPLAY_ARR[@]} > MOSTRAR_LINHAS )); then
        DISPLAY_ARR=("${DISPLAY_ARR[@]: -MOSTRAR_LINHAS}")
    fi

    TEXTO=$(printf '%b\n' "${DISPLAY_ARR[@]}")

    dialog --colors \
           --title "$TITULO" \
           --infobox "\
TLD pesquisado : .$TLD
Log analisado  : $LOG_PADRAO
Arquivo saida  : $ARQ_SAIDA

$TEXTO

\\Z2Novos: $ADICIONADOS\\Zn   \\Z1Já existiam: $EXISTENTES\\Zn   Ignorados (IPv6): $IGNORADOS" \
           24 78

    sleep "$DELAY"
done 3<<< "$NOVOS"

TOTAL=$(wc -l < "$ARQ_SAIDA" | tr -d ' ')

# ------------------------- 4) RESUMO FINAL ---------------------------
dialog --colors --title "$TITULO" --msgbox "\
Varredura concluída!

TLD pesquisado        : .$TLD
Log analisado         : $LOG_PADRAO
Arquivo de saída      : $ARQ_SAIDA

\\Z2IPs novos adicionados : $ADICIONADOS\\Zn
\\Z1IPs já existentes    : $EXISTENTES\\Zn
IPv6 ignorados           : $IGNORADOS
Total de IPs no arquivo  : $TOTAL" 17 70

# ------------------------- 5) APLICAR NO BLOQUEIO DO POSTFIX ---------
dialog --title "$TITULO" --yesno "\
Deseja aplicar os $TOTAL IPs coletados no bloqueio do Postfix?

Arquivo que será reescrito:
$ARQ_BLACKLIST

Todos os IPs serão gravados seguidos de:
$MOTIVO

O conteúdo atual do arquivo será EXCLUÍDO antes da nova gravação.

Ao final, os seguintes comandos serão executados:
  1) $CMD_1
  2) $CMD_2
  3) $CMD_3
  4) $CMD_4
  5) $CMD_5" 23 80
APLICAR=$?

if [[ $APLICAR -ne 0 ]]; then
    clear
    echo "Operação finalizada (bloqueio do Postfix NÃO foi alterado)."
    exit 0
fi

# Verificações básicas
if [[ ! -d "$(dirname "$ARQ_BLACKLIST")" ]]; then
    dialog --title "$TITULO" --msgbox \
        "Diretório do Postfix não encontrado:\n$(dirname "$ARQ_BLACKLIST")\n\nO Postfix está instalado?" 10 70
    clear
    exit 1
fi

if [[ ! -w "$(dirname "$ARQ_BLACKLIST")" ]]; then
    dialog --title "$TITULO" --msgbox \
        "Sem permissão de escrita em:\n$(dirname "$ARQ_BLACKLIST")\n\nExecute o script como root (sudo)." 10 70
    clear
    exit 1
fi

# Exclui e recria o arquivo com IP + motivo
rm -f "$ARQ_BLACKLIST"
touch "$ARQ_BLACKLIST"

while IFS= read -r ip; do
    [[ -z "$ip" ]] && continue
    printf '%s %s\n' "$ip" "$MOTIVO" >> "$ARQ_BLACKLIST"
done < "$ARQ_SAIDA"

LINHAS_BLACKLIST=$(wc -l < "$ARQ_BLACKLIST" | tr -d ' ')

# ------------------------- 6) RODA OS 5 COMANDOS ---------------------
executar_cmd() {
    local cmd="$1"
    local saida
    saida=$(eval "$cmd" 2>&1)
    local st=$?
    printf '%s\n%s' "$st" "$saida"
}

# Arrays para guardar status e texto de cada comando
declare -a CMDS=("$CMD_1" "$CMD_2" "$CMD_3" "$CMD_4" "$CMD_5")
declare -a STATUS
declare -a TXT

for i in "${!CMDS[@]}"; do
    n=$((i + 1))
    total=${#CMDS[@]}
    dialog --title "$TITULO" --infobox "\
Gravando bloqueio... OK ($LINHAS_BLACKLIST linhas)

Executando comando $n/$total:
${CMDS[$i]}

Aguarde..." 12 74

    SAIDA=$(executar_cmd "${CMDS[$i]}")
    STATUS[$i]=$(printf '%s\n' "$SAIDA" | head -n1)
    TXT[$i]=$(printf '%s\n' "$SAIDA" | tail -n +2 | head -n 6)
done

# ------------------------- 7) CONFIRMAÇÃO FINAL ----------------------
marcar() {
    if [[ "$1" -eq 0 ]]; then
        printf '\\Z2[OK]\\Zn'
    else
        printf '\\Z1[FALHOU (status=%s)]\\Zn' "$1"
    fi
}

CORPO=""
for i in "${!CMDS[@]}"; do
    n=$((i + 1))
    M=$(marcar "${STATUS[$i]}")
    CORPO+="${n}) ${CMDS[$i]}\n   $M\n   ${TXT[$i]}\n\n"
done

dialog --colors --title "$TITULO" --msgbox "\
Bloqueio aplicado com sucesso!

Arquivo : $ARQ_BLACKLIST
Linhas  : $LINHAS_BLACKLIST

Resultado dos comandos:

${CORPO}" 30 80

clear
exit 0
