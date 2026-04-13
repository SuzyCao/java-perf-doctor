# java-perf-doctor 🚀
An AI-Native JVM Diagnostic Skill for Claude Code

java-perf-doctor 是一个专为 Claude Code 设计的自动化诊断工具。它结合了 Shell 脚本的硬核采集能力与大模型的逻辑推理能力，能够跨越宿主机边界，直接深入 Docker 容器 内部进行 JVM 性能体检。

# java-perf-doctor 🚀

![Java](https://img.shields.io/badge/Java-ED8B00?style=for-the-badge&logo=openjdk&logoColor=white)
![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=for-the-badge&logo=docker&logoColor=white)
![Claude](https://img.shields.io/badge/Claude-Code-purple?style=for-the-badge)

## 🌟 项目亮点 (Key Features)
零侵入容器钻取：无需在容器内预装复杂 Agent，通过 docker exec 自动化调度 JDK 原生工具（jstack, jstat, jcmd）。

多维数据关联分析：

死锁精准定位：自动扫描线程堆栈，识别持有/等待锁的地址，并关联至 Java 源码行号。

CPU 热点追踪：自动完成 Linux TID（十进制）到 JVM NID（十六进制）的进制转换，锁定“耗币”代码。

GC 趋势健康检查：实时分析 Eden/Old 区占比及 FGC 频率，给出具体的参数调优建议。

防御性脚本设计：内置 /proc 文件系统 fallback 逻辑，即便在删减版（精简型）Docker 镜像中也能通过读取内核数据完成采集。

自动化评测体系：包含完整的 evals.json 测试用例，通过自动化断言确保诊断结果的准确性与鲁棒性。

## 🏗️ 项目结构 (Project Structure)

```text
java-perf-doctor/
├── SKILL.md             # 🤖 AI 逻辑核心：定义诊断 SOP、决策树与报告模板
├── scripts/             # 🛠️ 采集工具箱
│   └── diagnose.sh      # 原子化脚本：负责 Docker 内部数据的安全抓取
├── evals/               # 🧪 质量门禁 (Eval Suite)
│   └── evals.json       # 自动化测试用例：覆盖死锁、CPU 飙高、GC 异常场景
└── README.md            # 📖 项目说明书
``` 
## 🚀 快速开始 (Quick Start)
1. 安装
将本项目克隆到你的 Claude Code 项目目录下：

Bash
git clone https://github.com/your-username/java-perf-doctor.git .claude/skills/java-perf-doctor

2. 使用
在 Claude Code 终端中直接下达自然语言指令，它会主动调用本 Skill：

"帮我诊断一下 takeout-app 容器的性能，最近响应有点慢。"

## 🛠️ 技术栈 (Tech Stack)
Java/JVM: Deep understanding of jstack, jstat, jcmd and Memory Management.

Docker: Containerized process management and cross-container CLI execution.

Shell Scripting: Robust data collection with error handling and fallback mechanisms.

AI Engineering: Prompt engineering for complex logic reasoning and structured reporting.
