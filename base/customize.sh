#!/bin/sh
##########################################################################################
#
# Magisk 模块安装脚本
#
##########################################################################################
##########################################################################################
#
# 使用说明：
#
# 1. 将要安装的文件放入 system 文件夹（删除 placeholder 文件）
# 2. 在 module.prop 中填写模块信息
# 3. 在本文件中配置并实现回调函数
# 4. 如果需要开机脚本，请将它们添加到 common/post-fs-data.sh 或 common/service.sh
# 5. 将任何新增或修改的系统属性放入 common/system.prop
#
##########################################################################################

##########################################################################################
# 配置标志
##########################################################################################

# 如果你不希望 Magisk 为你挂载任何文件，请设为 true。
# 大多数模块不应该将其设为 true。
SKIPMOUNT=false

# 如果需要加载 system.prop，请设为 true
PROPFILE=false

# 如果需要 post-fs-data 脚本，请设为 true
POSTFSDATA=false

# 如果需要 late_start service 脚本，请设为 true
LATESTARTSERVICE=true

##########################################################################################
# 替换列表
##########################################################################################

# 在此列出所有你想要直接替换系统中的目录
# 查阅文档以了解为何以及何时需要使用替换列表

# 示例格式如下：
REPLACE_EXAMPLE="
/system/app/Youtube
/system/priv-app/SystemUI
/system/priv-app/Settings
/system/framework
"

# 在这里构造你自己的替换列表
REPLACE="
"

##########################################################################################
# 回调函数
##########################################################################################
#
# 安装框架会调用下面的函数。
# 你无法修改 update-binary，定制安装仅能通过实现这些回调函数来完成。
#
# 在执行回调时，安装框架会将 Magisk 内部的 busybox 路径放在 PATH 的最前面，
# 因此常见命令都应可用。同时，/data、/system 和 /vendor 会被正确挂载。
#
##########################################################################################
##########################################################################################
# 安装框架会导出若干变量和函数。
# 请在安装中使用这些变量和函数。
#
# ! 不要使用任何 Magisk 内部路径，这些并非公共 API。
# ! 不要使用 util_functions.sh 中的非公共函数，它们也不是公共 API。
# ! 非公共 API 无法保证在各版本间保持兼容。
#
# 可用变量：
#
# MAGISK_VER (string): 当前已安装的 Magisk 版本字符串
# MAGISK_VER_CODE (int): 当前已安装的 Magisk 版本代码
# BOOTMODE (bool): 如果模块正在 Magisk Manager 中安装则为 true
# MODPATH (path): 模块文件应安装到的路径
# TMPDIR (path): 可用于临时存放文件的目录
# ZIPFILE (path): 模块安装 zip 的路径
# ARCH (string): 设备架构，值为 arm、arm64、x86 或 x64
# IS64BIT (bool): 如果 $ARCH 为 arm64 或 x64，则为 true
# API (int): 设备的 API 级别（Android 版本）
#
# 可用函数：
#
# ui_print <msg>
#     将 <msg> 打印到安装界面（请优先使用该函数）
#     避免使用 'echo'，因为它不会在自定义 recovery 的界面中显示
#
# abort <msg>
#     打印错误信息 <msg> 并终止安装
#     避免使用 'exit'，因为 exit 会跳过安装的清理步骤
#
# set_perm <target> <owner> <group> <permission> [context]
#     如果未提供 [context]，默认使用 "u:object_r:system_file:s0"
#     该函数相当于以下命令的简写：
#       chown owner.group target
#       chmod permission target
#       chcon context target
#
# set_perm_recursive <directory> <owner> <group> <dirpermission> <filepermission> [context]
#     如果未提供 [context]，默认使用 "u:object_r:system_file:s0"
#     对 <directory> 中的所有文件调用：
#       set_perm file owner group filepermission context
#     对 <directory> 中的所有目录（包括自身）调用：
#       set_perm dir owner group dirpermission context
#
##########################################################################################
##########################################################################################
# 如果你需要开机脚本，不要使用系统通用的脚本目录（post-fs-data.d/service.d），
# 只使用模块脚本，以便在模块被移除或禁用时行为一致，并保证未来 Magisk 版本中保持相同行为。
# 通过在配置区设置相应的标志来启用开机脚本。
##########################################################################################

[ ! -d $MODPATH/logs ] && mkdir -p $MODPATH/logs

# 完善的日志设置
exec 2>> $MODPATH/logs/customize.log
set -x

# 记录启动信息
echo "=========================================="
echo "MagiskFrida 模块安装开始"
echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=========================================="
echo "模块路径: $MODPATH"
echo "系统: Android $(getprop ro.build.version.release) (API $(getprop ro.build.version.sdk_int))"
echo ""

PATH=$PATH:/data/adb/ap/bin:/data/adb/magisk:/data/adb/ksu/bin

# 尽量减少 Magisk 强制的模块安装后端干预（末尾不能有分号）
# SKIPUNZIP=1

# 安装时显示的信息
print_modname() {
  ui_print " "
  ui_print "    ============================================"
  ui_print "    *        MagiskFrida 模块安装器          *"
  ui_print "    *  兼容 Magisk/KernelSU/APatch           *"
  ui_print "    *        版本: \$(cat $MODPATH/module.prop | grep "^version=" | cut -d= -f2)          *"
  ui_print "    ============================================"
  ui_print " "
  echo "[*] 模块安装开始..."
}

# 在 on_install 中将模块文件拷贝/解压到 $MODPATH

on_install() {
  echo "[*] 验证设备架构..."
  case $ARCH in
    arm64)
      F_ARCH=$ARCH
      echo "[+] 检测到：ARM64（64位）"
      ;;
    arm)
      F_ARCH=$ARCH
      echo "[+] 检测到：ARM（32位）"
      ;;
    x64)
      F_ARCH=x86_64
      echo "[+] 检测到：x86_64（64位）"
      ;;
    x86)
      F_ARCH=$ARCH
      echo "[+] 检测到：x86（32位）"
      ;;
    *)
      echo "[-] 错误：检测到不支持的架构: $ARCH"
      ui_print "[-] 错误：不支持的架构: $ARCH"
      abort
      ;;
  esac

  ui_print "- 设备架构: $F_ARCH"
  echo "[+] 为 $F_ARCH 选择 Frida 二进制文件"

  # 检测安装来源
  echo "[*] 检测安装环境..."
  if [ "$BOOTMODE" ] && [ "$KSU" ]; then
      ui_print "- 安装来源：KernelSU"
      ui_print "- KernelSU 内核版本: $KSU_KERNEL_VER_CODE"
      ui_print "- KernelSU 守护进程版本: $KSU_VER_CODE"
      echo "[+] 检测到 KernelSU 环境"
  elif [ "$BOOTMODE" ] && [ "$APATCH" ]; then
      ui_print "- 安装来源：APatch"
      ui_print "- APatch 版本: $APATCH_VER_CODE"
      ui_print "- Magisk 版本: $MAGISK_VER_CODE"
      echo "[+] 检测到 APatch 环境"
  elif [ "$BOOTMODE" ] && [ "$MAGISK_VER_CODE" ]; then
      ui_print "- 安装来源：Magisk"
      ui_print "- Magisk 版本: $MAGISK_VER_CODE ($MAGISK_VER)"
      echo "[+] 检测到 Magisk 环境"
  else
    ui_print "*****************************************************"
    ui_print "[-] 错误：不支持的安装环境"
    ui_print "[-] 请通过 KernelSU、Magisk 或 APatch 应用安装"
    ui_print "*****************************************************"
    echo "[!] 错误：必须通过兼容的应用执行安装"
    abort
  fi

  echo "[*] 解压模块文件..."
  ui_print "- 正在为 $F_ARCH 解压模块文件..."
  F_TARGETDIR="$MODPATH/system/bin"

  if ! mkdir -p "$F_TARGETDIR" 2>/dev/null; then
    echo "[-] 错误：无法创建目标目录: $F_TARGETDIR"
    ui_print "[-] 错误：创建目标目录失败"
    abort
  fi

  echo "[+] 已创建目标目录: $F_TARGETDIR"

  if ! chcon -R u:object_r:system_file:s0 "$F_TARGETDIR" 2>/dev/null; then
    echo "[!] 警告：设置 SELinux 上下文失败（非关键）"
  fi

  if ! chmod -R 755 "$F_TARGETDIR" 2>/dev/null; then
    echo "[-] 错误：设置目录权限失败"
    ui_print "[-] 错误：设置权限失败"
    abort
  fi

  echo "[*] 正在解压 Frida-server 二进制..."
  if ! busybox unzip -qq -o "$ZIPFILE" "files/frida-server-$F_ARCH" -j -d "$F_TARGETDIR" 2>/dev/null; then
    echo "[-] 错误：为 $F_ARCH 解压 Frida-server 失败"
    ui_print "[-] 错误：解压失败"
    abort
  fi

  echo "[+] 已解压 Frida-server"

  if ! mv "$F_TARGETDIR/frida-server-$F_ARCH" "$F_TARGETDIR/frida-server" 2>/dev/null; then
    echo "[-] 错误：重命名 Frida-server 二进制文件失败"
    ui_print "[-] 错误：文件重命名失败"
    abort
  fi

  echo "[+] Frida-server 安装完成"
  ui_print "- Frida-server 安装完成"
}

# 只有少数特殊文件需要特殊权限
# 本函数将在 on_install 完成后被调用
# 对于大多数情况，默认权限已足够

set_permissions() {
  echo "[*] 设置文件权限..."

  # 以下为默认规则，请勿移除
  if ! set_perm_recursive $MODPATH 0 0 0755 0644; then
    echo "[!] 警告：默认权限设置失败"
  fi
  echo "[+] 默认权限已应用"

  # 为 Frida-server 二进制设置自定义权限
  echo "[*] 设置 Frida-server 可执行权限..."
  if ! set_perm $MODPATH/system/bin/frida-server 0 2000 0755 u:object_r:system_file:s0; then
    echo "[!] 警告：设置 Frida-server 权限失败（可能导致问题）"
  else
    echo "[+] Frida-server 权限已配置"
  fi
}

# 主安装流程
echo "[*] 调用 print_modname..."
print_modname

echo "[*] 调用 on_install..."
on_install

echo "[*] 调用 set_permissions..."
set_permissions

# 处理模块被禁用的情况
if [ -f $MODPATH/disable ]; then
  echo "[!] 检测到模块禁用标志"
  string="description=开机时运行 frida-server：❌（已禁用）"
  if ! sed -i "s/^description=.*/$string/g" $MODPATH/module.prop 2>/dev/null; then
    echo "[!] 警告：更新 module.prop 失败"
  fi
fi

echo "=========================================="
echo "模块安装完成"
echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=========================================="
echo ""

#EOF