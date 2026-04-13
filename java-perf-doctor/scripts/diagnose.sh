#!/bin/bash
# java-perf-doctor 诊断数据采集脚本
# 用法: ./diagnose.sh <container_name> <pid> [output_dir]
# 输出: jstack.txt, jstat.txt, vmflags.txt, top_threads.txt

set -e

CONTAINER=${1:?"用法: $0 <container_name> <pid> [output_dir]"}
PID=${2:?"用法: $0 <container_name> <pid> [output_dir]"}
OUTPUT_DIR=${3:-"/tmp/java-diag-$$"}
JDK_BIN="/opt/java/openjdk/bin"

mkdir -p "$OUTPUT_DIR"
echo "[java-perf-doctor] 采集目标: 容器=$CONTAINER PID=$PID 输出=$OUTPUT_DIR"

# 1. jstack 线程堆栈（含锁信息）
echo "[1/4] 采集 jstack..."
timeout 15 docker exec "$CONTAINER" \
  "$JDK_BIN/jstack" -l "$PID" > "$OUTPUT_DIR/jstack.txt" 2>&1 \
  && echo "  ✓ jstack.txt" \
  || echo "  ✗ jstack 失败，请检查 PID 是否正确"

# 2. jstat GC 数据（10次 × 1秒间隔）
echo "[2/4] 采集 jstat（10秒）..."
docker exec "$CONTAINER" \
  "$JDK_BIN/jstat" -gcutil "$PID" 1000 10 > "$OUTPUT_DIR/jstat.txt" 2>&1 \
  && echo "  ✓ jstat.txt" \
  || echo "  ✗ jstat 失败"

# 3. JVM 参数
echo "[3/4] 采集 VM flags..."
docker exec "$CONTAINER" \
  "$JDK_BIN/jcmd" "$PID" VM.flags > "$OUTPUT_DIR/vmflags.txt" 2>&1 \
  && echo "  ✓ vmflags.txt" \
  || echo "  ✗ jcmd 失败"

# 4. CPU 最高线程（3次快照）
echo "[4/4] 采集 top -H（3秒）..."
docker exec "$CONTAINER" \
  top -H -p "$PID" -b -n 3 -d 1 > "$OUTPUT_DIR/top_threads.txt" 2>&1 \
  && echo "  ✓ top_threads.txt" \
  || {
    # fallback: 从 /proc 读取线程 CPU 时间
    echo "  top 失败，尝试 /proc fallback..."
    docker exec "$CONTAINER" bash -c "
      echo 'TID    utime    stime    comm'
      for f in /proc/$PID/task/*/stat; do
        tid=\$(echo \$f | grep -o '[0-9]*' | tail -2 | head -1)
        read -r vals < \$f
        comm=\$(cat /proc/$PID/task/\$tid/comm 2>/dev/null || echo '?')
        utime=\$(echo \$vals | awk '{print \$14}')
        stime=\$(echo \$vals | awk '{print \$15}')
        echo \"\$tid    \$utime    \$stime    \$comm\"
      done | sort -k2 -rn | head -10
    " > "$OUTPUT_DIR/top_threads.txt" 2>&1 \
    && echo "  ✓ top_threads.txt (via /proc)"
  }

echo ""
echo "[java-perf-doctor] 采集完成，文件保存在: $OUTPUT_DIR"
echo "  $(ls -lh "$OUTPUT_DIR" | tail -n +2 | awk '{print $5, $9}')"
