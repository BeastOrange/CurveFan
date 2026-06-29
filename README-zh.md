<div align="center">
  <img src="CurveFan/Assets/AppIcon.png" width="128" height="128" alt="CurveFan">

  # CurveFan

  **原生 macOS Apple Silicon 风扇转速监控与控制器**

  ![Swift](https://img.shields.io/badge/Swift-6.4-F05138?logo=swift&logoColor=white)
  ![macOS](https://img.shields.io/badge/macOS-26%2B-000000?logo=apple&logoColor=white)
  ![Platform](https://img.shields.io/badge/Apple_Silicon-M1--M5-8A2BE2)
  ![License](https://img.shields.io/badge/License-MIT-22c55e)
</div>

<div align="center">

[English](README.md) | 简体中文

</div>

---

<div align="center">
  <img src="docs/screenshot-menubar.png" width="320" alt="菜单栏面板">
  &nbsp;&nbsp;
  <img src="docs/screenshot-main.png" width="580" alt="主窗口">
</div>

---

CurveFan 是一款运行在菜单栏的原生 macOS 应用，通过 SMC 直接控制 Apple Silicon Mac 的风扇转速。所有硬件写入由特权 LaunchDaemon 负责执行，UI 进程无特权运行。退出应用或选择 **System Auto** 时，会自动恢复 macOS 原生风扇管理。

> **警告** — CurveFan 直接写入 SMC 风扇寄存器，手动控制风扇存在热管理风险，请谨慎使用。

## 技术栈

| 层级 | 技术 |
|---|---|
| 语言 | Swift 6.4（严格并发模型） |
| UI | SwiftUI + AppKit（NSStatusItem / NSPanel） |
| 图表 | Swift Charts — RPM 趋势图、风扇曲线预览 |
| 硬件 | IOKit `AppleSMC` — 仅在 Helper 进程中使用 |
| 进程通信 | Unix socket · JSON · 4 字节长度前缀帧 |
| 构建 | Swift Package Manager |
| 测试 | XCTest · 无需真实硬件 |

## 功能

- **菜单栏面板** — 实时 RPM 仪表、CPU/GPU 温度、风扇转速范围
- **System Auto** — 一键恢复 macOS 原生风扇控制
- **风扇曲线预设** — Quiet（静音）、Balanced（均衡）、MaxCool（全速散热）
- **手动 RPM** — 固定转速目标，自动限制在硬件允许范围内
- **批量 SMC 读取** — 所有温度传感器通过单次 IPC 往返获取
- **唤醒恢复** — 系统从睡眠唤醒后自动重新下发手动设置
- **Apple Silicon M1–M5 全覆盖** — 按芯片代际区分 SMC key 和解锁序列

## 架构

```
CurveFanCore（库）            ← 共享模型、IPC 类型、SMC 解码器、预设
    ├── CurveFan（SwiftUI）   ← 无特权 UI 进程，通过 Unix socket 通信
    └── CurveFanHelper        ← root LaunchDaemon，唯一 SMC / IOKit 访问点
```

应用进程从不直接接触 SMC。每个硬件操作都以长度前缀 JSON 命令的形式跨 Unix socket 传递。Helper 在写入前会校验所有输入（key 格式、风扇索引、RPM 范围）。

## 系统要求

- Apple Silicon Mac（M1 或更新）且具有至少一个可控风扇
- macOS 26.0 或更高
- 管理员权限（首次启动时安装特权 Helper）

## 安装

从 [Releases](https://github.com/BeastOrange/CurveFan/releases) 下载最新 DMG。

1. 打开 DMG，将 **CurveFan.app** 拖入 Applications 文件夹。
2. 双击打开 **CurveFan.app**。
3. 首次启动时，CurveFan 会请求安装特权 Helper — 点击 **Install Helper** 并输入密码。
4. 完成。Helper 将随系统登录自动启动，之后无需任何额外操作。

如果 macOS 提示应用已损坏或无法打开：

```bash
sudo xattr -cr /Applications/CurveFan.app
```

## 从源码构建

```bash
git clone git@github.com:BeastOrange/CurveFan.git && cd CurveFan

swift build                   # 调试构建，所有目标
swift test                    # 单元测试（无需真实硬件）
bash build_app.sh release     # 打包 .build/release/CurveFan.app
bash build_dmg.sh 1.0.0       # 生成 CurveFan-1.0.0.dmg
sudo bash setup.sh            # 不通过 DMG 直接安装
bash setup.sh --check         # 查看安装状态
```

### 冒烟测试

```bash
bash smoke_ipc_local.sh    # 完整 IPC 往返测试，使用假 SMC，无需硬件
bash smoke_hardware.sh     # 真实硬件 SMC 读取测试（需要 Helper 已运行）
```

## 卸载

```bash
sudo bash uninstall.sh              # 移除 App、Helper、守护进程和用户数据
sudo bash uninstall.sh --keep-data  # 保留预设数据
```

## 安全说明

- 退出 CurveFan 或选择 **System Auto** 时，会在终止前恢复 macOS 风扇控制。
- Helper 在收到 `SIGTERM`/`SIGINT` 时也会自动恢复，作为第二道防线。
- RPM 值被强制限制在风扇硬件上报的范围内，超出范围的请求会被拒绝。
- 安全漏洞请私下报告 — 详见 [SECURITY.md](SECURITY.md)。

## 开源协议

MIT — 详见 [LICENSE](LICENSE)。
