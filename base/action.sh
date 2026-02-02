#!/system/bin/sh
# MagiskFrida - Frida Server 控制脚本
# 此脚本按需处理启动/停止 Frida-server

MODPATH=${0%/*}
PATH=$PATH:/data/adb/ap/bin:/data/adb/magisk:/data/adb/ksu/bin

# 增强的日志设置
LOG_FILE="$MODPATH/logs/action.log"
exec 2>> "$LOG_FILE"
set -x

# 记录脚本执行时间和时间戳
{
  echo "=========================================="
  echo "MagiskFrida 操作脚本已执行"
  echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "脚本: $(basename $0)"
  echo "模块路径: $MODPATH"
  echo "=========================================="
  echo ""
} >> "$LOG_FILE" 2>&1

# 加载实用程序
if [ ! -f "$MODPATH/utils.sh" ]; then
  echo "[ERROR] 在 $MODPATH/utils.sh 未找到 utils.sh" >> "$LOG_FILE"
  exit 1
fi

echo "[*] 正在加载实用程序..." >> "$LOG_FILE"
. "$MODPATH/utils.sh" || {
  echo "[ERROR] 加载 utils.sh 失败" >> "$LOG_FILE"
  exit 1
}

# 检查模块是否被禁用
if [ -f "$MODPATH/disable" ]; then
    echo "[!] 模块已被禁用 - Frida-server 将不会被控制" >> "$LOG_FILE"
    echo "[-] Frida-server 已禁用" 
    string="description=开机时运行 frida-server：❌（已禁用）"
    sed -i "s/^description=.*/$string/g" "$MODPATH/module.prop"
    echo "" >> "$LOG_FILE"
    exit 0
fi

echo "[*] 正在检查 Frida-server 状态..." >> "$LOG_FILE"

# 获取 Frida-server 进程 ID
result="$(busybox pgrep 'frida-server' 2>/dev/null || echo '')"

if [ ! -z "$result" ] && [ "$result" -gt 0 ] 2>/dev/null; then
    echo "[!] Frida-server 已在运行（PID: $result）" >> "$LOG_FILE"
    echo "[*] 正在停止 Frida-server..." >> "$LOG_FILE"
    
    if busybox kill -9 "$result" 2>/dev/null; then
      echo "[+] Frida-server 停止成功（PID: $result）" >> "$LOG_FILE"
    else
      echo "[ERROR] 停止 Frida-server 失败" >> "$LOG_FILE"
    fi
else
    echo "[*] Frida-server 未运行，正在启动..." >> "$LOG_FILE"
    
    FRIDA_BIN="$MODPATH/system/bin/frida-server"
    
    if [ ! -f "$FRIDA_BIN" ]; then
      echo "[ERROR] 在 $FRIDA_BIN 未找到 Frida-server 二进制文件" >> "$LOG_FILE"
      string="description=开机时运行 frida-server：❌（未找到二进制文件）"
      sed -i "s/^description=.*/$string/g" "$MODPATH/module.prop"
      exit 1
    fi
    
    echo "[*] 正在启动 Frida-server 守护进程..." >> "$LOG_FILE"
    if "$FRIDA_BIN" -D >> "$LOG_FILE" 2>&1; then
      echo "[+] Frida-server 启动成功" >> "$LOG_FILE"
    else
      echo "[ERROR] 启动 Frida-server 失败" >> "$LOG_FILE"
      string="description=开机时运行 frida-server：❌（启动失败）"
      sed -i "s/^description=.*/$string/g" "$MODPATH/module.prop"
      exit 1
    fi
fi

sleep 1

echo "[*] 等待 Frida-server 稳定..." >> "$LOG_FILE"

# 验证 Frida-server 是否正在运行（带超时）
if check_frida_is_up 1; then
  echo "[+] Frida-server 正在运行且有响应" >> "$LOG_FILE"
else
  echo "[ERROR] Frida-server 未能正常启动" >> "$LOG_FILE"
fi

echo "" >> "$LOG_FILE"
echo "[*] 操作脚本完成于 $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
echo "=========================================="  >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

#EOF