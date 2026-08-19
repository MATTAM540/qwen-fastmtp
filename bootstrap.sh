#!/usr/bin/env bash
# ==============================================================================
# Qwen3.8-27B FastMTP Tek Komutla Otomatik Kurulum ve Başlatma (One-Liner Bootstrap)
# Kullanım:
#   curl -sSL https://raw.githubusercontent.com/MATTAM540/qwen-fastmtp/main/bootstrap.sh | bash
# ==============================================================================
set -euo pipefail

# Renkler
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

export DEBIAN_FRONTEND=noninteractive

echo -e "${CYAN}================================================================${NC}"
echo -e "${GREEN}    🚀 Qwen3.8-27B FastMTP Tek Tıkla Tam Otomatik Kurulum     ${NC}"
echo -e "${CYAN}================================================================${NC}"
echo -e "${YELLOW}Arkana yaslan, tüm sistem hazırlanıp model sunucusu başlatılacak...${NC}"
echo -e "${CYAN}================================================================${NC}"

WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
REPO_DIR="$WORKSPACE_DIR/qwen-fastmtp"
LLAMA_DIR="$WORKSPACE_DIR/llama.cpp"
MODELS_DIR="$WORKSPACE_DIR/models/qwen38"
LOG_FILE="$WORKSPACE_DIR/qwen.log"
PID_FILE="$WORKSPACE_DIR/llama-server.pid"

# 1. Dizin oluşturma
mkdir -p "$WORKSPACE_DIR" "$MODELS_DIR" 2>/dev/null || sudo mkdir -p "$WORKSPACE_DIR" "$MODELS_DIR"
cd "$WORKSPACE_DIR"

# 2. Sistem Paketleri
echo -e "\n${CYAN}==>${NC} ${BLUE}[1/5] Sistem araçları ve derleme paketleri kuruluyor...${NC}"
SUDO_CMD=""
if [ "$EUID" -ne 0 ] && command -v sudo &>/dev/null; then
    SUDO_CMD="sudo"
fi

if command -v apt-get &>/dev/null; then
    $SUDO_CMD apt-get update -y -qq || true
    $SUDO_CMD apt-get install -y -qq git cmake build-essential curl python3 python3-pip python3-venv >/dev/null || true
fi

# 3. llama.cpp Klonlama & FastMTP Yaması
echo -e "\n${CYAN}==>${NC} ${BLUE}[2/5] llama.cpp indiriliyor ve FastMTP yaması uygulanıyor...${NC}"
if [ -d "$LLAMA_DIR/.git" ]; then
    cd "$LLAMA_DIR"
    git fetch origin master -q
    git checkout master -q
    git pull origin master -q
else
    git clone https://github.com/ggml-org/llama.cpp.git "$LLAMA_DIR" -q
    cd "$LLAMA_DIR"
fi

PATCH_URL="https://huggingface.co/HauhauCS/Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-MTP-GGUF/resolve/main/HauhauCS-FastMTP-llama.cpp.patch"
curl -sSL -o /tmp/HauhauCS-FastMTP.patch "$PATCH_URL"

if git apply --check /tmp/HauhauCS-FastMTP.patch 2>/dev/null; then
    git apply /tmp/HauhauCS-FastMTP.patch
    echo -e "${GREEN}✔ FastMTP yaması uygulandı.${NC}"
else
    echo -e "${YELLOW}ℹ FastMTP yaması zaten uygulanmış veya atlandı.${NC}"
fi

# 4. CUDA ile Derleme
echo -e "\n${CYAN}==>${NC} ${BLUE}[3/5] llama.cpp CUDA (Release) ile derleniyor...${NC}"
cd "$LLAMA_DIR"
rm -rf build
cmake -S . -B build -DGGML_CUDA=ON -DCMAKE_BUILD_TYPE=Release >/dev/null
NPROC_COUNT=$(nproc 2>/dev/null || echo 4)
cmake --build build --config Release -j"$NPROC_COUNT" >/dev/null

if [ -f "$LLAMA_DIR/build/bin/llama-server" ]; then
    echo -e "${GREEN}✔ llama-server CUDA derlemesi hazır.${NC}"
else
    echo -e "${RED}✖ llama-server derlenemedi!${NC}"
    exit 1
fi

# 5. Hugging Face CLI ve Model İndirme
echo -e "\n${CYAN}==>${NC} ${BLUE}[4/5] Model dosyaları Hugging Face'den indiriliyor...${NC}"
PIP_FLAGS="--upgrade"
if python3 -m pip install --help 2>&1 | grep -q -- "--break-system-packages"; then
    PIP_FLAGS="$PIP_FLAGS --break-system-packages"
fi
python3 -m pip install $PIP_FLAGS huggingface_hub >/dev/null 2>&1 || true

HF_CMD="huggingface-cli download"
if command -v hf &>/dev/null; then
    HF_CMD="hf download"
fi

HF_REPO="HauhauCS/Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-MTP-GGUF"
MODEL_FILE="Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-Q8_K_P.gguf"
DRAFT_MODEL_FILE="Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-FastMTP-32K.gguf"

cd "$MODELS_DIR"
if [ ! -s "$MODELS_DIR/$MODEL_FILE" ]; then
    echo -e "${BLUE}Ana model indiriliyor (~31.5 GB)...${NC}"
    $HF_CMD "$HF_REPO" "$MODEL_FILE" --local-dir "$MODELS_DIR"
fi

if [ ! -s "$MODELS_DIR/$DRAFT_MODEL_FILE" ]; then
    echo -e "${BLUE}FastMTP Draft model indiriliyor (~900 MB)...${NC}"
    $HF_CMD "$HF_REPO" "$DRAFT_MODEL_FILE" --local-dir "$MODELS_DIR"
fi

# 6. Eski Sunucu Varsa Kapat ve Yenisini Başlat
echo -e "\n${CYAN}==>${NC} ${BLUE}[5/5] Qwen3.8-27B Sunucusu Arka Planda Başlatılıyor...${NC}"
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE" 2>/dev/null || true)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        kill -9 "$OLD_PID" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
fi

PORT="${PORT:-8081}"
HOST="${HOST:-0.0.0.0}"

nohup "$LLAMA_DIR/build/bin/llama-server" \
  --model "$MODELS_DIR/$MODEL_FILE" \
  --model-draft "$MODELS_DIR/$DRAFT_MODEL_FILE" \
  --spec-type draft-mtp \
  --spec-draft-n-max 3 \
  --spec-draft-ngl 999 \
  --ctx-size 262144 \
  --n-gpu-layers 999 \
  --split-mode none \
  --flash-attn on \
  --batch-size 2048 \
  --ubatch-size 512 \
  --parallel 1 \
  --jinja \
  --reasoning on \
  --host "$HOST" \
  --port "$PORT" \
  > "$LOG_FILE" 2>&1 &

NEW_PID=$!
echo "$NEW_PID" > "$PID_FILE"

sleep 3

PUBLIC_IP=$(curl -s -m 3 https://ifconfig.me 2>/dev/null || echo "SUNUCU_IP")

echo -e "\n${CYAN}================================================================${NC}"
echo -e "${GREEN}       🎉 TEBRİKLER! QWEN3.8-27B FASTMTP HAZIR VE ÇALIŞIYOR     ${NC}"
echo -e "${CYAN}================================================================${NC}"
echo -e "Sunucu PID      : ${GREEN}$NEW_PID${NC}"
echo -e "Yerel API       : ${GREEN}http://127.0.0.1:$PORT/v1${NC}"
echo -e "Dış Erişim API  : ${GREEN}http://$PUBLIC_IP:$PORT/v1${NC}"
echo -e "Log Dosyası     : ${BLUE}$LOG_FILE${NC}"
echo -e ""
echo -e "${YELLOW}Nasıl takip edebilirsiniz?${NC}"
echo -e "  Logları canlı izlemek için : ${CYAN}tail -f $LOG_FILE${NC}"
echo -e "  Sunucuyu durdurmak için    : ${CYAN}kill $(cat $PID_FILE 2>/dev/null || echo '<PID>')${NC}"
echo -e "${CYAN}================================================================${NC}"
