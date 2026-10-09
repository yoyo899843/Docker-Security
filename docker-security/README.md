# Docker 安全練習：Command Injection → 容器逃脫

一個**刻意做壞**的教學靶場，用來示範三個常見錯誤疊在一起時會發生什麼事：

1. 程式把使用者輸入直接丟進 shell → **command injection（遠端命令執行）**
2. 容器開了 `--privileged`
3. 容器把 host 的 `/` 掛了進來

單獨一個就很糟，三個加起來＝攻擊者從一個網頁輸入框，一路拿到**整台主機**。

---

## ⚠️ 安全須知（上課前先讀）

- 這個靶場會掛載 host 的根目錄並以 privileged 執行。**逃脫之後碰到的是「跑這個容器的那台機器」的真實檔案系統。**
- **只能在可以隨時丟棄的虛擬機裡執行**（VirtualBox / Hyper-V / 雲端臨時主機 / 一次性開發機）。
- 不要在自己的主力電腦、不要在共用主機、更不要在任何正式環境執行。
- port 已經綁定在 `127.0.0.1`，不會曝露到區域網路。請維持這個設定。
- 練習完請務必 `docker compose -f docker-compose.vulnerable.yml down` 收掉。

---

## 檔案

```
docker-security/
├── app/                          # 刻意有漏洞的網頁應用
│   ├── app.py                    #   command injection 就在這裡
│   ├── templates/index.html
│   ├── requirements.txt
│   └── Dockerfile
├── docker-compose.vulnerable.yml # 錯誤示範：privileged + 掛載 /
├── docker-compose.hardened.yml   # 修正示範：拿掉逃脫條件
└── README.md
```

---

## 第一關：找出 command injection

啟動靶場：

```bash
docker compose -f docker-compose.vulnerable.yml up -d --build
```

打開 <http://127.0.0.1:8080>，這是一個「網路診斷工具」，會對你輸入的主機 ping 兩次。

伺服器端的程式長這樣（`app/app.py`）：

```python
cmd = "ping -c 2 " + host          # 直接字串拼接
subprocess.check_output(cmd, shell=True, ...)
```

`shell=True` 會把整串交給 `/bin/sh` 解析，而 shell 認得 `;`、`&&`、`|`、`$()` 這些控制字元。試試在輸入框打：

| 輸入 | 結果 |
|------|------|
| `127.0.0.1; id` | 先 ping，再執行 `id`，看到容器內的使用者身分 |
| `127.0.0.1; uname -a` | 看到容器的核心資訊 |
| `; cat /etc/passwd` | 不 ping，直接讀檔 |

**觀念**：只要使用者輸入會進到 shell，而你沒有嚴格處理，攻擊者就能執行任意指令。這就是 OWASP 的 Command Injection。

---

## 第二關：確認這是一個「開了外掛」的容器

既然能執行任意指令，先偵查環境。在輸入框打：

```
; ls -la /
```

你會看到根目錄裡多了一個 `/host` —— 那就是 compose 掛進來的 host 根目錄。再打：

```
; cat /proc/1/status
```

注意看 `CapEff`（有效權限）那一行。正常容器會是一串被砍過的權限；因為我們開了 `privileged`，這裡會是滿滿的 `0000003fffffffff`，代表幾乎所有 Linux capabilities 都在。

**觀念**：`privileged: true` ＝ 關掉大部分核心層級的隔離。容器裡的 root 幾乎等於 host 的 root。

---

## 第三關：逃脫到 host

因為 host 的 `/` 就掛在 `/host`，根本不需要什麼高深的 kernel exploit —— 直接讀寫就是了。

**讀 host 的機密檔案**（輸入框）：

```
; cat /host/etc/shadow
```

```
; ls -la /host/root
```

**在 host 上留下痕跡**，證明真的寫得進去：

```
; touch /host/tmp/pwned_by_student
```

然後在 host（虛擬機）上確認：

```bash
ls -l /tmp/pwned_by_student     # 真的出現了
```

到這裡，攻擊者已經能讀 host 上任何檔案、改開機設定、植入排程或 SSH 金鑰。**容器逃脫完成。**

> 進階（選講）：即使沒有掛 `/`，光是 `privileged` 也能逃脫（例如透過 cgroup `release_agent`、或直接讀寫 host 的裝置節點 `/dev/sda`）。這裡用「掛 `/`」是最直觀的版本，先讓學生看懂「掛載 + 權限」的因果。

收掉靶場：

```bash
docker compose -f docker-compose.vulnerable.yml down
rm -f /tmp/pwned_by_student       # 在虛擬機上清掉剛剛的痕跡
```

---

## 第四關：怎麼修

這題有**兩層**要修，對應資安的「縱深防禦」：應用層把洞補掉，容器層就算補不乾淨也不讓它能逃脫。

### 1. 修 code（根因）——不要把輸入交給 shell

```python
import ipaddress, subprocess

# (1) 先驗證輸入真的是一個 IP / 主機名，不符就拒絕
host = request.form.get("host", "")
ipaddress.ip_address(host)        # 不是合法 IP 就丟例外

# (2) 用參數陣列，不要 shell=True；shell 的控制字元就失效了
output = subprocess.check_output(
    ["ping", "-c", "2", host],    # 陣列形式，host 永遠被當成單一參數
    stderr=subprocess.STDOUT, timeout=15,
)
```

重點：**用參數陣列（list）取代字串**，並且**關掉 `shell=True`**。再加上輸入驗證（allowlist）當第二道關卡。

### 2. 修容器設定（縮小爆炸半徑）

對照 `docker-compose.hardened.yml`：

| 錯誤設定 | 改法 |
|----------|------|
| `privileged: true` | 移除；真的需要個別能力時才用 `cap_add` 精準開 |
| `volumes: - /:/host` | 絕不掛 host 根目錄；只掛該服務真正需要的資料夾，並加 `:ro` |
| （預設可寫根檔案系統） | `read_only: true` + 需要寫的地方用 `tmpfs` |
| （預設保留一堆 capabilities） | `cap_drop: [ALL]` |
| （預設可提權） | `security_opt: ["no-new-privileges:true"]` |

用修好的版本跑跑看，再試一次第三關的指令：

```bash
docker compose -f docker-compose.hardened.yml up -d --build
```

- `; ls /host` → 沒有 `/host` 了（沒掛進來）
- `; cat /proc/1/status` → `CapEff` 幾乎全 0
- `; touch /` 之類的寫入 → 根檔案系統唯讀，失敗

（注意：hardened 版本**故意保留** code 的 injection，讓學生看到「即使 code 還有洞，良好的容器設定也能把損害關在容器裡」。實務上兩層都要修。）

---

## 帶走的三句話

1. **使用者輸入永遠不要直接進 shell** —— 用參數陣列，別用 `shell=True` 拼字串。
2. **`--privileged` 幾乎等於把 host root 交出去** —— 預設不要用，需要什麼能力就精準 `cap_add`。
3. **掛載範圍愈小愈好** —— 絕不掛 `/`，能唯讀就唯讀。

> 延伸閱讀：OWASP Command Injection、Docker `--privileged` 文件、CIS Docker Benchmark。
