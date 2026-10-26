# 随行视听西湖导览终端（WestLake AV）

基于 **安路 HX4S20C 开发板（FPGA 型号 EG4S20BG256）** 的观光车随行视听系统，用于 **2026 FPGA 创新设计竞赛 · 安路赛道 · 课题一**。

系统从 TF 卡读取西湖四个站点的照片与区间宣传图，通过 HDMI 输出 640×480 画面，叠加动态导览字幕，并输出 48 kHz 到站提示音。

---

## 当前状态

| 阶段 | 状态 |
|---|---|
| 代码实现（RTL + 脚本 + 测试台） | ✅ 完成 |
| Icarus 功能仿真（读图/场景/字幕/音频） | ✅ 通过 |
| TD 综合/布局布线/时序 | ✅ 通过（SWNS ≈ +0.25 ns） |
| **上板实测**（HDMI 画面、声音、按键、**Flash 固化冷启动**） | ⏳ 待验证 |

> 说明：下面列的功能均为「代码已实现并通过仿真/编译」；**真板子的 HDMI 声画、TF 卡兼容性、Flash 固化与断电重启尚未实测**，请勿在报告里写成已完成。

---

## 当前已实现的功能（P0）

| 功能 | 说明 |
|---|---|
| 读图显示 | TF 卡读取 24 张标准 BMP（4 站点图 + 20 宣传图），SPI 读取 + BMP 解析 + SDRAM 双缓冲 + HDMI 显示 |
| 场景切换 | **站点模式 / 区间模式** 双模式状态机，单键 `key1` 推进 |
| 站点模式 | 显示对应站点图 + 到站提示音 + 字幕**打字机逐字进入**，停留 5s（可按键提前发车） |
| 区间模式 | 5 张宣传图 1s 一张**无限循环**，按 `key1` 到下一站 |
| 动态字幕 | 导览语逐字打字机（8 字/秒，参数可调）+ 站名/下一站/状态栏实时叠加 |
| 到站提示音 | FPGA 内部 DDS 生成 48 kHz 三角波提示音，只在进站时响（`publish_kind` 区分） |
| OSD 叠加 | 中文导览字幕 + 状态栏（模式/站号/运行秒表）+ 路线进度条 |
| 稳定运行 | 时序约束通过，位流可生成；**Flash 固化与断电冷启动待上板实测** |

四个站点：**少年宫（断桥）→ 涌金门 → 雷峰塔 → 岳庙（跨虹桥）**，循环。

---

## 硬件与工具链

- **开发板**：HX4S20C（竞赛板）
- **FPGA**：EG4S20BG256
- **工具**：安路 Tang Dynasty（TD）6.2.1
- **语言**：Verilog
- **仿真**：Icarus Verilog（已打包在 `tools/iverilog/`）

**时钟域**（输入 50 MHz 晶振，经 PLL）：

| 时钟 | 频率 | 用途 |
|---|---|---|
| `sd_card_clk` | 100 MHz | TF 卡 SPI、场景控制、媒体读取 |
| `ext_mem_clk` | 50 MHz | SDRAM 控制器 |
| `video_clk` | 25 MHz | 视频像素、OSD、音频 |
| `hdmi_5x_clk` | 125 MHz | HDMI TMDS 串行化 |

---

## 系统架构

```
TF卡(镜像) → SPI读扇区 → wl_media_reader(读目录+BMP解析) → SDRAM双缓冲
                                    ↑ wl_scene_ctrl(场景状态机)
SDRAM读帧 → wl_video_commit(帧边界切缓冲) → wl_osd(字幕叠加) → HDMI发射(带PCM音频)
                                             ↑ wl_pcm_audio(48kHz提示音)
按键 → wl_key_debounce(消抖) ─→ wl_scene_ctrl
```

### 核心模块（`03_Project/WestLake_AV/src/user_source/hdl_source/`）

| 模块 | 作用 |
|---|---|
| `top_tf_hdmi_audio.v` | 顶层，连接所有子模块 |
| `westlake/wl_media_reader.v` | 读固定扇区目录（24 条），校验 BMP 头，逐像素送出 |
| `westlake/wl_scene_ctrl.v` | **站点/区间场景状态机**（核心控制） |
| `westlake/wl_video_commit.v` | 双缓冲帧提交 + 跨时钟域握手 + 提示音触发 |
| `westlake/wl_osd.v` | 字幕叠加 + 打字机效果 + 状态栏 |
| `westlake/wl_pcm_audio.v` | 48 kHz PCM 音频源（到站提示音） |
| `westlake/wl_reset_sync.v` / `wl_key_debounce.v` | 复位同步 / 按键消抖 |
| `SD/sd_card_bmp.v` | 胶合层：媒体读取 + 场景控制 + 原厂 SD SPI 传输 |

> `westlake/wl_playlist_ctrl.v` 是早期轮播控制器的遗留代码，现已被 `wl_scene_ctrl` 取代。

### 场景状态机

```
WAIT_CATALOG → STATION(站点图+提示音+打字机, 停5s) ──自动/按键──→ SECTION(5张宣传图1s循环)
                     ↑                                                  │
                     └──────────── 按 key1 到下一站（0→1→2→3→0 回绕）──────┘
```

---

## 目录结构

```
WestLake_AV/
├── 00_Docs/          # 教程、规划、验收文档
├── 01_Assets/        # 原图(JPG)、标准BMP、磁盘镜像、素材配置
│   ├── Original/     # 原始照片（4 站点 + 20 宣传图）
│   ├── TF_BMP/       # 生成的标准 640×480 BMP
│   └── WestLake_TF_128MiB.img   # 生成的磁盘镜像
├── 02_Examples/      # 赛题 43 个参考例程（参考资料，非本工程代码）
├── 03_Project/
│   ├── WestLake_AV/  # ★ 正式工程（源码）
│   └── 00_Baseline/  # 参考基线工程
├── 04_Sim/           # Icarus 仿真测试台 + 结果
├── 05_Build/         # TD 编译产物（westlake.bit、时序/资源报告）
├── tools/            # 脚本（prepare_assets.py、run_td.py 等）+ iverilog
├── 01_Run_Simulation.cmd   # 跑仿真
├── 02_Build_Project.cmd    # 编译生成位流
└── 03_Rebuild_Assets.cmd   # 重新生成 BMP/字模/镜像
```

---

## 快速开始

### 1. 准备素材与镜像（换图时才需要）

```bash
# 替换 01_Assets/Original/ 里的 JPG（保持文件名和顺序）
# 然后双击：
03_Rebuild_Assets.cmd
```
生成：`TF_BMP/*.bmp`、`captions.hex`、`ascii_font.hex`、`WestLake_TF_128MiB.img`。

### 2. 写 TF 卡镜像

用 **Win32 Disk Imager** 把 `01_Assets\WestLake_TF_128MiB.img` 整盘写入 TF 卡（**不是**拖图片进去）。

> FPGA 不实现通用 FAT32 文件系统，只读固定扇区 LBA 2056 的目录 + 连续扇区，所以必须整盘刷镜像。

### 3. 编译生成位流

```bash
02_Build_Project.cmd
```
成功后 `05_Build/westlake/westlake.bit`，状态为 `FLOW_COMPLETE; CONSTRAINED_TIMING_PASS`。

> 若报 "TD not found"，改 `tools/run_td.py` 里 `exe=` 的默认路径，或设置环境变量 `WESTLAKE_TD`。

### 4. 上板下载

1. 断电插 TF 卡、连 HDMI（带音箱的电视/显示器）、连 JTAG 下载器，上电；
2. TD 下载工具扫描到 `EG4S20BG256`；
3. 选 `westlake.bit` 做 SRAM 临时下载验证；
4. 测通后固化到板载 Flash（上电自动运行）。

---

## SD 卡目录格式（LBA 2056）

| 字节 | 内容 |
|---|---|
| 0–7 | 魔数 `WLAV0002` |
| 8 | 图片总数 = 24 |
| 9 | 位深 = 24 |
| 10–13 | 宽 640 / 高 480 |
| 14 | 站点数 = 4 |
| 15 | 每区间宣传数 = 5 |
| 16–399 | 24 条记录，每条 16 字节 `{起始扇区, 长度, 序号, CRC32}` |

- 条目 0–3 = 4 张站点图（绑定站号 0–3）
- 条目 4–23 = 20 张宣传图（区间 N 对应条目 `4+N*5` ~ `4+N*5+4`）

BMP 要求：640×480、24 位、无压缩、正高度（bottom-up）、54 字节头、每张 921654 字节。

---

## 仿真

```bash
01_Run_Simulation.cmd   # 或 python tools/run_sim.py [media|osd|scene|...]
```

测试台（`04_Sim/tb_*.sv`）：
- `tb_media` — 24 张图逐像素比对 + 4 种错误检测
- `tb_scene` — 场景状态机完整循环 + 回绕
- `tb_osd` — 字幕/打字机逐像素比对
- `tb_audio` / `tb_control` / `tb_framebuffer` / `tb_key` / `tb_status`

---

## 关键参数（可调）

| 参数 | 位置 | 默认值 |
|---|---|---|
| 站点停留 | `wl_scene_ctrl.v` `STATION_DWELL_MS` | 5000（5s） |
| 宣传图停留 | `wl_scene_ctrl.v` `PROMO_DWELL_MS` | 1000（1s） |
| 打字机速度 | `wl_osd.v` `TYPE_CHAR_MS` | 125（8 字/秒） |
| 站点数 | `wl_scene_ctrl.v` `NUM_STATIONS` | 4 |
| 每区间宣传数 | `wl_scene_ctrl.v` `PROMOS_PER_INTERVAL` | 5 |

---

## 资源与时序（当前）

| 项 | 值 |
|---|---|
| LUT | 25% |
| BRAM | ~80%（注意余量） |
| DSP | 3% |
| 时序 | SWNS ≈ +0.25 ns（通过） |

> 后续做转场特效 / I2S / 音频可视化等二期功能时，**新增逻辑尽量放 25 MHz `video_clk` 域**，避免再挤占已经很紧的 100 MHz `sd_card_clk` 域。
