#!/usr/bin/env bash
# ==============================================================================
# Hesap gerektirmeyen Cloudflare Quick Tunnel yönetimi
# ===============================================================================
set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[BİLGİ]${NC} $1"; }
log_success() { echo -e "${GREEN}[BAŞARILI]${NC} $1"; }
log_warn()   { echo -e "${YELLOW}[UYARI]${NC} $1"; }
log_error()  { echo -e "${RED}[HATA]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/config.env" ]; then
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/config.env"
elif [ -f "$SCRIPT_DIR/config.env.example" ]; then
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/config.env.example"
fi

WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
PORT="${PORT:-8081}"
CTX_SIZE="${CTX_SIZE:-262144}"
MODEL_NAME="${MODEL_NAME:-qwen3.8}"
API_KEY_FILE="${API_KEY_FILE:-$WORKSPACE_DIR/llama-api.key}"
TUNNEL_URL="${TUNNEL_URL:-http://127.0.0.1:$PORT}"
TUNNEL_LOG_FILE="${TUNNEL_LOG_FILE:-$WORKSPACE_DIR/cloudflared.log}"
TUNNEL_PID_FILE="${TUNNEL_PID_FILE:-$WORKSPACE_DIR/cloudflared.pid}"

usage() {
    echo -e "${CYAN}Kullanım:${NC} $0 <start|stop|status|logs|install>"
    echo ""
    echo "  start    Geçici, hesapsız trycloudflare.com tunnel başlatır"
    echo "  stop     Tunnel sürecini durdurur"
    echo "  status   Tunnel durumunu ve public adresi gösterir"
    echo "  logs     Tunnel loglarını canlı takip eder"
    echo "  install  cloudflared'ın hazır olduğunu kontrol eder"
}

require_cloudflared() {
    if command -v cloudflared &>/dev/null; then
        return 0
    fi

    log_error "cloudflared bulunamadı. Önce '$0 install' komutunu çalıştırın."
    exit 1
}

running_pid() {
    local pid=""

    if [ -f "$TUNNEL_PID_FILE" ]; then
        pid=$(cat "$TUNNEL_PID_FILE" 2>/dev/null || true)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "$pid"
            return 0
        fi
    fi

    return 1
}

extract_public_url() {
    if [ -f "$TUNNEL_LOG_FILE" ]; then
        sed -nE 's#.*(https://[-[:alnum:]]+\.trycloudflare\.com).*#\1#p' "$TUNNEL_LOG_FILE" | head -n 1
    fi
}

read_api_key() {
    awk 'NF && $1 !~ /^#/ { print; exit }' "$API_KEY_FILE" 2>/dev/null || true
}

print_connection_info() {
    local public_url="${1:-}"
    local api_key="$(read_api_key)"
    local base_url=""

    if [ -z "$public_url" ]; then
        public_url="$(extract_public_url)"
    fi

    echo -e "${CYAN}================================================================${NC}"
    echo -e "${GREEN}                   UZAK ERİŞİM HAZIR                            ${NC}"
    echo -e "${CYAN}================================================================${NC}"
    if [ -n "$public_url" ]; then
        base_url="${public_url}/v1"
        echo -e "Public link    : ${GREEN}${public_url}${NC}"
        echo -e "OpenAI Base URL: ${GREEN}${base_url}${NC}"
    else
        echo -e "Public link    : ${YELLOW}URL logda henüz görünmedi; $TUNNEL_LOG_FILE dosyasını kontrol edin.${NC}"
    fi
    if [ -n "$api_key" ]; then
        echo -e "API key        : ${YELLOW}${api_key}${NC}"
    else
        echo -e "API key        : ${YELLOW}Sunucu başlatılınca otomatik üretilecek.${NC}"
    fi
    echo -e "API key header : Authorization: Bearer <API_KEY>"
    echo ""
    echo "Kopyalanabilir OpenCode yapılandırma özeti:"
    printf '{\n  "provider": "openai-compatible",\n  "base_url": "%s",\n  "api_key": "%s",\n  "model": "%s",\n  "context_length": %s\n}\n' \
        "$base_url" "$api_key" "$MODEL_NAME" "$CTX_SIZE"
    echo -e "${CYAN}================================================================${NC}"
}

start_tunnel() {
    local current_pid=""
    local public_url=""
    local health_status=""

    require_cloudflared

    if current_pid="$(running_pid)"; then
        log_warn "Quick Tunnel zaten çalışıyor (PID: $current_pid)."
        print_connection_info
        return 0
    fi

    mkdir -p "$(dirname "$TUNNEL_LOG_FILE")" "$(dirname "$TUNNEL_PID_FILE")"

    health_status=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$TUNNEL_URL/health" 2>/dev/null || true)
    if [ "$health_status" != "200" ] && [ "$health_status" != "503" ]; then
        log_warn "Llama API şu anda sağlıklı yanıt vermiyor ($TUNNEL_URL/health: ${health_status:-erişilemedi}). Tunnel yine de başlatılıyor."
    fi

    log_info "Hesapsız Cloudflare Quick Tunnel başlatılıyor: $TUNNEL_URL"
    nohup cloudflared tunnel --url "$TUNNEL_URL" > "$TUNNEL_LOG_FILE" 2>&1 &
    current_pid=$!
    echo "$current_pid" > "$TUNNEL_PID_FILE"

    for _ in $(seq 1 10); do
        sleep 1
        public_url="$(extract_public_url)"
        if [ -n "$public_url" ]; then
            break
        fi
        if ! kill -0 "$current_pid" 2>/dev/null; then
            break
        fi
    done

    if ! kill -0 "$current_pid" 2>/dev/null; then
        log_error "cloudflared başlatılamadı. Son loglar:"
        tail -n 30 "$TUNNEL_LOG_FILE" 2>/dev/null || true
        rm -f "$TUNNEL_PID_FILE"
        exit 1
    fi

    log_success "Quick Tunnel çalışıyor (PID: $current_pid)."
    print_connection_info "$public_url"
    log_warn "Bu adres geçicidir; tunnel durdurulunca veya süreç yeniden başlayınca değişir."
}

stop_tunnel() {
    local current_pid=""

    if ! current_pid="$(running_pid)"; then
        rm -f "$TUNNEL_PID_FILE"
        log_info "Çalışan Quick Tunnel bulunamadı."
        return 0
    fi

    kill "$current_pid" 2>/dev/null || true
    sleep 1
    if kill -0 "$current_pid" 2>/dev/null; then
        log_warn "Tunnel kapanmadı; sonlandırılıyor (PID: $current_pid)."
        kill -KILL "$current_pid" 2>/dev/null || true
    fi
    rm -f "$TUNNEL_PID_FILE"
    log_success "Quick Tunnel durduruldu."
}

status_tunnel() {
    local current_pid=""
    local public_url="$(extract_public_url)"

    if current_pid="$(running_pid)"; then
        log_success "Quick Tunnel çalışıyor (PID: $current_pid)."
        print_connection_info "$public_url"
    else
        log_warn "Quick Tunnel çalışmıyor."
        if [ -n "$public_url" ]; then
            echo "Son bilinen public link: $public_url"
        fi
    fi
}

install_cloudflared() {
    if command -v cloudflared &>/dev/null; then
        log_success "cloudflared zaten kurulu: $(cloudflared --version 2>&1 | head -n 1)"
        return 0
    fi

    log_error "cloudflared PATH içinde bulunamadı. Bu çalışma ortamında otomatik kurulu olması bekleniyordu."
    return 1
}

COMMAND="${1:-help}"
case "$COMMAND" in
    start|run)
        start_tunnel
        ;;
    stop)
        stop_tunnel
        ;;
    status)
        status_tunnel
        ;;
    logs|log)
        tail -f "$TUNNEL_LOG_FILE"
        ;;
    install)
        install_cloudflared
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        log_error "Bilinmeyen komut: $COMMAND"
        usage
        exit 1
        ;;
esac
