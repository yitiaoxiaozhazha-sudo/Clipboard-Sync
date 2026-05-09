# 剪贴板同步

iOS 越狱设备与 PC 之间通过局域网共享剪贴板。

## 架构

- **iOS**：越狱插件 (theos) 挂钩 `UIPasteboard`，通过 TCP 同步剪贴板变更
- **PC**：Python 服务器监听本地剪贴板，双向转发变更
- **协议**：JSON 消息通过 TCP 传输，以 `\n` 分隔

## PC 端设置 (Windows / macOS / Linux)

### 安装依赖

```bash
pip install -r pc/requirements.txt
```

### 启动服务端

```bash
python3 pc/clipboard_server.py
```

可选参数：

```bash
python3 pc/clipboard_server.py --port 8888       # 自定义端口
python3 pc/clipboard_server.py --host 0.0.0.0    # 绑定地址
```

服务端默认监听所有网络接口 (0.0.0.0:9527)。

## iOS 端设置 (需要越狱)

### 前提条件

- [theos](https://github.com/theos/theos) 构建系统
- 已越狱的 iOS 设备 (支持有根/无根越狱)

### 编译

```bash
cd ios

# 无根越狱 (默认)：
make package

# 有根越狱：
make package THEOS_PACKAGE_SCHEME=
```

### 安装

编译后的 `.deb` 包在 `packages/` 目录。安装方式：

- Sileo / Zebra：打开 `.deb` 文件安装
- SSH：将 `.deb` 通过 scp 传入设备，然后运行 `dpkg -i`

### 配置

安装后，打开 **设置** > **Clipboard Sync**：

| 设置项   | 描述                       | 默认值           |
|----------|----------------------------|------------------|
| IP 地址  | 你的 PC 局域网 IP           | 192.168.1.100    |
| 端口     | 服务端端口 (需与 PC 一致)   | 9527             |
| 启用     | 开关同步功能                | ON               |

插件支持断线自动重连，网络切换或 PC 端重启后无需手动操作。

## 工作原理

1. PC 运行 `clipboard_server.py`，开放 TCP 端口 9527
2. iOS 插件连接到 PC 的 IP:端口
3. iOS 剪贴板变化 → 发送文本到 PC → PC 更新剪贴板
4. PC 剪贴板变化 → 广播到 iOS → iOS 更新剪贴板
5. 防循环：双方忽略由同步消息触发的剪贴板变更

## 运行环境

- **PC**：Python 3.6+，安装 `pyperclip` (`pip install pyperclip`)
- **iOS**：越狱 iOS 13.0+，theos 构建环境
- **网络**：两端在同一局域网，防火墙放行 TCP 9527 端口
