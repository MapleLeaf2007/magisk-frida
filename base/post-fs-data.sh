#!/bin/sh
# MagiskFrida - Post FS-Data 脚本
# 此脚本在启动早期的 post-fs-data 模式下运行

MODPATH=${0%/*}

# 增强的日志设置，使用追加模式保留历史记录
exec 2>> $MODPATH/logs/post-fs-data.log
set -x

# 日志初始化
{
  echo ""
  echo "=========================================="
  echo "Post-FS-Data 脚本已启动"
  echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "模块路径: $MODPATH"
  echo "=========================================="
  echo ""
} >> $MODPATH/logs/post-fs-data.log 2>&1

# 验证模块结构
echo "[*] 正在验证模块结构..." >> $MODPATH/logs/post-fs-data.log

if [ ! -f $MODPATH/module.prop ]; then
  echo "[ERROR] 未找到 module.prop" >> $MODPATH/logs/post-fs-data.log
  exit 1
fi

if [ ! -f $MODPATH/system/bin/frida-server ]; then
  echo "[ERROR] 未找到 Frida-server 二进制文件" >> $MODPATH/logs/post-fs-data.log
  exit 1
fi

echo "[+] 模块结构已验证" >> $MODPATH/logs/post-fs-data.log

# 预启动检查
echo "[*] 正在运行预启动检查..." >> $MODPATH/logs/post-fs-data.log

# 设置适当的权限
chmod 755 $MODPATH/system/bin/frida-server 2>/dev/null
chcon u:object_r:system_file:s0 $MODPATH/system/bin/frida-server 2>/dev/null

echo "[+] Post-FS-Data 脚本成功完成" >> $MODPATH/logs/post-fs-data.log
echo "" >> $MODPATH/logs/post-fs-data.log

#EOF