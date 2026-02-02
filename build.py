#!/user/bin/env python3
"""
MagiskFrida 构建模块

处理：
- 模块创建和配置
- 多架构的 Frida-server 下载和解压
- 模块打包和版本管理
- 并行处理以提高效率
"""

import logging
import lzma
import os
from pathlib import Path
import shutil
import threading
import zipfile
import concurrent.futures
import json
import re
import time

import requests

PATH_BASE = Path(__file__).parent.resolve()
PATH_BASE_MODULE: Path = PATH_BASE.joinpath("base")
PATH_BUILD: Path = PATH_BASE.joinpath("build")
PATH_BUILD_TMP: Path = PATH_BUILD.joinpath("tmp")
PATH_DOWNLOADS: Path = PATH_BASE.joinpath("downloads")

# 配置增强格式的日志记录
logger = logging.getLogger(__name__)
syslog = logging.StreamHandler()
formatter = logging.Formatter(
    "[%(levelname)s] %(threadName)s : %(asctime)s - %(message)s",
    datefmt='%H:%M:%S')
syslog.setFormatter(formatter)
logger.setLevel(logging.INFO)
logger.addHandler(syslog)


def download_file(url: str, path: Path):
    """
    从 URL 下载文件到指定路径
    
    参数:
        url: 远程文件 URL
        path: 保存的本地文件路径
        
    异常:
        requests.HTTPError: 如果下载失败
    """
    file_name = url[url.rfind("/") + 1:]
    logger.info(f"正在下载 '{file_name}'...")
    logger.debug(f"  URL: {url}")
    logger.debug(f"  目标位置: {path}")

    if path.exists():
        logger.info(f"  文件已存在，跳过下载: {file_name}")
        return

    try:
        start_time = time.time()
        r = requests.get(url, allow_redirects=True, timeout=30)
        r.raise_for_status()

        with open(path, "wb") as f:
            f.write(r.content)

        elapsed = time.time() - start_time
        file_size_mb = path.stat().st_size / (1024 * 1024)
        logger.info(
            f"  ✓ 下载完成: {file_size_mb:.2f} MB 用时 {elapsed:.1f}秒")

    except requests.exceptions.Timeout:
        logger.error(f"  ✗ {file_name} 下载超时")
        raise
    except requests.exceptions.RequestException as e:
        logger.error(f"  ✗ {file_name} 下载失败: {e}")
        raise
    except IOError as e:
        logger.error(f"  ✗ 写入文件 {path} 失败: {e}")
        raise


def extract_file(archive_path: Path, dest_path: Path):
    """
    解压 .xz 压缩文件到目标位置
    
    参数:
        archive_path: .xz 归档文件路径
        dest_path: 目标文件路径
        
    异常:
        lzma.LZMAError: 如果解压缩失败
        IOError: 如果文件操作失败
    """
    logger.info(f"正在解压 '{archive_path.name}'...")
    logger.debug(f"  源文件: {archive_path}")
    logger.debug(f"  目标位置: {dest_path}")

    try:
        start_time = time.time()
        with lzma.open(archive_path) as f:
            file_content = f.read()
            path = dest_path.parent

            path.mkdir(parents=True, exist_ok=True)

            with open(dest_path, "wb") as out:
                out.write(file_content)

        elapsed = time.time() - start_time
        file_size_mb = dest_path.stat().st_size / (1024 * 1024)
        logger.info(
            f"  ✓ 解压完成: {file_size_mb:.2f} MB 用时 {elapsed:.1f}秒"
        )

    except lzma.LZMAError as e:
        logger.error(f"  ✗ 解压缩失败: {e}")
        raise
    except IOError as e:
        logger.error(f"  ✗ 文件操作失败: {e}")
        raise


def generate_version_code(project_tag: str) -> int:
    """
    从标签生成数字版本代码 (12.7.5 -> 120705)

    参数:
        project_tag: 版本标签字符串

    返回:
        整数形式的数字版本代码
    """
    try:
        parts = re.split("[-.]", project_tag)
        version_code = "".join(f"{int(part):02d}" for part in parts)
        result = int(version_code)
        logger.debug(f"生成版本代码 {project_tag} -> {result}")
        return result
    except (ValueError, IndexError) as e:
        logger.error(f"无法为 {project_tag} 生成版本代码: {e}")
        raise


def create_module_prop(path: Path, project_tag: str):
    """
    创建 module.prop 配置文件
    
    参数:
        path: 模块目录路径
        project_tag: 版本标签
    """
    logger.info(f"正在创建版本为 {project_tag} 的 module.prop...")

    try:
        module_prop = f"""id=magisk-frida
name=MagiskFrida
version={project_tag}
versionCode={generate_version_code(project_tag)}
author=ViRb3 & enovella
updateJson=https://github.com/ViRb3/magisk-frida/releases/latest/download/updater.json
description=在启动时运行 frida-server"""

        prop_file = path.joinpath("module.prop")
        with open(prop_file, "w", newline="\n") as f:
            f.write(module_prop)

        logger.info(f"  ✓ module.prop 创建成功")
        logger.debug(f"  版本代码: {generate_version_code(project_tag)}")

    except IOError as e:
        logger.error(f"  ✗ 创建 module.prop 失败: {e}")
        raise


def create_module(project_tag: str):
    """
    通过复制模板和设置版本来创建基础模块结构
    
    参数:
        project_tag: 版本标签
    """
    logger.info("正在创建模块结构...")
    logger.debug(f"  基础模板: {PATH_BASE_MODULE}")
    logger.debug(f"  构建目标: {PATH_BUILD_TMP}")

    try:
        if PATH_BUILD_TMP.exists():
            logger.info("  正在清理之前的构建...")
            shutil.rmtree(PATH_BUILD_TMP)

        logger.info("  正在复制模板文件...")
        shutil.copytree(PATH_BASE_MODULE, PATH_BUILD_TMP)

        create_module_prop(PATH_BUILD_TMP, project_tag)
        logger.info("  ✓ 模块结构创建成功")

    except Exception as e:
        logger.error(f"  ✗ 创建模块失败: {e}")
        raise


def fill_module(arch: str, frida_tag: str, project_tag: str):
    """
    为特定架构下载和解压 Frida-server
    
    参数:
        arch: CPU 架构 (arm, arm64, x86, x86_64)
        frida_tag: Frida 版本标签
        project_tag: 项目版本标签
    """
    threading.current_thread().setName(arch)
    logger.info(f"[{arch}] 正在为架构填充模块...")

    try:
        frida_download_url = (
            f"https://github.com/frida/frida/releases/download/{frida_tag}/")
        frida_server = f"frida-server-{frida_tag}-android-{arch}.xz"
        frida_server_path = PATH_DOWNLOADS.joinpath(frida_server)

        logger.info(f"[{arch}] 正在下载 Frida {frida_tag} 用于 {arch}...")
        download_file(frida_download_url + frida_server, frida_server_path)

        files_dir = PATH_BUILD_TMP.joinpath("files")
        files_dir.mkdir(exist_ok=True)

        logger.info(f"[{arch}] 正在解压 Frida-server...")
        extract_file(frida_server_path,
                     files_dir.joinpath(f"frida-server-{arch}"))

        logger.info(f"[{arch}] ✓ 完成成功")

    except Exception as e:
        logger.error(f"[{arch}] ✗ 失败: {e}")
        raise


def create_updater_json(project_tag: str):
    """
    创建 Magisk 模块更新器配置
    
    参数:
        project_tag: 版本标签
    """
    logger.info(f"正在为版本 {project_tag} 创建 updater.json...")

    try:
        updater = {
            "version":
            project_tag,
            "versionCode":
            generate_version_code(project_tag),
            "zipUrl":
            f"https://github.com/ViRb3/magisk-frida/releases/download/{project_tag}/MagiskFrida-{project_tag}.zip",
            "changelog":
            "https://raw.githubusercontent.com/ViRb3/magisk-frida/master/CHANGELOG.md",
        }

        updater_file = PATH_BUILD.joinpath("updater.json")
        with open(updater_file, "w", newline="\n") as f:
            f.write(json.dumps(updater, indent=4))

        logger.info("  ✓ updater.json 创建成功")
        logger.debug(f"  更新 URL: {updater['zipUrl']}")

    except IOError as e:
        logger.error(f"  ✗ 创建 updater.json 失败: {e}")
        raise


def package_module(project_tag: str):
    """
    创建 Magisk 模块 ZIP 包
    
    参数:
        project_tag: 版本标签
    """
    logger.info(f"正在将模块打包为 MagiskFrida-{project_tag}.zip...")

    try:
        module_zip = PATH_BUILD.joinpath(f"MagiskFrida-{project_tag}.zip")

        file_count = 0
        with zipfile.ZipFile(module_zip, "w",
                             compression=zipfile.ZIP_DEFLATED) as zf:
            for root, _, files in os.walk(PATH_BUILD_TMP):
                for file_name in files:
                    if file_name == "placeholder" or file_name == ".gitkeep":
                        continue

                    file_path = Path(root).joinpath(file_name)
                    arcname = Path(root).relative_to(PATH_BUILD_TMP).joinpath(
                        file_name)
                    zf.write(file_path, arcname=arcname)
                    file_count += 1

        zip_size_mb = module_zip.stat().st_size / (1024 * 1024)
        logger.info(
            f"  ✓ 包创建完成: {zip_size_mb:.2f} MB ({file_count} 个文件)")
        logger.debug(f"  位置: {module_zip}")

        logger.info("  正在清理临时文件...")
        shutil.rmtree(PATH_BUILD_TMP)
        logger.info("  ✓ 清理完成")

    except Exception as e:
        logger.error(f"  ✗ 打包模块失败: {e}")
        raise


def do_build(frida_tag: str, project_tag: str):
    """
    为所有架构执行完整的构建过程
    
    参数:
        frida_tag: Frida 版本标签
        project_tag: 项目版本标签
    """
    logger.info("=" * 70)
    logger.info("开始构建流程")
    logger.info("=" * 70)
    logger.info(f"Frida 版本: {frida_tag}")
    logger.info(f"项目版本: {project_tag}")
    logger.info(f"构建目录: {PATH_BUILD}")
    logger.info("=" * 70)

    try:
        # 准备目录
        logger.info("正在准备构建目录...")
        PATH_DOWNLOADS.mkdir(parents=True, exist_ok=True)
        PATH_BUILD.mkdir(parents=True, exist_ok=True)
        logger.info("  ✓ 目录准备就绪")

        # 创建模块结构
        create_module(project_tag)

        # 为所有架构构建
        logger.info("正在为架构构建: arm, arm64, x86, x86_64")
        archs = ["arm", "arm64", "x86", "x86_64"]
        executor = concurrent.futures.ProcessPoolExecutor(
            max_workers=len(archs))
        futures = [
            executor.submit(fill_module, arch, frida_tag, project_tag)
            for arch in archs
        ]

        completed = 0
        for future in concurrent.futures.as_completed(futures):
            exception = future.exception()
            if exception is not None:
                logger.error(f"架构构建失败: {exception}")
                raise exception
            completed += 1
            logger.info(
                f"架构构建完成: {completed}/{len(archs)}")

        # 打包和最终化
        package_module(project_tag)
        create_updater_json(project_tag)

        logger.info("=" * 70)
        logger.info("✓ 构建成功完成")
        logger.info("=" * 70)
        logger.info(f"模块: MagiskFrida-{project_tag}.zip")
        logger.info(
            f"位置: {PATH_BUILD.joinpath(f'MagiskFrida-{project_tag}.zip')}"
        )
        logger.info("=" * 70)

    except Exception as e:
        logger.error("=" * 70)
        logger.error(f"✗ 构建失败: {str(e)}")
        logger.error("=" * 70)
        raise