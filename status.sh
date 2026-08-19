#!/usr/bin/env bash
# ==============================================================================
# Qwen3.8-27B llama-server ve GPU Durum Kontrol Scripti
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

WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
PORT="${PORT:-8081}"
LOG_FILE="${LOG_FILE:-$WORKSPACE_DIR/qwen.log}"
PID_FILE="${PID_FILE:-$WORKSPACE_DIR/llama-server.pid}"

FOLLOW_LOGS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--follow)
            FOLLOW_LOGS=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

echo -e "${CYAN}================================================================${NC}"
echo -e "${GREEN}             Qwen3.8-27B Sunucu ve Sistem Durumu               ${NC}"
echo -e "${CYAN}================================================================${NC}"

# 1. Süreç Durumu
IS_RUNNING=false
SERVER_PID=""

if [ -f "$PID_FILE" ]; then
    SERVER_PID=$(cat "$PID_FILE" 2>/dev/null || true)
    if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
        IS_RUNNING=true
    fi
fi

if [ "$IS_RUNNING" = false ]; then
    DETECTED_PID=$(pgrep -f "llama-server.*qwen" | head -n 1 || true)
    if [ -n "$DETECTED_PID" ]; then
        IS_RUNNING=true
        SERVER_PID="$DETECTED_PID"
    fi
fi

if [ "$IS_RUNNING" = true ]; then
    echo -e "Sunucu Durumu  : ${GREEN}ÇALIŞIYOR${NC} (PID: $SERVER_PID)"
else
    echo -e "Sunucu Durumu  : ${RED}DURDU (KAPALI)${NC}"
fi

# 2. HTTP / Port Sağlık Kontrolü
if [ "$IS_RUNNING" = true ]; then
    HEALTH_RESP=$(curl -s -m 3 "http://127.0.0.1:$PORT/health" 2>/dev/null || true)
    if [ -n "$HEALTH_RESP" ]; then
        echo -e "HTTP Endpoint  : ${GREEN}AKTİF (http://127.0.0.1:$PORT)${NC} -> $HEALTH_RESP"
    else
        echo -e "HTTP Endpoint  : ${YELLOW}YANIT VERMİYOR veya BAŞLATILIYOR (Port: $PORT)${NC}"
    fi
fi

# 3. GPU ve VRAM Durumu
echo -e "\n${CYAN}--- GPU Durumu ---${NC}"
if command -v nvidia-smi &>/dev/null; then
    nvidia-smi --query-gpu=name,driver_version,memory.used,memory.total,utilization.gpu,temperature.gpu --format=csv,noheader | awk -F', ' '{
        printf "GPU: %s | Sürücü: %s | VRAM: %s / %s | Kullanım: %s | Sıcaklık: %s°C\n", $1, $2, $3, $4, $5, $6
    }'
else
    echo -e "${YELLOW}nvidia-smi bulunamadı.${NC}"
fi

# 4. Log Özeti
echo -e "\n${CYAN}--- Son Log Kayıtları ($LOG_FILE) ---${NC}"
if [ -f "$LOG_FILE" ]; then
    tail -n 15 "$LOG_FILE"
else
    echo -e "Henüz log dosyası oluşmadı."
fi
echo -e "${CYAN}================================================================${NC}"

if [ "$FOLLOW_LOGS" = true ]; then
    if [ -f "$LOG_FILE" ]; then
        echo -e "${BLUE}Canlı log takibi başlatılıyor (Çıkmak için Ctrl+C)...${NC}"
        tail -f "$LOG_FILE"
    else
        log_warn "İzlenecek log dosyası bulunamadı: $LOG_FILE"
    fi
fi
