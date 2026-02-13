#!/bin/sh
# MagiskFrida - 实用函数
# 模块脚本使用的通用辅助函数

MODPATH=${0%/*}
PATH=$PATH:/data/adb/ap/bin:/data/adb/magisk:/data/adb/ksu/bin

# 增强的日志设置
exec 2>> $MODPATH/logs/utils.log
set -x

echo ""
echo "=========================================="
echo "Utils.sh 已加载"
echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=========================================="
echo ""

# 函数: check_frida_is_up
# 用途: 等待 Frida-server 变得可响应
# 参数: $1 = 超时时间（秒）（默认 4）
# 返回: 0 如果 Frida 正在运行，1 如果超时
function check_frida_is_up() {
    local timeout=4
    local counter=0
    local max_retries=0

    [ ! -z "$1" ] && timeout="$1" || timeout=4
    max_retries=$timeout
    counter=0

    echo "[*] 检查 florida-server 状态（超时: ${timeout}秒）..."

    while [ $counter -lt $max_retries ]; do
        local result="$(busybox pgrep 'florida-server' 2>/dev/null || echo '')"

        if [ ! -z "$result" ] && [ "$result" -gt 0 ] 2>/dev/null; then
            echo "[+] florida-server 正在运行（PID: $result）! 状态: 💉😜"
            string="description=开机时运行 florida-server: ✅（活跃）"
            sed -i "s/^description=.*/$string/g" "$MODPATH/module.prop" 2>/dev/null
            return 0
        else
            echo "[-] florida-server 还未准备好...（尝试 $((counter+1))/$max_retries）"
            counter=$((counter + 1))

            if [ $counter -lt $max_retries ]; then
                sleep 1.5
            fi
        fi
    done

    # 达到超时
    echo "[ERROR] florida-server 在 ${timeout} 秒内未能启动"
    string="description=开机时运行 florida-server: ❌（失败）"
    sed -i "s/^description=.*/$string/g" "$MODPATH/module.prop" 2>/dev/null
    return 1
}

# 函数: wait_for_boot
# 用途: 等待系统完成启动
# 参数: 无
# 返回: 0 成功，1 错误
function wait_for_boot() {
    echo "[*] 等待 Android 启动完成..."
    local counter=0
    local max_wait=300  # 最多等待 5 分钟

    while true; do
        counter=$((counter + 1))

        local boot_status="$(getprop sys.boot_completed 2>/dev/null)"
        local exit_code=$?

        if [ $exit_code -ne 0 ]; then
            echo "[ERROR] 获取启动状态失败（尝试 $counter）"
            if [ $counter -gt 10 ]; then
                echo "[ERROR] 获取启动状态失败次数过多"
                return 1
            fi
            sleep 5
            continue
        elif [ "$boot_status" = "1" ]; then
            echo "[+] Android 启动成功完成"
            echo "[*] 系统就绪时间: $(date '+%Y-%m-%d %H:%M:%S')"
            return 0
        else
            if [ $((counter % 10)) -eq 0 ]; then
                echo "[-] 仍在等待启动...（已耗时 $((counter * 3)) 秒）"
            fi

            if [ $counter -gt $max_wait ]; then
                echo "[ERROR] 启动超时，经过 ${max_wait} 次尝试"
                return 1
            fi
        fi

        sleep 3
    done
}

# 函数: log_debug
# 用途: 记录调试信息（仅在启用调试模式时）
# 参数: $* = 消息文本
function log_debug() {
    echo "[DEBUG] $@" >> "$MODPATH/logs/utils.log"
}

# 函数: log_info
# 用途: 记录信息性消息
# 参数: $* = 消息文本
function log_info() {
    echo "[INFO] $@" >> "$MODPATH/logs/utils.log"
    echo "[-] $@"  # 同时打印到控制台
}

# 函数: log_error
# 用途: 记录错误消息
# 参数: $* = 消息文本
function log_error() {
    echo "[ERROR] $@" >> "$MODPATH/logs/utils.log"
    echo "[ERROR] $@"  # 同时打印到控制台
}

echo "[+] 所有实用函数加载成功"
echo ""

#EOF