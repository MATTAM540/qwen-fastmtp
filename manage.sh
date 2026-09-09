#!/usr/bin/env bash
# ==============================================================================
# Qwen3.8-27B FastMTP Merkezi Yönetim CLI (manage.sh)
# ==============================================================================
set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${GREEN}      Qwen3.8-27B FastMTP llama-server Yönetim Aracı           ${NC}"
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${YELLOW}Kullanım:${NC} $0 <komut> [seçenekler]"
    echo ""
    echo -e "${CYAN}Komutlar:${NC}"
    echo -e "  ${GREEN}install${NC}       llama.cpp, yama ve Qwen3.8 modellerinin tam kurulumunu yapar"
    echo -e "  ${GREEN}start${NC}         Sunucuyu arka planda (daemon) başlatır"
    echo -e "  ${GREEN}start-live${NC}    Sunucuyu terminalde ön planda (canlı) başlatır"
    echo -e "  ${GREEN}stop${NC}          Çalışan llama-server sürecini durdurur"
    echo -e "  ${GREEN}restart${NC}       Sunucuyu yeniden başlatır"
    echo -e "  ${GREEN}status${NC}        Sunucu, API ve GPU durumunu kontrol eder"
    echo -e "  ${GREEN}logs${NC}          Sunucu loglarını canlı olarak takip eder (tail -f)"
    echo -e "  ${GREEN}start-public${NC}  Sunucuyu ve hesapsız geçici Cloudflare Tunnel'ı başlatır"
    echo -e "  ${GREEN}tunnel${NC}       Geçici Cloudflare Tunnel'ı başlatır"
    echo -e "  ${GREEN}tunnel-stop${NC}  Geçici Cloudflare Tunnel'ı durdurur"
    echo -e "  ${GREEN}tunnel-status${NC} Tunnel durumunu ve public linki gösterir"
    echo -e "  ${GREEN}tunnel-logs${NC}  Tunnel loglarını canlı takip eder"
    echo -e "  ${GREEN}tunnel-install${NC} cloudflared'ın hazır olduğunu kontrol eder"
    echo -e "  ${GREEN}api-key${NC}      Otomatik oluşturulan API key'i gösterir"
    echo -e "  ${GREEN}help${NC}          Bu yardım ekranını gösterir"
    echo -e "${CYAN}================================================================${NC}"
    exit 0
}

show_api_key() {
    if [ -f "$SCRIPT_DIR/config.env" ]; then
        # shellcheck source=/dev/null
        source "$SCRIPT_DIR/config.env"
    elif [ -f "$SCRIPT_DIR/config.env.example" ]; then
        # shellcheck source=/dev/null
        source "$SCRIPT_DIR/config.env.example"
    fi

    local workspace_dir="${WORKSPACE_DIR:-/workspace}"
    local api_key_file="${API_KEY_FILE:-$workspace_dir/llama-api.key}"
    local api_key=""

    if [ -f "$api_key_file" ]; then
        api_key=$(awk 'NF && $1 !~ /^#/ { print; exit }' "$api_key_file" 2>/dev/null || true)
    fi

    if [ -n "$api_key" ]; then
        echo "$api_key"
    else
        echo "API key henüz oluşturulmadı. Önce ./manage.sh start çalıştırın." >&2
        return 1
    fi
}

COMMAND="${1:-}"
shift || true

case "$COMMAND" in
    install)
        bash "$SCRIPT_DIR/install.sh" "$@"
        ;;
    start)
        bash "$SCRIPT_DIR/start.sh" --daemon "$@"
        ;;
    start-live)
        bash "$SCRIPT_DIR/start.sh" "$@"
        ;;
    start-public)
        bash "$SCRIPT_DIR/start.sh" --daemon "$@"
        bash "$SCRIPT_DIR/tunnel.sh" start
        ;;
    stop)
        bash "$SCRIPT_DIR/stop.sh" "$@"
        ;;
    restart)
        bash "$SCRIPT_DIR/stop.sh"
        sleep 2
        bash "$SCRIPT_DIR/start.sh" --daemon "$@"
        ;;
    status)
        bash "$SCRIPT_DIR/status.sh" "$@"
        ;;
    logs)
        bash "$SCRIPT_DIR/status.sh" --follow
        ;;
    tunnel|tunnel-start)
        bash "$SCRIPT_DIR/tunnel.sh" start
        ;;
    tunnel-stop)
        bash "$SCRIPT_DIR/tunnel.sh" stop
        ;;
    tunnel-status)
        bash "$SCRIPT_DIR/tunnel.sh" status
        ;;
    tunnel-logs)
        bash "$SCRIPT_DIR/tunnel.sh" logs
        ;;
    tunnel-install)
        bash "$SCRIPT_DIR/tunnel.sh" install
        ;;
    api-key)
        show_api_key
        ;;
    help|--help|-h|"")
        usage
        ;;
    *)
        echo -e "${RED}[HATA]${NC} Bilinmeyen komut: $COMMAND"
        usage
        ;;
esac
