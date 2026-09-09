#!/usr/bin/env bash
# ==============================================================================
# Qwen3.8-27B FastMTP llama-server Başlatma Scripti
# ==============================================================================
set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[BİLGİ]${NC} $1"; }
log_success() { echo -e "${GREEN}[BAŞARILI]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[UYARI]${NC} $1"; }
log_error()   { echo -e "${RED}[HATA]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Yapılandırma yükleme
if [ -f "$SCRIPT_DIR/config.env" ]; then
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/config.env"
elif [ -f "$SCRIPT_DIR/config.env.example" ]; then
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/config.env.example"
fi

# Varsayılan değerler
WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
LLAMA_DIR="${LLAMA_DIR:-$WORKSPACE_DIR/llama.cpp}"
MODELS_DIR="${MODELS_DIR:-$WORKSPACE_DIR/models/qwen38}"
MODEL_FILE="${MODEL_FILE:-Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-Q8_K_P.gguf}"
DRAFT_MODEL_FILE="${DRAFT_MODEL_FILE:-Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-FastMTP-32K.gguf}"

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8081}"
CTX_SIZE="${CTX_SIZE:-262144}"
N_GPU_LAYERS="${N_GPU_LAYERS:-999}"
SPEC_TYPE="${SPEC_TYPE:-draft-mtp}"
SPEC_DRAFT_N_MAX="${SPEC_DRAFT_N_MAX:-3}"
SPEC_DRAFT_NGL="${SPEC_DRAFT_NGL:-999}"
BATCH_SIZE="${BATCH_SIZE:-2048}"
UBATCH_SIZE="${UBATCH_SIZE:-512}"
PARALLEL="${PARALLEL:-1}"
SPLIT_MODE="${SPLIT_MODE:-none}"
FLASH_ATTN="${FLASH_ATTN:-on}"
REASONING="${REASONING:-on}"

LOG_FILE="${LOG_FILE:-$WORKSPACE_DIR/qwen.log}"
PID_FILE="${PID_FILE:-$WORKSPACE_DIR/llama-server.pid}"
API_KEY_FILE="${API_KEY_FILE:-$WORKSPACE_DIR/llama-api.key}"

AUTH_ARGS=()
API_KEY_SOURCE=""

ensure_api_key() {
    local api_key=""

    if [ -f "$API_KEY_FILE" ]; then
        api_key=$(awk 'NF && $1 !~ /^#/ { print; exit }' "$API_KEY_FILE" 2>/dev/null || true)
    fi

    if [ -z "$api_key" ]; then
        mkdir -p "$(dirname "$API_KEY_FILE")"
        umask 077
        if command -v openssl &>/dev/null; then
            api_key="sk-$(openssl rand -hex 32)"
        else
            api_key="sk-$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')"
        fi
        printf '%s\n' "$api_key" > "$API_KEY_FILE"
        chmod 600 "$API_KEY_FILE"
        API_KEY_SOURCE="otomatik üretildi"
    else
        chmod 600 "$API_KEY_FILE" 2>/dev/null || true
        API_KEY_SOURCE="mevcut key dosyasından yüklendi"
    fi

    AUTH_ARGS=(--api-key-file "$API_KEY_FILE")
}

read_api_key() {
    awk 'NF && $1 !~ /^#/ { print; exit }' "$API_KEY_FILE" 2>/dev/null || true
}

DAEMON_MODE=false

usage() {
    echo -e "${CYAN}Kullanım:${NC} $0 [seçenekler]"
    echo ""
    echo "Seçenekler:"
    echo "  -d, --daemon, -b, --background   Sunucuyu arka planda çalıştırır ve logları $LOG_FILE dosyasına yazar"
    echo "  -f, --foreground                 Sunucuyu ön planda (canlı çıktı ile) çalıştırır (Varsayılan)"
    echo "  -p, --port <PORT>                Özel port numarası belirtir (Varsayılan: $PORT)"
    echo "  -c, --ctx <BOYUT>                Context size boyutunu belirtir (Varsayılan: $CTX_SIZE)"
    echo "  -h, --help                       Bu yardım mesajını gösterir"
    exit 0
}

# Parametre ayrıştırma
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--daemon|-b|--background)
            DAEMON_MODE=true
            shift
            ;;
        -f|--foreground)
            DAEMON_MODE=false
            shift
            ;;
        -p|--port)
            PORT="$2"
            shift 2
            ;;
        -c|--ctx)
            CTX_SIZE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_warn "Bilinmeyen parametre: $1"
            usage
            ;;
    esac
done

LLAMA_SERVER_BIN="$LLAMA_DIR/build/bin/llama-server"
MAIN_MODEL_PATH="$MODELS_DIR/$MODEL_FILE"
DRAFT_MODEL_PATH="$MODELS_DIR/$DRAFT_MODEL_FILE"

# 1. Dosya kontrolleri
if [ ! -f "$LLAMA_SERVER_BIN" ]; then
    log_error "llama-server çalıştırılabilir dosyası bulunamadı: $LLAMA_SERVER_BIN"
    log_info "Lütfen önce ./install.sh scriptini çalıştırarak derlemeyi tamamlayın."
    exit 1
fi

if [ ! -f "$MAIN_MODEL_PATH" ]; then
    log_error "Ana model dosyası bulunamadı: $MAIN_MODEL_PATH"
    log_info "Lütfen ./install.sh ile modellerin indirildiğinden emin olun."
    exit 1
fi

if [ ! -f "$DRAFT_MODEL_PATH" ]; then
    log_error "FastMTP draft model dosyası bulunamadı: $DRAFT_MODEL_PATH"
    log_info "Lütfen ./install.sh ile draft modelin indirildiğinden emin olun."
    exit 1
fi

# 2. Çalışan süreç kontrolü
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE" 2>/dev/null || true)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        log_warn "llama-server zaten çalışıyor (PID: $OLD_PID)!"
        log_info "Durdurmak için ./stop.sh, durum için ./status.sh kullanabilirsiniz."
        exit 0
    else
        rm -f "$PID_FILE"
    fi
fi

# API key kullanıcıdan istenmez; ilk çalıştırmada otomatik üretilir ve yeniden kullanılır.
ensure_api_key

# Port çakışması kontrolü
if command -v lsof &>/dev/null; then
    if lsof -i :"$PORT" &>/dev/null; then
        log_warn "$PORT portu şu anda başka bir süreç tarafından kullanılıyor!"
    fi
fi

echo -e "${CYAN}================================================================${NC}"
echo -e "${GREEN}             Qwen3.8-27B FastMTP Sunucusu Başlatılıyor        ${NC}"
echo -e "${CYAN}================================================================${NC}"
echo -e "Ana Model      : $MAIN_MODEL_PATH"
echo -e "Draft Model    : $DRAFT_MODEL_PATH"
echo -e "Port / Host    : $HOST:$PORT"
echo -e "API Key Auth   : AKTİF ($API_KEY_SOURCE)"
echo -e "Context Size   : $CTX_SIZE"
echo -e "Speculative MTP: $SPEC_TYPE (n-max: $SPEC_DRAFT_N_MAX, ngl: $SPEC_DRAFT_NGL)"
echo -e "Flash Attention: $FLASH_ATTN | Reasoning: $REASONING"
echo -e "Mod            : $( [ "$DAEMON_MODE" = true ] && echo 'Arka Plan (Daemon)' || echo 'Ön Plan (Live)' )"
echo -e "${CYAN}================================================================${NC}"

SERVER_CMD=(
    "$LLAMA_SERVER_BIN"
    --model "$MAIN_MODEL_PATH"
    --model-draft "$DRAFT_MODEL_PATH"
    --spec-type "$SPEC_TYPE"
    --spec-draft-n-max "$SPEC_DRAFT_N_MAX"
    --spec-draft-ngl "$SPEC_DRAFT_NGL"
    --ctx-size "$CTX_SIZE"
    --n-gpu-layers "$N_GPU_LAYERS"
    --split-mode "$SPLIT_MODE"
    --flash-attn "$FLASH_ATTN"
    --batch-size "$BATCH_SIZE"
    --ubatch-size "$UBATCH_SIZE"
    --parallel "$PARALLEL"
    --jinja
    --reasoning "$REASONING"
    "${AUTH_ARGS[@]}"
    --host "$HOST"
    --port "$PORT"
)

API_KEY_VALUE="$(read_api_key)"
echo -e "API Key        : ${YELLOW}${API_KEY_VALUE}${NC}"
echo -e "API Key dosyası: $API_KEY_FILE"

if [ "$DAEMON_MODE" = true ]; then
    log_info "Sunucu arka planda başlatılıyor..."
    mkdir -p "$(dirname "$LOG_FILE")"
    mkdir -p "$(dirname "$PID_FILE")"
    
    nohup "${SERVER_CMD[@]}" > "$LOG_FILE" 2>&1 &
    NEW_PID=$!
    echo "$NEW_PID" > "$PID_FILE"
    
    sleep 2
    if kill -0 "$NEW_PID" 2>/dev/null; then
        log_success "Sunucu başarıyla arka planda başlatıldı (PID: $NEW_PID)"
        log_info "Log dosyası     : $LOG_FILE"
        log_info "Canlı log takip : tail -f $LOG_FILE veya ./status.sh -f"
        log_info "Durdurmak için  : ./stop.sh"
    else
        log_error "Sunucu başlatılırken kapandı! Son loglar:"
        tail -n 20 "$LOG_FILE" || true
        rm -f "$PID_FILE"
        exit 1
    fi
else
    log_info "Sunucu ön planda başlatılıyor (Ctrl+C ile durdurabilirsiniz)..."
    exec "${SERVER_CMD[@]}"
fi
