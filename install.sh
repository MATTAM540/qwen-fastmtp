#!/usr/bin/env bash
# ==============================================================================
# Qwen3.8-27B FastMTP Otomatik Kurulum Scripti (Vast.ai / CUDA A100 Destekli)
# ==============================================================================
set -euo pipefail

# Renk tanımlamaları
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info()    { echo -e "${BLUE}[BİLGİ]${NC} $1"; }
log_success() { echo -e "${GREEN}[BAŞARILI]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[UYARI]${NC} $1"; }
log_error()   { echo -e "${RED}[HATA]${NC} $1"; }
log_step()    { echo -e "\n${CYAN}==>${NC} ${BLUE}$1${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Yapılandırma dosyasını yükle (varsa)
if [ -f "$SCRIPT_DIR/config.env" ]; then
    log_info "Özel yapılandırma dosyası yüklendi: config.env"
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/config.env"
elif [ -f "$SCRIPT_DIR/config.env.example" ]; then
    log_info "Varsayılan yapılandırma şablonu yüklendi: config.env.example"
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/config.env.example"
fi

# Varsayılan değerler (tanımlı değilse)
WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
LLAMA_DIR="${LLAMA_DIR:-$WORKSPACE_DIR/llama.cpp}"
MODELS_DIR="${MODELS_DIR:-$WORKSPACE_DIR/models/qwen38}"
HF_REPO="${HF_REPO:-HauhauCS/Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-MTP-GGUF}"
PATCH_URL="${PATCH_URL:-https://huggingface.co/HauhauCS/Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-MTP-GGUF/resolve/main/HauhauCS-FastMTP-llama.cpp.patch}"
MODEL_FILE="${MODEL_FILE:-Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-Q8_K_P.gguf}"
DRAFT_MODEL_FILE="${DRAFT_MODEL_FILE:-Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-FastMTP-32K.gguf}"

# Dizin izin ve varlık kontrolü
if [ ! -d "$WORKSPACE_DIR" ]; then
    log_info "$WORKSPACE_DIR dizini oluşturuluyor..."
    mkdir -p "$WORKSPACE_DIR" 2>/dev/null || sudo mkdir -p "$WORKSPACE_DIR"
fi

echo -e "${CYAN}================================================================${NC}"
echo -e "${GREEN}      Qwen3.8-27B FastMTP Otomatik Kurulum Başlatılıyor        ${NC}"
echo -e "${CYAN}================================================================${NC}"
echo -e "Çalışma Dizini : $WORKSPACE_DIR"
echo -e "llama.cpp      : $LLAMA_DIR"
echo -e "Model Dizini   : $MODELS_DIR"
echo -e "Model Deposu   : $HF_REPO"
echo -e "${CYAN}================================================================${NC}"

# 1. Adım: Sistem ve GPU Kontrolü
log_step "1/6: Sistem ve GPU kontrolleri yapılıyor..."
if command -v nvidia-smi &>/dev/null; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n 1)
    VRAM_TOTAL=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader | head -n 1)
    DRIVER_VER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n 1)
    log_success "NVIDIA GPU Algılandı: $GPU_NAME ($VRAM_TOTAL VRAM, Sürücü: $DRIVER_VER)"
else
    log_warn "nvidia-smi bulunamadı! CUDA hızlandırması çalışmayabilir."
fi

if command -v nvcc &>/dev/null; then
    NVCC_VER=$(nvcc --version | grep "release" | awk '{print $5}' | sed 's/,//')
    log_success "CUDA Derleyicisi (nvcc) Mevcut: $NVCC_VER"
else
    log_warn "nvcc bulunamadı! CUDA araç setinin yüklü olduğundan emin olun."
fi

# 2. Adım: Gerekli Paketlerin Yüklenmesi
log_step "2/6: Sistem paketleri ve derleme araçları yükleniyor..."
SUDO_CMD=""
if [ "$EUID" -ne 0 ]; then
    if command -v sudo &>/dev/null; then
        SUDO_CMD="sudo"
    fi
fi

if command -v apt &>/dev/null; then
    log_info "APT paket listesi güncelleniyor ve bağımlılıklar yükleniyor..."
    $SUDO_CMD apt update -y -qq || true
    DEBIAN_FRONTEND=noninteractive $SUDO_CMD apt install -y -qq \
        git cmake build-essential curl python3 python3-pip python3-venv >/dev/null || true
    log_success "Temel sistem araçları hazır."
fi

# 3. Adım: llama.cpp Klonlama ve FastMTP Yaması
log_step "3/6: llama.cpp indiriliyor ve FastMTP yaması uygulanıyor..."
if [ -d "$LLAMA_DIR/.git" ]; then
    log_info "Mevcut llama.cpp dizini bulundu, güncelleniyor: $LLAMA_DIR"
    cd "$LLAMA_DIR"
    git fetch origin master
    git checkout master
    git pull origin master
else
    log_info "llama.cpp GitHub deposundan klonlanıyor..."
    mkdir -p "$(dirname "$LLAMA_DIR")"
    git clone https://github.com/ggml-org/llama.cpp.git "$LLAMA_DIR"
    cd "$LLAMA_DIR"
fi

# FastMTP yamasını indir
PATCH_TEMP="/tmp/HauhauCS-FastMTP.patch"
log_info "FastMTP yaması Hugging Face üzerinden indiriliyor..."
curl -sSL -o "$PATCH_TEMP" "$PATCH_URL"

# Yamanın durumunu kontrol et
if git apply --check "$PATCH_TEMP" 2>/dev/null; then
    log_info "FastMTP yaması llama.cpp'ye uygulanıyor..."
    git apply "$PATCH_TEMP"
    log_success "FastMTP yaması başarıyla uygulandı."
else
    # Yama zaten uygulanmış mı kontrol et
    if git diff --name-only HEAD | grep -q "qwen35.cpp" || git log -n 5 | grep -qi "FastMTP"; then
        log_warn "FastMTP yaması zaten uygulanmış görünüyor, devam ediliyor."
    else
        log_warn "Yama doğrudan uygulanamadı. Zorla (rejects) deneniyor..."
        git apply --reject "$PATCH_TEMP" || true
    fi
fi

# 4. Adım: llama.cpp CUDA ile Derleme
log_step "4/6: llama.cpp CUDA (GGML_CUDA=ON) desteğiyle derleniyor..."
cd "$LLAMA_DIR"
rm -rf build

log_info "CMake yapılandırması başlatılıyor (Release, CUDA açık)..."
cmake -S . -B build \
    -DGGML_CUDA=ON \
    -DCMAKE_BUILD_TYPE=Release

NPROC_COUNT=$(nproc 2>/dev/null || echo 4)
log_info "$NPROC_COUNT çekirdek ile derleme yapılıyor..."
cmake --build build --config Release -j"$NPROC_COUNT"

if [ -f "$LLAMA_DIR/build/bin/llama-server" ]; then
    log_success "llama-server başarıyla derlendi!"
    "$LLAMA_DIR/build/bin/llama-server" --version || true
else
    log_error "llama-server derlemesi başarısız oldu!"
    exit 1
fi

# 5. Adım: Hugging Face CLI Kurulumu
log_step "5/6: Python Hugging Face CLI aracı yükleniyor..."
# Python PEP 668 uyumluluğu için
PIP_FLAGS="--upgrade"
if python3 -m pip install --help | grep -q -- "--break-system-packages"; then
    PIP_FLAGS="$PIP_FLAGS --break-system-packages"
fi

python3 -m pip install $PIP_FLAGS huggingface_hub >/dev/null 2>&1 || true

# HF indirme komutunu belirle (hf veya huggingface-cli)
HF_CMD=""
if command -v hf &>/dev/null; then
    HF_CMD="hf download"
elif command -v huggingface-cli &>/dev/null; then
    HF_CMD="huggingface-cli download"
elif python3 -m huggingface_hub.cli.core download --help &>/dev/null 2>&1; then
    HF_CMD="python3 -m huggingface_hub.cli.core download"
else
    python3 -m pip install $PIP_FLAGS huggingface_hub
    HF_CMD="huggingface-cli download"
fi

# 6. Adım: Qwen3.8-27B Modellerinin İndirilmesi
log_step "6/6: Model dosyaları kontrol ediliyor ve indiriliyor..."
mkdir -p "$MODELS_DIR"
cd "$MODELS_DIR"

log_info "Hedef Depo: $HF_REPO"
log_info "1. Ana Model: $MODEL_FILE (~31.5 GB)"
log_info "2. FastMTP Draft: $DRAFT_MODEL_FILE (~900 MB)"

# Ana model kontrolü ve indirme
if [ -f "$MODELS_DIR/$MODEL_FILE" ] && [ -s "$MODELS_DIR/$MODEL_FILE" ]; then
    log_success "Ana model dosyası zaten mevcut: $MODEL_FILE"
else
    log_info "Ana model indiriliyor ($MODEL_FILE)... Bu işlem bağlantı hızınıza bağlı olarak birkaç dakika sürebilir."
    $HF_CMD "$HF_REPO" "$MODEL_FILE" --local-dir "$MODELS_DIR"
fi

# Draft model kontrolü ve indirme
if [ -f "$MODELS_DIR/$DRAFT_MODEL_FILE" ] && [ -s "$MODELS_DIR/$DRAFT_MODEL_FILE" ]; then
    log_success "Draft model dosyası zaten mevcut: $DRAFT_MODEL_FILE"
else
    log_info "FastMTP Draft modeli indiriliyor ($DRAFT_MODEL_FILE)..."
    $HF_CMD "$HF_REPO" "$DRAFT_MODEL_FILE" --local-dir "$MODELS_DIR"
fi

echo -e "\n${CYAN}================================================================${NC}"
echo -e "${GREEN}             KURULUM BAŞARIYLA TAMAMLANDI!                    ${NC}"
echo -e "${CYAN}================================================================${NC}"
echo -e "Model dosyaları:\n"
ls -lh "$MODELS_DIR"
echo -e "\n${CYAN}Sunucuyu başlatmak için aşağıdaki yöntemlerden birini kullanabilirsiniz:${NC}"
echo -e "  1. Arka planda başlatmak için  : ${GREEN}./start.sh --daemon${NC} veya ${GREEN}./manage.sh start${NC}"
echo -e "  2. Ön planda (live) başlatmak  : ${GREEN}./start.sh${NC}"
echo -e "  3. Logları takip etmek için    : ${GREEN}./manage.sh logs${NC}"
echo -e "  4. Sunucuyu durdurmak için     : ${GREEN}./stop.sh${NC}"
echo -e "${CYAN}================================================================${NC}"
