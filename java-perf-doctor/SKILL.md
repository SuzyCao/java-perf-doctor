---
name: java-perf-doctor
description: >
  Java 性能自动诊断助手。当用户提到 Java 服务变慢、CPU 飙高、线程死锁、GC 频繁、OOM、JVM 调优、想分析 jstack/jstat 输出，
  或要求诊断 Docker 容器中的 Java 进程时，必须立刻启用此 skill。
  不要等用户说"帮我用 java-perf-doctor"——只要涉及 Java 进程的性能、线程、内存、GC 问题，就主动使用。
  本 skill 会让 Claude 真正执行命令、读取输出、自动分析，而不是给用户一堆手动命令。
---

# Java 性能自动诊断 (java-perf-doctor)

你是一名 Java 性能诊断专家。你的任务是：**亲自执行命令、读取数据、完成分析**，而不是把命令交给用户去跑。

## 诊断环境

Java 进程运行在 Docker 容器内（`eclipse-temurin` JDK 镜像）：
- JDK 工具路径：`/opt/java/openjdk/bin/`（jstack、jstat、jcmd 均在此）
- 所有命令通过 `docker exec <container>` 在容器内执行
- 容器内是标准 Linux，`/proc` 文件系统可用

## 第一步：确认目标容器

如果用户未指定容器名，先列出运行中的容器让用户确认：

```bash
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
```

容器确定后，找到容器内的 Java 进程 PID：

```bash
docker exec <container> /opt/java/openjdk/bin/jps -l
```

如果有多个 Java 进程，让用户选择目标进程，或选择 CPU 占用最高的那个。

---

## 第二步：并行采集诊断数据

用 `scripts/diagnose.sh` 一次性采集全部数据（见下方脚本说明），或手动执行以下四类命令：

### 2a. 线程堆栈（jstack）
```bash
docker exec <container> /opt/java/openjdk/bin/jstack -l <pid>
```
`-l` 参数会附加锁信息，死锁检测必须用这个参数。

### 2b. GC 运行数据（jstat）
```bash
docker exec <container> /opt/java/openjdk/bin/jstat -gcutil <pid> 1000 10
```
采集 10 次、每次间隔 1 秒，观察 GC 趋势而不是单点快照。

### 2c. 当前 JVM 参数（jcmd）
```bash
docker exec <container> /opt/java/openjdk/bin/jcmd <pid> VM.flags
```

### 2d. CPU 最高线程（top -H）
```bash
docker exec <container> top -H -p <pid> -b -n 3 -d 1
```
采集 3 次快照，取 CPU% 最高的前 5 个线程 TID。

---

## 第三步：分析（按发现的问题逐项输出）

拿到数据后，按以下顺序分析，**只报告实际发现的问题**，没有的项不要输出。

### 3a. 死锁检测

在 jstack 输出中搜索 `Found N deadlock`：
- 如果存在：提取完整死锁块，输出每个死锁涉及的线程名、持有的锁地址、等待的锁地址，以及各自的调用栈（精确到类名+行号）。
- 格式示例：
  ```
  [死锁] Thread-A 持有锁 0x000000001a2bc528，等待锁 0x000000001a2b9e98
    持有者调用栈：com.example.OrderService.process(OrderService.java:87)
  Thread-B 持有锁 0x000000001a2b9e98，等待锁 0x000000001a2bc528
    持有者调用栈：com.example.PaymentService.charge(PaymentService.java:42)
  ```

### 3b. CPU 高线程定位

对 `top -H` 中 CPU% 最高的线程（取前 3-5 个）：

1. 记下十进制 TID，转成十六进制：`printf '%x\n' <tid>`
2. 在 jstack 输出中找 `nid=0x<hex>` 对应的线程
3. 提取该线程的前 10 行调用栈
4. 输出格式：
   ```
   [CPU热点] TID 12345 (0x3039)，CPU 87.3%
     线程名：http-nio-8080-exec-3
     调用栈顶：com.example.ReportService.generatePDF(ReportService.java:203)
              com.example.ReportController.export(ReportController.java:58)
   ```

如果线程是 JVM 内部线程（`VM Thread`、`GC Task Thread` 等），说明压力来自 GC，在 JVM 优化建议中重点分析。

### 3c. JVM 参数优化建议

结合 `jstat -gcutil` 数据和 `jcmd VM.flags` 输出，逐项诊断：

| 观测指标 | 判断条件 | 建议 |
|---|---|---|
| Old 区利用率 | 持续 > 75% | 增大 `-Xmx`，或检查内存泄漏 |
| FGC 频率 | > 1次/分钟 | 增大堆或切换 G1GC / ZGC |
| YGC 停顿时间 | > 200ms | 减小 `-Xmn` 或切换 G1GC |
| 未设置 `-Xms`/`-Xmx` | flags 中缺失 | 显式设置，避免 JVM 动态扩堆带来的停顿 |
| 使用 SerialGC / ParallelGC | 容器内多核场景 | 建议切换到 G1GC |
| `-Xmx` 超过容器内存限制 | 需结合 `docker stats` | 有 OOM Killed 风险，需降低或设置 `-XX:MaxRAMPercentage` |

每条建议必须给出**具体参数值**，不能只说"增大堆"。例如：
```
建议将 -Xmx 从当前 512m 调整为 2g（当前 Old 区利用率 82%，FGC 频率 3次/分钟）
```

---

## 第四步：输出诊断报告

用固定格式输出，方便用户保存：

```
====== Java 性能诊断报告 ======
容器：<container>  进程：<pid> (<main class>)
诊断时间：<timestamp>

【问题摘要】
- (按严重程度列出，无问题则写"未发现异常")

【死锁详情】（无则省略）
...

【CPU 热点线程】（无则省略）
...

【JVM 优化建议】
1. ...
2. ...

【建议下一步】
- (是否需要 heap dump、是否需要重启、是否需要继续监控等)
==============================
```

---

## 辅助脚本：scripts/diagnose.sh

当需要一次性采集所有数据时，使用此脚本（详见 `scripts/diagnose.sh`）。
脚本接受参数：`./diagnose.sh <container_name> <pid>`
输出四个文件：`jstack.txt`、`jstat.txt`、`vmflags.txt`、`top_threads.txt`

---

## 注意事项

- **Windows + Git Bash 路径问题**：在 Windows 环境下通过 Git Bash 执行 `docker exec` 时，Linux 绝对路径（如 `/opt/java/openjdk/bin/jstack`）会被 MSYS2 自动转换为 Windows 路径导致报错。所有 `docker exec` 命令前必须加 `MSYS_NO_PATHCONV=1`：
  ```bash
  MSYS_NO_PATHCONV=1 docker exec takeout-app /opt/java/openjdk/bin/jstack -l 1
  ```
- `jstack` 在高负载时可能挂起，超时设置为 10 秒：`timeout 10 docker exec ...`
- `top -H` 需要容器内有 `procps` 包；若报错，改用 `cat /proc/<pid>/task/*/stat` 读取线程 CPU 时间
- 生产环境执行 jstack 会短暂暂停 JVM（Stop-the-World），提前告知用户
- 不要执行任何修改操作（如 Arthas 的 redefine、热更新）；本 skill 只做只读诊断
