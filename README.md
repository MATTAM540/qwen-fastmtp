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
> 2. Yama ile uyumlu sabit `llama.cpp` commit'ini (`4df29be4`) klonlar ve **HauhauCS FastMTP** yamasını uygular.
> 3. `llama.cpp`'yi CUDA donanım hızlandırmasıyla derler.
> 4. Hugging Face üzerinden **Qwen3.8-27B Q8_K_P** ve **FastMTP 32K Draft** modellerini otomatik indirir.
> 5. Sunucuyu arka planda (daemon) **256k Context**, **Flash Attention** ve **API key koruması** ile başlatır.
> 6. Hazır gelen `cloudflared` ile hesapsız geçici Quick Tunnel açar; sonunda API key ve public linki yazdırır.

Kurulum, llama.cpp ve Hugging Face dosyalarının sürümlerini sabitler; patch ile iki GGUF dosyasının SHA-256 değerlerini kontrol eder. Yamayı temiz kaynakta uygular veya önceden tam uygulanmışsa bunu doğrular. Commit uyuşmazsa ya da yama kısmen uygulanmışsa derlemeyi durdurur; kısmi yamayla devam etmez.

---

## 📌 Özellikler

- ⚡ **FastMTP (Multi-Token Prediction / Spekülatif Çıkarım)**: HauhauCS MTP yaması ile 3 kata varan token üretim hızı.
- 🎯 **Sıfır Konfigürasyon**: Tek satırlık script tüm süreci uçtan uca tamamlar.
- 🛠️ **Merkezi CLI (`manage.sh`)**: Sunucuyu durdurma, başlatma, durum ve log takibi.
- 🧠 **256K Context Desteği**: Geniş bağlam boyutu (`ctx-size: 262144`), Flash Attention ve Jinja şablon desteği.
- 🔌 **OpenAI Uyumlu API**: OpenCode, Cline, Continue, Cursor ve standart OpenAI SDK'ları ile tam uyumlu API endpoint (`http://127.0.0.1:8081/v1`).
- 🔐 **Otomatik API Key**: İlk başlatmada rastgele ve güçlü bir key üretir; kullanıcıdan key istemez.
- ☁️ **Geçici Cloudflare Quick Tunnel**: Hesap veya domain gerektirmeden public `trycloudflare.com` adresi açabilir.

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
./manage.sh start-public # Sunucu + hesapsız geçici Cloudflare Tunnel
./manage.sh tunnel-stop  # Geçici Tunnel'ı durdurur
./manage.sh tunnel-status # Public linki ve Tunnel durumunu gösterir
./manage.sh api-key      # Otomatik üretilen API key'i gösterir
```

`start-public` komutu tamamlandığında AI context, model adı, public link, OpenAI Base URL ve API key tek bir kopyalanabilir JSON bilgi kutusunda yazdırılır. Tek seferlik adresi kaydedin; Tunnel durduğunda veya yeniden başlatıldığında adres değişebilir.

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
LLAMA_CPP_COMMIT="4df29be4f4c3673f428170fda944a5b19f743bb8"
HF_REVISION="993a5971fda8f30dd1b7eb2654792ba4415c7460"
MODELS_DIR="/workspace/models/qwen38"

# Port ve Ağ (Quick Tunnel için loopback önerilir)
HOST="127.0.0.1"
PORT="8081"

# API key dosyası (ilk başlatmada otomatik oluşturulur)
API_KEY_FILE="/workspace/llama-api.key"
MODEL_NAME="qwen3.8"

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

Sunucu başlatıldığında OpenAI uyumlu standart REST API (`http://127.0.0.1:8081/v1`) aktif hale gelir; `start-public` sonrası dış erişim için yazdırılan Quick Tunnel adresini kullanın.

### cURL ile Test:

```bash
curl http://127.0.0.1:8081/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(./manage.sh api-key)" \
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
    base_url="https://<QUICK_TUNNEL_ADRESI>/v1",
    api_key="<./manage.sh api-key çıktısı>"
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
- **Base URL**: `https://<QUICK_TUNNEL_ADRESI>/v1`
- **API Key**: `./manage.sh api-key` çıktısı
- **Model Name**: `qwen3.8` veya `default`

### Hesapsız Geçici Cloudflare Tunnel

Ardından tek komutla llama sunucusunu ve geçici tunnel'ı başlatın:

```bash
./manage.sh start-public
```

Bu yöntem Cloudflare hesabı/domain gerektirmez ve rastgele bir `https://*.trycloudflare.com` adresi üretir. Geliştirme/test amaçlıdır; adres kalıcı değildir, Quick Tunnel'lar 200 eşzamanlı istekle sınırlıdır ve SSE/streaming desteklemez.

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
├── tunnel.sh            # Hesapsız geçici Cloudflare Quick Tunnel yönetimi
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
