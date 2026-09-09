#!/usr/bin/env bash
# ==============================================================================
# Qwen3.8-27B FastMTP Tek Komutla Otomatik Kurulum ve Başlatma (One-Liner Bootstrap)
# Kullanım:
#   curl -sSL https://raw.githubusercontent.com/MATTAM540/qwen-fastmtp/main/bootstrap.sh | bash
# ==============================================================================
set -euo pipefail

# Renk tanımlamaları
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[BİLGİ]${NC} $1"; }
log_success() { echo -e "${GREEN}[BAŞARILI]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[UYARI]${NC} $1"; }
log_error()   { echo -e "${RED}[HATA]${NC} $1"; }
log_step()    { echo -e "\n${CYAN}================================================================${NC}\n${BOLD}${MAGENTA}==>${NC} ${BOLD}$1${NC}\n${CYAN}================================================================${NC}"; }

export DEBIAN_FRONTEND=noninteractive

echo -e "${CYAN}================================================================${NC}"
echo -e "${GREEN}${BOLD}    🚀 Qwen3.8-27B FastMTP Tek Tıkla Tam Otomatik Kurulum     ${NC}"
echo -e "${CYAN}================================================================${NC}"
echo -e "${YELLOW}Tüm kurulum adımları ve detaylı loglar anlık olarak görüntülenecek...${NC}"
echo -e "${CYAN}================================================================${NC}"

WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
REPO_DIR="$WORKSPACE_DIR/qwen-fastmtp"
LLAMA_DIR="$WORKSPACE_DIR/llama.cpp"
MODELS_DIR="$WORKSPACE_DIR/models/qwen38"
LOG_FILE="$WORKSPACE_DIR/qwen.log"
PID_FILE="$WORKSPACE_DIR/llama-server.pid"
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

# 1. Adım: Sistem ve Donanım Analizi
log_step "ADIM 1/6: Sistem ve Donanım Kaynakları Analiz Ediliyor"
mkdir -p "$WORKSPACE_DIR" "$MODELS_DIR" 2>/dev/null || sudo mkdir -p "$WORKSPACE_DIR" "$MODELS_DIR"
cd "$WORKSPACE_DIR"

echo -e "${CYAN}--- Çalışma Ortamı ---${NC}"
echo -e "Çalışma Dizini : ${BOLD}$WORKSPACE_DIR${NC}"
echo -e "llama.cpp      : ${BOLD}$LLAMA_DIR${NC}"
echo -e "Model Deposu   : ${BOLD}$MODELS_DIR${NC}"

echo -e "\n${CYAN}--- GPU ve CUDA Durumu ---${NC}"
if command -v nvidia-smi &>/dev/null; then
    nvidia-smi --query-gpu=name,driver_version,memory.total,utilization.gpu --format=csv,noheader | awk -F', ' '{
        printf "GPU Modeli: %s | Sürücü: %s | Toplam VRAM: %s | Kullanım: %s\n", $1, $2, $3, $4
    }'
else
    log_warn "nvidia-smi bulunamadı! CUDA hızlandırması çalışmayabilir."
fi

if command -v nvcc &>/dev/null; then
    NVCC_VER=$(nvcc --version | grep "release" | awk '{print $5}' | sed 's/,//')
    log_success "CUDA Compiler (nvcc) sürümü: $NVCC_VER"
fi

echo -e "\n${CYAN}--- CPU, RAM ve Disk Durumu ---${NC}"
CPU_CORES=$(nproc 2>/dev/null || echo 4)
RAM_INFO=$(free -h 2>/dev/null | awk '/^Mem:/ {print $2 " toplam, " $3 " kullanılıyor, " $7 " boş"}' || true)
DISK_FREE=$(df -h "$WORKSPACE_DIR" 2>/dev/null | awk 'NR==2 {print $4 " boş alan (" $2 " toplam)"}' || true)
echo -e "CPU Çekirdekleri : $CPU_CORES çekirdek"
echo -e "Sistem RAM       : $RAM_INFO"
echo -e "Disk Alanı       : $DISK_FREE"

# 2. Adım: Paketler
log_step "ADIM 2/6: Temel Sistem Paketleri ve Derleme Araçları Kuruluyor"
SUDO_CMD=""
if [ "$EUID" -ne 0 ] && command -v sudo &>/dev/null; then
    SUDO_CMD="sudo"
fi

if command -v apt-get &>/dev/null; then
    log_info "APT paket listeleri güncelleniyor..."
    $SUDO_CMD apt-get update -y
    
    log_info "Gerekli derleme araçları yükleniyor (git, cmake, build-essential, curl, python3)..."
    $SUDO_CMD apt-get install -y --no-install-recommends \
        git cmake build-essential curl python3 python3-pip python3-venv libgomp1
    log_success "Sistem paketleri hazır."
else
    log_warn "apt-get bulunamadı, mevcut sistem paketleriyle devam ediliyor."
fi

# 3. Adım: llama.cpp Klonlama & FastMTP Yaması
log_step "ADIM 3/6: llama.cpp Deposu Klonlanıyor ve FastMTP Yaması Uygulanıyor"
if [ -d "$LLAMA_DIR/.git" ]; then
    log_info "Mevcut llama.cpp dizini bulundu, güncelleniyor: $LLAMA_DIR"
    cd "$LLAMA_DIR"
    git fetch origin master
    git checkout master
    git pull origin master
else
    log_info "llama.cpp GitHub reposu klonlanıyor (https://github.com/ggml-org/llama.cpp.git)..."
    git clone --progress https://github.com/ggml-org/llama.cpp.git "$LLAMA_DIR"
    cd "$LLAMA_DIR"
fi

PATCH_URL="https://huggingface.co/HauhauCS/Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-MTP-GGUF/resolve/main/HauhauCS-FastMTP-llama.cpp.patch"
PATCH_TEMP="/tmp/HauhauCS-FastMTP.patch"

log_info "FastMTP yaması Hugging Face'den indiriliyor: $PATCH_URL"
curl -L -o "$PATCH_TEMP" "$PATCH_URL"

log_info "Yama kontrolü yapılıyor (git apply --check)..."
if git apply --check "$PATCH_TEMP" 2>/dev/null; then
    log_info "FastMTP yaması uygulanıyor..."
    git apply --verbose "$PATCH_TEMP"
    log_success "FastMTP yaması başarıyla uygulandı! Değişen dosyalar:"
    git diff --stat || true
else
    if git diff --name-only HEAD | grep -q "qwen35.cpp" || git log -n 5 | grep -qi "FastMTP"; then
        log_warn "FastMTP yaması zaten uygulanmış görünüyor, devam ediliyor."
    else
        log_warn "Yama doğrudan uygulanamadı. Zorla (rejects) deneniyor..."
        git apply --reject "$PATCH_TEMP" || true
    fi
fi

# 4. Adım: CUDA ile Derleme (Canlı İlerleme Çıktısı)
log_step "ADIM 4/6: llama.cpp CUDA (GGML_CUDA=ON) ile Derleniyor"
cd "$LLAMA_DIR"
log_info "Önceki build dizini temizleniyor..."
rm -rf build

log_info "CMake yapılandırması hazırlanıyor (Release modu, CUDA açık)..."
cmake -S . -B build \
    -DGGML_CUDA=ON \
    -DCMAKE_BUILD_TYPE=Release

NPROC_COUNT=$(nproc 2>/dev/null || echo 4)
log_info "$NPROC_COUNT paralel iş parçacığıyla derleme başlatılıyor..."
cmake --build build --config Release -j"$NPROC_COUNT"

if [ -f "$LLAMA_DIR/build/bin/llama-server" ]; then
    log_success "llama-server başarıyla derlendi!"
    echo -e "${CYAN}--- llama-server Versiyon Bilgisi ---${NC}"
    "$LLAMA_DIR/build/bin/llama-server" --version || true
else
    log_error "llama-server derlemesi başarısız oldu!"
    exit 1
fi

# 5. Adım: Hugging Face CLI ve Model İndirme (Canlı Progress Bar)
log_step "ADIM 5/6: Qwen3.8-27B Modelleri Hugging Face'den İndiriliyor"
PIP_FLAGS="--upgrade"
if python3 -m pip install --help 2>&1 | grep -q -- "--break-system-packages"; then
    PIP_FLAGS="$PIP_FLAGS --break-system-packages"
fi

log_info "huggingface_hub Python kütüphanesi kontrol ediliyor/yükleniyor..."
python3 -m pip install $PIP_FLAGS huggingface_hub

HF_CMD="huggingface-cli download"
if command -v hf &>/dev/null; then
    HF_CMD="hf download"
fi

HF_REPO="HauhauCS/Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-MTP-GGUF"
MODEL_FILE="Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-Q8_K_P.gguf"
DRAFT_MODEL_FILE="Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-FastMTP-32K.gguf"
MODEL_NAME="${MODEL_NAME:-qwen3.8}"

cd "$MODELS_DIR"

log_info "Hedef Repo: $HF_REPO"
log_info "1. Ana Model : $MODEL_FILE (~31.5 GB)"
log_info "2. Draft Model: $DRAFT_MODEL_FILE (~900 MB)"

# Ana model kontrolü ve indirme
if [ -f "$MODELS_DIR/$MODEL_FILE" ] && [ -s "$MODELS_DIR/$MODEL_FILE" ]; then
    log_success "Ana model dosyası zaten mevcut: $MODEL_FILE ($(du -h "$MODELS_DIR/$MODEL_FILE" | awk '{print $1}'))"
else
    log_info "Ana model indiriliyor ($MODEL_FILE)... İlerleme çubuğu:"
    $HF_CMD "$HF_REPO" "$MODEL_FILE" --local-dir "$MODELS_DIR"
    log_success "Ana model indirme tamamlandı."
fi

# Draft model kontrolü ve indirme
if [ -f "$MODELS_DIR/$DRAFT_MODEL_FILE" ] && [ -s "$MODELS_DIR/$DRAFT_MODEL_FILE" ]; then
    log_success "Draft model dosyası zaten mevcut: $DRAFT_MODEL_FILE ($(du -h "$MODELS_DIR/$DRAFT_MODEL_FILE" | awk '{print $1}'))"
else
    log_info "FastMTP Draft model indiriliyor ($DRAFT_MODEL_FILE)..."
    $HF_CMD "$HF_REPO" "$DRAFT_MODEL_FILE" --local-dir "$MODELS_DIR"
    log_success "Draft model indirme tamamlandı."
fi

echo -e "\n${CYAN}--- İndirilen Model Dosyaları ---${NC}"
ls -lh "$MODELS_DIR"

# 6. Adım: Sunucuyu Başlatma ve Başlangıç Loglarını Canlı İzleme
log_step "ADIM 6/6: Qwen3.8-27B llama-server Başlatılıyor ve VRAM'e Yükleniyor"
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE" 2>/dev/null || true)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        log_info "Mevcut çalışan eski sunucu durduruluyor (PID: $OLD_PID)..."
        kill -9 "$OLD_PID" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
fi

PORT="${PORT:-8081}"
HOST="${HOST:-127.0.0.1}"
CTX_SIZE="${CTX_SIZE:-262144}"

ensure_api_key

log_info "llama-server parametreleri:"
echo -e "  - Ana Model     : $MODELS_DIR/$MODEL_FILE"
echo -e "  - Draft Model   : $MODELS_DIR/$DRAFT_MODEL_FILE"
echo -e "  - Spec Type     : draft-mtp (n-max: 3, ngl: 999)"
echo -e "  - Context Boyutu: $CTX_SIZE (256K)"
echo -e "  - GPU Katmanları: 999 (Tüm katmanlar CUDA'ya offload)"
echo -e "  - Flash Attn    : ON | Reasoning: ON | Jinja: ON"
echo -e "  - Host / Port   : $HOST:$PORT"
echo -e "  - API Key Auth   : AKTİF ($API_KEY_SOURCE)"
echo -e "  - Log Dosyası   : $LOG_FILE"

nohup "$LLAMA_DIR/build/bin/llama-server" \
  --model "$MODELS_DIR/$MODEL_FILE" \
  --model-draft "$MODELS_DIR/$DRAFT_MODEL_FILE" \
  --spec-type draft-mtp \
  --spec-draft-n-max 3 \
  --spec-draft-ngl 999 \
  --ctx-size "$CTX_SIZE" \
  --n-gpu-layers 999 \
  --split-mode none \
  --flash-attn on \
  --batch-size 2048 \
  --ubatch-size 512 \
  --parallel 1 \
  --jinja \
  --reasoning on \
  --alias "$MODEL_NAME" \
  "${AUTH_ARGS[@]}" \
  --host "$HOST" \
  --port "$PORT" \
  > "$LOG_FILE" 2>&1 &

NEW_PID=$!
echo "$NEW_PID" > "$PID_FILE"

log_info "Sunucu başlatıldı (PID: $NEW_PID). Modelin GPU VRAM'e yüklenme logları izleniyor..."

# İlk 10 saniye logları canlı ekrana bas
echo -e "\n${CYAN}------------------- BAŞLANGIÇ SUNUCU LOGLARI -------------------${NC}"
for i in {1..12}; do
    if [ -f "$LOG_FILE" ]; then
        tail -n 25 "$LOG_FILE" | grep -v "^$" || true
    fi
    if grep -qi "HTTP server listening" "$LOG_FILE" 2>/dev/null; then
        echo -e "${GREEN}✔ HTTP Server aktif ve istekleri dinliyor!${NC}"
        break
    fi
    if ! kill -0 "$NEW_PID" 2>/dev/null; then
        log_error "Sunucu beklenmedik şekilde kapandı! Hata detayları:"
        cat "$LOG_FILE"
        exit 1
    fi
    sleep 1
    echo -e "${BLUE}... Yükleniyor ($i/12 sn) ...${NC}"
done
echo -e "${CYAN}----------------------------------------------------------------${NC}"

echo -e "\n${CYAN}================================================================${NC}"
echo -e "${GREEN}${BOLD}       🎉 TEBRİKLER! QWEN3.8-27B FASTMTP HAZIR VE ÇALIŞIYOR     ${NC}"
echo -e "${CYAN}================================================================${NC}"
echo -e "Sunucu Süreç ID : ${GREEN}${BOLD}$NEW_PID${NC}"
echo -e "Yerel API       : ${GREEN}http://127.0.0.1:$PORT/v1${NC}"
echo -e "Log Dosyası     : ${BLUE}$LOG_FILE${NC}"

TUNNEL_LOG_FILE="${TUNNEL_LOG_FILE:-$WORKSPACE_DIR/cloudflared.log}"
TUNNEL_PID_FILE="${TUNNEL_PID_FILE:-$WORKSPACE_DIR/cloudflared.pid}"
PUBLIC_URL=""

if command -v cloudflared &>/dev/null; then
    log_info "Hesapsız Cloudflare Quick Tunnel başlatılıyor..."
    nohup cloudflared tunnel --url "http://127.0.0.1:$PORT" > "$TUNNEL_LOG_FILE" 2>&1 &
    TUNNEL_PID=$!
    echo "$TUNNEL_PID" > "$TUNNEL_PID_FILE"

    for _ in $(seq 1 10); do
        sleep 1
        PUBLIC_URL=$(sed -nE 's#.*(https://[-[:alnum:]]+\.trycloudflare\.com).*#\1#p' "$TUNNEL_LOG_FILE" | head -n 1)
        if [ -n "$PUBLIC_URL" ]; then
            break
        fi
        if ! kill -0 "$TUNNEL_PID" 2>/dev/null; then
            break
        fi
    done

    if [ -z "$PUBLIC_URL" ] || ! kill -0 "$TUNNEL_PID" 2>/dev/null; then
        log_warn "Quick Tunnel linki üretilemedi; log: $TUNNEL_LOG_FILE"
    fi
else
    log_warn "cloudflared bulunamadığı için public link oluşturulamadı."
fi

echo -e "${CYAN}================================================================${NC}"
echo -e "${GREEN}${BOLD}                    AI API BİLGİLENDİRME                       ${NC}"
echo -e "${CYAN}================================================================${NC}"
echo -e "AI context      : ${GREEN}${CTX_SIZE} token${NC}"
echo -e "Model adı       : ${GREEN}${MODEL_NAME}${NC}"
if [ -n "$PUBLIC_URL" ]; then
    BASE_URL="${PUBLIC_URL}/v1"
    echo -e "Public link     : ${GREEN}${PUBLIC_URL}${NC}"
    echo -e "OpenAI Base URL : ${GREEN}${BASE_URL}${NC}"
else
    BASE_URL="http://127.0.0.1:${PORT}/v1"
    echo -e "Public link     : ${YELLOW}oluşturulamadı${NC}"
fi
API_KEY_VALUE="$(read_api_key)"
echo -e "API key         : ${YELLOW}${API_KEY_VALUE}${NC}"
echo -e "API key dosyası : ${BLUE}$API_KEY_FILE${NC}"
echo ""
echo "Kopyalanabilir OpenCode yapılandırma özeti:"
printf '{\n  "provider": "openai-compatible",\n  "base_url": "%s",\n  "api_key": "%s",\n  "model": "%s",\n  "context_length": %s\n}\n' \
    "$BASE_URL" "$API_KEY_VALUE" "$MODEL_NAME" "$CTX_SIZE"
echo -e "${CYAN}================================================================${NC}"
echo -e ""
echo -e "${YELLOW}Sunucuyu Yönetmek İçin:${NC}"
echo -e "  Canlı logları takip et : ${CYAN}tail -f $LOG_FILE${NC}"
echo -e "  Sunucuyu durdur        : ${CYAN}kill $NEW_PID${NC}"
echo -e "  GPU kullanımını gör    : ${CYAN}nvidia-smi${NC}"
echo -e "${CYAN}================================================================${NC}"
