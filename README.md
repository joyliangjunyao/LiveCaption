# 中文版（LiveCaption）

LiveCaption 是一款面向 macOS 的本地实时字幕工具，支持电脑音频与麦克风独立或组合采集，自动识别语言并按需翻译。基于 Whisper 和 Metal 本地运行，提供毛玻璃悬浮窗、可调位置、尺寸、透明度与字号，以及带时间戳的字幕记录导出，优先保护隐私并支持离线使用。

macOS 15+ 原生实时字幕、翻译与录音悬浮窗。支持电脑音频、麦克风或双路同时采集。

## 构建与启动

需要 macOS 15+、Swift 6+（Xcode 或 Command Line Tools）和 CMake。
首次使用开发工具须先完成 Apple 的安装及许可证流程。Apple Intelligence
总结另外需要受支持的系统、硬件和已启用的本机模型。项目包含 vendor 源码，
无需另行初始化子模块。当前发布脚本构建本机架构，并非通用二进制。

```bash
./scripts/build-app.sh
open dist/LiveCaption.app
swift test
```

首次使用时，macOS 会分别请求麦克风及屏幕与系统音频录制权限。更改系统音频权限后可能需要重新启动应用。

开发构建使用 ad-hoc 签名及固定 identifier；不保证系统在更新后保留 TCC 授权。
如果旧版本留下失效权限记录，可按需执行以下命令（会清除已有授权）：

```bash
tccutil reset Microphone com.wishyoujoy.livecaption
tccutil reset ScreenCapture com.wishyoujoy.livecaption
```

随后重新打开应用并授权一次。

## 当前能力

- whisper.cpp + Metal 本地连续识别，直接从音频自动判断语言
- Apple Translation 离线/系统语言包翻译，可选择十种目标语言
- 电脑音频与麦克风独立管线，可单选或组合
- 独立录音启停；双路模式分别保存电脑音频和麦克风 WAV
- 文本按录音时间轴导出；可选本地说话人区分，并按发言轮次切分实时字幕
- 停止录音后可用 Apple Intelligence 生成本地总结；不可用时自动生成基础提取式总结
- 毛玻璃置顶窗、跨桌面空间、自由拖动；控制栏会随宽度自动换行，右下角手柄可随时缩放
- 可选择仅字幕、字幕加翻译或仅翻译
- 可调整透明度以及原文、译文字号
- 无标题栏悬浮窗，只驻留在顶部菜单栏，不显示在 Dock
- 鼠标进入字幕框时自动展开控制栏，移出后自动隐藏
- 可设置无字幕多久后自动隐藏整个浮窗；新字幕出现时自动淡入唤醒

录音默认保存在“文稿/LiveCaption”，可从顶部菜单或设置中更改。每次录音会创建独立的时间命名文件夹，其中包含音频、`字幕记录.txt`，以及启用总结后生成的 `录音总结.md`。说话人模型首次启用时需要联网下载，之后在本机运行。

首次开始识别时会下载所选多语言模型。平衡模型约 181 MB；高精度 `large-v3-turbo-q5_0` 模型约 547 MB。下载后模型保存在 `~/Library/Application Support/LiveCaption/Models`，后续可完全离线运行。

## 开源与发布

本项目自有代码使用 MIT 许可证，第三方源码保留各自许可证，见
[LICENSE](LICENSE) 和 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
数据保存、模型下载及可选 CLI 总结的联网行为见 [PRIVACY.md](PRIVACY.md)。
开发与测试见 [CONTRIBUTING.md](CONTRIBUTING.md)。

当前脚本生成的是未公证开发版本。面向普通用户分发 `.app` 前，需要自行配置
Developer ID 签名与 Apple 公证；不要将开发版本描述为已公证发行版。
发布源码时只发布 Git 跟踪文件，不要直接压缩整个工作目录；其中可能包含
构建缓存、本地工具和历史运行产物。持续集成负责构建及离线测试，不调用云端 CLI。
