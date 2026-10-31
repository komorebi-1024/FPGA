# 随行视听西湖——比赛工程提交材料

整理日期：2026-10-31。当前版本：westlake_image（亮度/对比度、真实站点语音与字幕联动版）。
本目录是原工程的独立复制件，正式源工程、素材和当前已验收位流保持原样。
仿真、时序、SRAM实机、Flash写入/独立读回及完全断电冷启动验收记录随包保留。

## 优先使用的三个入口

- TD正式工程：`03_Project/WestLake_AV/src/td_project/HDMI1.4b_Transmitter_v1.0.al`。
- FPGA烧录文件：`05_Build/westlake_image/westlake_image.bit`。
- **实际写入TF卡**：`01_Assets/WestLake_TF_Voice_128MiB.img`。

开发板：安路HX4S20C，器件EG4S20BG256；TD 6.2.1；HDMI 640×480、48kHz双声道。
当前位流与最终Voice镜像的SHA256和验收状态见 `05_Build/westlake_image/verification_status.json`。

## 目录内容

- `03_Project/WestLake_AV/src/`：完整正式源工程、RTL、IP、约束、字模与初始化文件，保持原相对路径。
- `01_Assets/`：24张原图与BMP、两首现用音乐、四站现用语音、字幕元数据及素材来源/署名。
- `04_Sim/`：测试台、必要输入/期望向量、已有验证结果及仿真预览；PNG不是实机截图。
- `05_Build/westlake_image/`：当前位流、时序/资源、源码哈希、Flash校验及用户实机验收记录。
- `00_Docs/`：当前图像调节、语音、音乐、转场开发说明及评分对照。
- `tools/`：现用素材生成/打包/校验、编译、仿真和下载脚本。
- 根目录CMD：原工程的运行入口。

`WestLake_TF_128MiB.img`与`WestLake_TF_Audio_128MiB.img`是素材打包和独立校验所用的基础依赖，
并非本次上板的推荐写卡文件。当前完整功能使用Voice镜像；它包含24张图片、两首音乐、四站语音。
旧位流、历史备份、整套参考例程、早期交接ZIP及未采用的配音试听没有打包。
正式src目录整体保留，其中原厂参考模块/初始化文件不得随意删除或冒充全部由作者独立编写。

## 运行与复现

将最终Voice镜像用整盘镜像工具写入专用TF卡（会覆盖目标卡），板卡断电后插卡。
用安路TD/BitWriter核对器件并先做JTAG/SRAM下载，确认后可写SPI配置Flash并Verify。
不要把IMG文件仅作为普通文件复制进卡，也不要把BIT写进TF卡。

目标电脑需自行安装TD、下载器驱动和写卡工具；重新编译/制作素材还需Python 3及Pillow。
字模重新生成使用Windows微软雅黑与Consolas，已有HEX已随工程保留。
仿真工具未随包分发；使用原run_sim.py时，将Icarus的iverilog.exe、vvp.exe及所需运行文件
准备在 `tools/iverilog/bin/`（与原工程约定一致）。本包不含TD安装包、工具运行时或许可证。
已制作WAV可直接重打包，不需要联网重新合成语音；在线TTS生成及旧试听脚本不在本工程提交包内。

- `01_Run_Simulation.cmd`：生成校验向量并执行已有自检（需配置Icarus与Pillow）。
- `02_Build_Project.cmd`：编译当前westlake_image目标；新电脑可设置WESTLAKE_TD。
- `03_Rebuild_Assets.cmd`：从现有图片重建基础/音乐镜像。
- `04_Pack_Audio.cmd`：从现有音乐重建Audio镜像。
- `06_Pack_Voice.cmd`：生成语音字幕字模，再生成/校验最终Voice镜像。
- `python tools/download_audio.py --build westlake_image --program`：检查源码一致性后SRAM下载。

运行/下载无需先重做素材或重新编译。已有脚本会保留原本的路径和校验逻辑；
如解压工具不保留文件时间，下载脚本的时间检查可能拒绝，使用Windows标准解压保留时间，
或在BitWriter图形工具手动选择经SHA256核验的当前位流。

## 按键

KEY1复位。菜单外KEY2进离站，KEY3短按松开切歌；KEY3长按约1秒开关图像设置。
设置内KEY3短按选择、KEY2调整/执行，DEFAULT恢复亮度0、对比度100%。
SW1频谱；SW2持续测试音，正常播放时关闭。首站等待5秒供HDMI接收设备锁定；
语音播完后再停3秒自动离站，KEY2可提前离站并恢复音乐。

## 验证边界与其他提交材料

本次仅复制、整理、哈希核对和压缩，不重新编译或操作板卡；已有实机反馈来源见验收JSON。
测试记录包含此前各阶段最近一次结果，不表示打包当天重跑全部测试。
`image_config_cdc_old_repro.log`是修复前预期失败的回归证据，不是当前方案的失败。
整曲曲尾硬件循环和长时稳定运行仍未完成验收。

本目录是工程技术材料包，不代替赛事指定模板的正式报告、报名材料或实机演示视频；
这些应按报名平台要求另行提供，未用仿真图或虚构材料代替。
照片、音乐、语音及原厂IP保留各自来源/版权说明，不统一重新授权。

包内 `提交文件SHA256.json` 和 `SHA256SUMS.txt` 可用于逐文件校验，
`打包校验报告.json` 记录本次复制、工程引用及压缩包内容检查结果。
