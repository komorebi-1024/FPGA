# TF 卡镜像与电脑素材文件名

镜像使用 FAT 的短文件名，写入后 Windows 显示的名字和 TF_BMP 文件夹稍有不同，内容完全相同。

|站点|电脑 BMP|卡内文件名|
|---|---|---|
|少年宫断桥|01_duanqiao.bmp|01BRIDGE.BMP|
|涌金门|02_yongjinmen.bmp|02YONGJI.BMP|
|雷峰塔|03_leifeng.bmp|03LEIFEN.BMP|
|岳庙|04_yuemiao.bmp|04YUEMIA.BMP|

按教程整盘写入 WestLake_TF_128MiB.img。FPGA 使用专用目录中的连续扇区地址，不按上述文件名搜索；写入后不要手工替换或删除卡内文件。更换素材请重新生成镜像再写卡。
