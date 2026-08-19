#!/usr/bin/env bash
# ==============================================================================
# Qwen3.8-27B llama-server Durdurma Scripti
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
PID_FILE="${PID_FILE:-$WORKSPACE_DIR/llama-server.pid}"

STOPPED=false

# 1. PID dosyası üzerinden durdurma
if [ -f "$PID_FILE" ]; then
    SERVER_PID=$(cat "$PID_FILE" 2>/dev/null || true)
    if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
        log_info "Çalışan llama-server süreci durduruluyor (PID: $SERVER_PID)..."
        kill "$SERVER_PID" 2>/dev/null || true
        
        # 10 saniye kadar bekle
        for i in {1..10}; do
            if ! kill -0 "$SERVER_PID" 2>/dev/null; then
                STOPPED=true
                break
            fi
            sleep 1
        done
        
        # Hala kapanmadıysa zorla kapat
        if [ "$STOPPED" = false ] && kill -0 "$SERVER_PID" 2>/dev/null; then
            log_warn "Süreç normal kapanmadı, SIGKILL gönderiliyor..."
            kill -9 "$SERVER_PID" 2>/dev/null || true
            sleep 1
            STOPPED=true
        fi
    fi
    rm -f "$PID_FILE"
fi

# 2. Arka planda kalmış olabilecek llama-server süreçlerini temizle
OTHER_PIDS=$(pgrep -f "llama-server.*qwen" 2>/dev/null || true)
if [ -n "$OTHER_PIDS" ]; then
    log_warn "PID dosyasında olmayan diğer llama-server süreçleri bulundu: $OTHER_PIDS"
    for p in $OTHER_PIDS; do
        log_info "Süreç sonlandırılıyor: $p"
        kill -9 "$p" 2>/dev/null || true
    done
    STOPPED=true
fi

if [ "$STOPPED" = true ]; then
    log_success "llama-server başarıyla durduruldu."
else
    log_info "Çalışan aktif bir llama-server süreci bulunamadı."
fi
