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
    echo -e "  ${GREEN}help${NC}          Bu yardım ekranını gösterir"
    echo -e "${CYAN}================================================================${NC}"
    exit 0
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
    help|--help|-h|"")
        usage
        ;;
    *)
        echo -e "${RED}[HATA]${NC} Bilinmeyen komut: $COMMAND"
        usage
        ;;
esac
