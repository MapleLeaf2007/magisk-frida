"""
MagiskFrida 构建系统的实用函数

提供以下功能的工具：
    GitHub API 交互（获取标签、管理发布版本）
    Git 命令执行
    版本标签的管理与排序
"""

import re
import requests
import subprocess
import logging

# 配置日志记录
logger = logging.getLogger(__name__)


def strip_revision(tag: str) -> str:
    """
    从标签中提取基础版本号（例如，将 12.7.5-2 转换为 12.7.5）
    
    参数:
        tag: 版本标签字符串
        
    返回:
        不带修订号的基础版本
    """
    result = tag.split('-', 1)[0]
    logger.debug(f"去除修订号: {tag} -> {result}")
    return result


def get_last_github_tag(project_name: str) -> str:
    """
    从 GitHub 项目获取最新发布标签
    
    参数:
        project_name: GitHub 项目名称，格式为 'owner/repo'
        
    返回:
        最新发布标签名称
        
    异常:
        requests.HTTPError: 如果 API 请求失败
        KeyError: 如果响应格式异常
    """
    try:
        logger.info(f"正在获取 {project_name} 的最新 GitHub 标签...")
        releases_url = f"https://api.github.com/repos/{project_name}/releases/latest"

        r = requests.get(releases_url, timeout=10)
        r.raise_for_status()
        logger.debug(f"GitHub API 响应状态: {r.status_code}")

        releases = r.json()
        last_release = releases["tag_name"]
        logger.info(f"✓ {project_name} 的最新标签: {last_release}")
        return last_release

    except requests.exceptions.Timeout:
        logger.error(f"获取 {project_name} 时超时")
        raise
    except requests.exceptions.RequestException as e:
        logger.error(f"获取 {project_name} 时发生 HTTP 错误: {e}")
        raise
    except KeyError as e:
        logger.error(f"意外的 GitHub API 响应格式: {e}")
        raise


def get_last_frida_tag() -> str:
    """
    获取最新的 Frida 发布标签
    
    返回:
        最新的 Frida 版本标签
    """
    logger.info("=" * 50)
    logger.info("正在获取 Frida 发布信息")
    logger.info("=" * 50)
    try:
        last_frida_tag = get_last_github_tag('frida/frida')
        logger.info(f"✓ 最后一个 frida 标签: {last_frida_tag}")
        return last_frida_tag
    except Exception as e:
        logger.error(f"获取 Frida 标签失败: {e}")
        raise


def get_last_project_tag() -> str:
    """
    获取最新的 MagiskFrida 项目发布标签
    
    返回:
        最新的项目版本标签
    """
    logger.info("=" * 50)
    logger.info("正在获取 MagiskFrida 项目发布信息")
    logger.info("=" * 50)
    try:
        last_tag = get_last_tag([])
        logger.info(f"✓ 最后一个项目标签: {last_tag}")
        return last_tag
    except Exception as e:
        logger.error(f"获取项目标签失败: {e}")
        raise


def sort_tags(tags: list) -> list:
    """
    按升序排列版本标签（例如，1.11 > 1.9）
    
    参数:
        tags: 版本标签字符串列表
        
    返回:
        排序后的标签列表
    """
    tags = tags.copy()
    try:
        tags.sort(key=lambda s: list(map(int, re.split(r"[\.-]", s))))
        logger.debug(f"已排序 {len(tags)} 个标签")
        return tags
    except ValueError as e:
        logger.error(f"标签排序失败: {e}")
        raise


def get_last_tag(filter_args: list) -> str:
    """
    获取最新的 git 标签，支持可选过滤
    
    参数:
        filter_args: 额外的 git 标签过滤参数
        
    返回:
        最新的匹配标签名称，如果没有找到标签则返回空字符串
    """
    try:
        logger.debug(f"正在获取带有过滤器的最后一个标签: {filter_args}")
        tags = exec_git_command(["tag", "-l"] + filter_args).splitlines()
        logger.debug(f"找到 {len(tags)} 个标签")

        last_tag = "" if len(tags) < 1 else sort_tags(tags)[-1]
        logger.debug(f"最新标签: {last_tag if last_tag else '(无)'}")
        return last_tag

    except Exception as e:
        logger.error(f"获取 git 标签时出错: {e}")
        raise


def exec_git_command(command_with_args: list) -> str:
    """
    执行 git 命令并返回标准输出
    
    参数:
        command_with_args: 命令参数列表（不包含 'git' 前缀）
        
    返回:
        命令输出字符串
        
    异常:
        subprocess.CalledProcessError: 如果 git 命令失败
    """
    try:
        logger.debug(f"正在执行 git 命令: {' '.join(command_with_args)}")
        result = subprocess.run(["git"] + command_with_args,
                                capture_output=True,
                                text=True,
                                timeout=30)

        if result.returncode != 0:
            logger.error(f"Git 命令失败: {result.stderr}")
            raise subprocess.CalledProcessError(result.returncode,
                                                command_with_args,
                                                result.stderr)

        logger.debug(f"Git 命令执行成功")
        return result.stdout

    except subprocess.TimeoutExpired:
        logger.error("Git 命令超时")
        raise
    except Exception as e:
        logger.error(f"执行 git 命令失败: {e}")
        raise


def get_next_revision(current_tag: str) -> str:
    """
    计算下一个修订标签（例如，12.7.5-1, 12.7.5-2, ...）
    
    参数:
        current_tag: 当前版本标签
        
    返回:
        下一个可用的修订标签
    """
    logger.info(f"正在计算基础标签的下一个修订版: {current_tag}")
    try:
        i = 1
        while True:
            new_tag = f"{current_tag}-{i}"
            logger.debug(f"检查标签是否存在: {new_tag}")

            if get_last_tag([new_tag]) == '':
                logger.info(f"✓ 下一个可用修订版: {new_tag}")
                return new_tag

            i += 1
            if i > 1000:  # 安全检查以防止无限循环
                logger.error("修订号超过安全限制 (1000)")
                raise RuntimeError("修订版本过多")

    except Exception as e:
        logger.error(f"计算下一个修订版失败: {e}")
        raise