# 🚀 Qwen3.8-27B FastMTP Auto-Deploy & Management

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![llama.cpp](https://img.shields.io/badge/llama.cpp-CUDA_Accelerated-green.svg)](https://github.com/ggml-org/llama.cpp)
[![Model](https://img.shields.io/badge/Model-Qwen3.8--27B--FastMTP-blue.svg)](https://huggingface.co/HauhauCS/Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-MTP-GGUF)

Vast.ai ve CUDA destekli GPU sunucularında **Qwen3.8-27B Uncensored (FastMTP)** modelini ve yamalı **llama.cpp** çıkarım sunucusunu **tek bir komutla kurup otomatik başlatan** açık kaynaklı otomasyon aracı.

---

## ☕ Tek Komutla Kurulum ve Başlatma (One-Liner)

Vast.ai veya herhangi bir Ubuntu/Debian GPU makinesine SSH ile bağlandıktan sonra sadece şu komutu yapıştırın ve arkanıza yaslanın:

```bash
curl -sSL https://raw.githubusercontent.com/MATTAM540/qwen-fastmtp/main/bootstrap.sh | bash
```

> **Bu komut tek başına ne yapar?**
> 1. Gerekli tüm sistem bağımlılıklarını (`cmake`, `build-essential`, `cuda` derleme araçları) kurar.
> 2. `llama.cpp`'yi klonlar ve **HauhauCS FastMTP** yamasını uygular.
> 3. `llama.cpp`'yi CUDA donanım hızlandırmasıyla derler.
> 4. Hugging Face üzerinden **Qwen3.8-27B Q8_K_P** ve **FastMTP 32K Draft** modellerini otomatik indirir.
> 5. Sunucuyu arka planda (daemon) **256k Context**, **Flash Attention** ve **Port 8081** ile başlatır!

---

## 📌 Özellikler

- ⚡ **FastMTP (Multi-Token Prediction / Spekülatif Çıkarım)**: HauhauCS MTP yaması ile 3 kata varan token üretim hızı.
- 🎯 **Sıfır Konfigürasyon**: Tek satırlık script tüm süreci uçtan uca tamamlar.
- 🛠️ **Merkezi CLI (`manage.sh`)**: Sunucuyu durdurma, başlatma, durum ve log takibi.
- 🧠 **256K Context Desteği**: Geniş bağlam boyutu (`ctx-size: 262144`), Flash Attention ve Jinja şablon desteği.
- 🔌 **OpenAI Uyumlu API**: OpenCode, Cline, Continue, Cursor ve standart OpenAI SDK'ları ile tam uyumlu API endpoint (`http://0.0.0.0:8081/v1`).

---

## 🖥️ Donanım Gereksinimleri

| Bileşen | Önerilen Minimum | Test Edilen Ortam (Vast.ai) |
| :--- | :--- | :--- |
| **GPU** | NVIDIA A100 (80 GB) / H100 | NVIDIA A100 80GB PCIe |
| **VRAM** | 80 GB | 81,920 MiB |
| **RAM** | 64 GB+ | ~129 GB |
| **Disk** | 50 GB+ boş alan | ~1.3 TB SSD |
| **CUDA** | 12.8+ | CUDA 13.2 / nvcc 12.8 |
| **Sürücü** | 535+ | 595.84 |
| **Python** | 3.10+ | Python 3.12 |

---

## 🎮 Yönetim Komutları (`manage.sh`)

Depoyu manuel klonlayarak yönetmek isterseniz:

```bash
git clone https://github.com/MATTAM540/qwen-fastmtp.git /workspace/qwen-fastmtp
cd /workspace/qwen-fastmtp
```

```bash
./manage.sh start        # Sunucuyu arka planda (daemon) başlatır
./manage.sh start-live   # Sunucuyu terminalde canlı/ön planda başlatır
./manage.sh stop         # Çalışan sunucuyu güvenli şekilde durdurur
./manage.sh restart      # Sunucuyu yeniden başlatır
./manage.sh status       # Sunucu, HTTP sağlık durumu ve GPU VRAM durumunu görüntüler
./manage.sh logs         # Canlı log akışını açar (Ctrl+C ile çıkılır)
```

---

## ⚙️ Yapılandırma (`config.env`)

Varsayılan ayarları değiştirmek isterseniz `config.env.example` dosyasını `config.env` olarak kopyalayabilirsiniz:

```bash
cp config.env.example config.env
nano config.env
```

### Önemli Yapılandırma Parametreleri:

```bash
# Dizinler
WORKSPACE_DIR="/workspace"
LLAMA_DIR="/workspace/llama.cpp"
MODELS_DIR="/workspace/models/qwen38"

# Port ve Ağ
HOST="0.0.0.0"
PORT="8081"

# Çıkarım ve Model Ayarları
CTX_SIZE="262144"           # 256k Context Boyutu
N_GPU_LAYERS="999"          # Tüm katmanlar GPU'ya (Offload)
SPEC_TYPE="draft-mtp"       # FastMTP Spekülatif Çıkarım Modu
SPEC_DRAFT_N_MAX="3"        # Draft spekülatif tahmin adımı
SPEC_DRAFT_NGL="999"
BATCH_SIZE="2048"
UBATCH_SIZE="512"
FLASH_ATTN="on"
REASONING="on"
```

---

## 🌐 API Kullanımı ve Entegrasyon

Sunucu başlatıldığında OpenAI uyumlu standart REST API (`http://<SUNUCU_IP>:8081/v1`) aktif hale gelir.

### cURL ile Test:

```bash
curl http://127.0.0.1:8081/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3.8",
    "messages": [
      {"role": "system", "content": "Sen yardımcı bir yapay zeka asistanısın."},
      {"role": "user", "content": "Merhaba, kendini tanıtır mısın?"}
    ],
    "temperature": 0.7
  }'
```

### Python OpenAI SDK ile Kullanım:

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://<SUNUCU_IP>:8081/v1",
    api_key="sk-no-key-required"  # Yerel sunucuda rastgele bir string yeterlidir
)

response = client.chat.completions.create(
    model="qwen3.8",
    messages=[
        {"role": "user", "content": "Python ile asenkron web scraping nasıl yapılır?"}
    ]
)

print(response.choices[0].message.content)
```

### OpenCode / Continue / Cline Entegrasyonu:
- **Provider**: `OpenAI Compatible`
- **Base URL**: `http://<SUNUCU_IP_VEYA_HOST>:8081/v1`
- **Model Name**: `qwen3.8` veya `default`

---

## 🔍 Proje Dosya Yapısı

```
.
├── bootstrap.sh         # Tek komutla kuran ve başlatan ana betik (curl ... | bash)
├── config.env.example   # Yapılandırma şablonu
├── install.sh           # Otomatik kurulum ve model indirme betiği
├── start.sh             # llama-server başlatma betiği (daemon / foreground)
├── stop.sh              # Güvenli durdurma betiği
├── status.sh            # Sistem, API ve GPU durum kontrolü
├── manage.sh            # Merkezi yönetim CLI arayüzü
├── .gitignore           # Model ve log dosyalarını hariç tutan gitignore
├── LICENSE              # MIT Lisansı
└── README.md            # Detaylı dokümantasyon
```

---

## 🙏 Teşekkürler ve Referanslar

- [llama.cpp (ggml-org)](https://github.com/ggml-org/llama.cpp)
- [HauhauCS Qwen3.8-27B MTP GGUF & Patch](https://huggingface.co/HauhauCS/Qwen3.8-27B-Uncensored-HauhauCS-Aggressive-MTP-GGUF)
- [Qwen Team (Alibaba Cloud)](https://github.com/QwenLM)

---

## 📄 Lisans

Bu proje [MIT Lisansı](LICENSE) altında lisanslanmıştır.
