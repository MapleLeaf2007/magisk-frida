#!/bin/sh
# MagiskFrida - 延迟启动服务脚本
# 此脚本在系统完全启动后的延迟启动服务模式下运行

MODPATH=${0%/*}

# 增强的日志设置
exec 2>> $MODPATH/logs/service.log
set -x

# 日志初始化
{
  echo ""
  echo "=========================================="
  echo "延迟启动服务脚本已启动"
  echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "模块路径: $MODPATH"
  echo "Android API 级别: $(getprop ro.build.version.sdk_int)"
  echo "=========================================="
  echo ""
} >> $MODPATH/logs/service.log 2>&1

# 加载实用函数
echo "[*] 正在加载实用函数..." >> $MODPATH/logs/service.log

if [ ! -f $MODPATH/utils.sh ]; then
  echo "[ERROR] 未找到 utils.sh" >> $MODPATH/logs/service.log
  exit 1
fi

. $MODPATH/utils.sh || {
  echo "[ERROR] 加载 utils.sh 失败" >> $MODPATH/logs/service.log
  exit 1
}

echo "[+] 实用函数已加载" >> $MODPATH/logs/service.log

# 检查模块是否被禁用
if [ -f $MODPATH/disable ]; then
  echo "[!] 检测到模块禁用标志 - 跳过 florida 启动" >> $MODPATH/logs/service.log
  exit 0
fi

# 等待启动完成
echo "[*] 等待 Android 启动完成..." >> $MODPATH/logs/service.log
if ! wait_for_boot; then
  echo "[ERROR] 启动等待失败" >> $MODPATH/logs/service.log
  exit 1
fi

echo "[+] 启动完成，继续启动 florida-server" >> $MODPATH/logs/service.log

# 验证 Frida-server 二进制文件是否存在
FRIDA_BIN="$MODPATH/system/bin/florida-server"
if [ ! -f "$FRIDA_BIN" ]; then
  echo "[ERROR] 在 $FRIDA_BIN 未找到 florida-server 二进制文件" >> $MODPATH/logs/service.log
  string="description=开机时运行 florida-server：❌（缺少二进制文件）"
  sed -i "s/^description=.*/$string/g" $MODPATH/module.prop
  exit 1
fi

echo "[*] 正在启动 florida-server 守护进程..." >> $MODPATH/logs/service.log

# 启动 Frida-server
if "$FRIDA_BIN" -D >> $MODPATH/logs/service.log 2>&1; then
  echo "[+] florida-server 守护进程已启动" >> $MODPATH/logs/service.log
else
  echo "[ERROR] 启动 florida-server 守护进程失败" >> $MODPATH/logs/service.log
  string="description=开机时运行 florida-server：❌（启动失败）"
  sed -i "s/^description=.*/$string/g" $MODPATH/module.prop
  exit 1
fi

# 给它一点时间稳定
sleep 1

# 验证 Frida-server 是否正在运行
echo "[*] 正在验证 florida-server 启动..." >> $MODPATH/logs/service.log

if check_frida_is_up 5; then
  echo "[+] florida-server 正在运行且已验证" >> $MODPATH/logs/service.log
else
  echo "[ERROR] florida-server 未响应验证检查" >> $MODPATH/logs/service.log
fi

echo "" >> $MODPATH/logs/service.log
echo "[+] 延迟启动服务脚本完成于 $(date '+%Y-%m-%d %H:%M:%S')" >> $MODPATH/logs/service.log
echo "=========================================="  >> $MODPATH/logs/service.log
echo "" >> $MODPATH/logs/service.log

#EOF