# Goose Windows GGUF 导入助手

这个助手可以让你选择电脑上已有的 `.gguf` 模型，把它注册到 Goose，
并通过 `llama.cpp` 启动本地模型服务。助手不会复制或上传模型。

## 使用前准备

- Windows PowerShell 5.1 或更新版本
- 已安装 Goose Desktop
- `llama-server.exe`（来自 llama.cpp）
- 你有权使用的 GGUF 模型

## 推荐目录

先建立一个支持目录，例如 `D:\Goose-Local`：

```text
D:\Goose-Local\
  llama.cpp\bin\llama-server.exe
  models\
  logs\
  scripts\
```

模型可以放在任意位置，包括带空格的目录，不必复制到支持目录。

## 安装和导入

1. 解压本 ZIP。
2. 右键 `Install.ps1`，选择使用 PowerShell 运行；或者在解压目录执行：

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Install.ps1
   ```

3. 选择上面的支持目录，例如 `D:\Goose-Local`。
4. 安装完成后，双击支持目录中的 `Import-Local-GGUF.cmd`。
5. 选择 `.gguf`，输入模型显示名称、GPU Layers 和上下文长度。
6. 等待服务显示导入成功，然后重新启动 Goose。
7. 在 Goose 中选择：

   ```text
   Provider: Local GGUF (llama.cpp)
   Model: 导入时输入的名称
   ```

所有导入模型共用 `127.0.0.1:8080`，因此同一时间只运行一个模型。

## 不包含的内容

本 ZIP 不包含 GGUF 权重、`llama-server.exe`、个人配置、API Key 或登录信息。
