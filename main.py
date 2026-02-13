#!/user/bin/env python3
"""
MagiskFrida 构建流程编排器

流程：
1. 检查项目是否有与 frida 标签匹配的标签
   是 -> 继续
   否 -> 必须打标签
2. 检查是否设置了 FORCE_RELEASE 环境变量（GitHub Actions）
   是 -> 必须打标签
   否 -> 继续
如果需要打标签，将新标签写入 'NEW_TAG.txt' 并开始构建
否则，不执行任何操作并使用占位符标签进行构建
3. 仅当 'NEW_TAG.txt' 存在时才会执行部署

注意：需要 git
"""

import build
import util
import os
import logging
import sys

# 配置日志记录
logging.basicConfig(level=logging.INFO,
                    format='[%(levelname)s] %(asctime)s - %(message)s',
                    datefmt='%Y-%m-%d %H:%M:%S')
logger = logging.getLogger(__name__)


def main():
    try:
        logger.info("=" * 60)
        logger.info("开始 MagiskFlorida 构建流程")
        logger.info("=" * 60)

        # 获取版本信息
        logger.info("正在获取 Florida 最新版本...")
        last_frida_tag = util.get_last_frida_tag()
        logger.info(f"✓ 最新 Florida 版本: {last_frida_tag}")

        logger.info("正在获取 MagiskFlorida 项目最新版本...")
        last_project_tag = util.get_last_project_tag()
        logger.info(f"✓ 最新项目版本: {last_project_tag}")

        new_project_tag = "0"

        # 检查版本更新或强制发布
        force_release = os.getenv('FORCE_RELEASE', 'false').lower() == 'true'
        needs_update = last_frida_tag != util.strip_revision(last_project_tag)

        logger.info(f"启用强制发布: {force_release}")
        logger.info(f"需要版本更新: {needs_update}")

        if needs_update or force_release:
            logger.info("正在计算新的项目版本...")
            new_project_tag = util.get_next_revision(last_frida_tag)
            logger.info(f"✓ 新版本计算完成: {new_project_tag}")

            if needs_update:
                logger.info(
                    f"原因: Florida 从 {util.strip_revision(last_project_tag)} 更新到 {last_frida_tag}"
                )
            else:
                logger.info("原因: 通过 GitHub Actions 请求强制发布")

            # 写入新标签用于部署
            logger.info("正在将新标签写入 NEW_TAG.txt 用于部署...")
            with open("NEW_TAG.txt", "w") as the_file:
                the_file.write(new_project_tag)
            logger.info("✓ NEW_TAG.txt 写入成功")
        else:
            logger.info("✓ 所有版本都是最新的 - 无需更新")

        # 开始构建流程
        logger.info("=" * 60)
        logger.info("开始模块构建...")
        logger.info("=" * 60)
        build.do_build(last_frida_tag, new_project_tag)

        logger.info("=" * 60)
        logger.info("✓ 构建流程成功完成")
        logger.info("=" * 60)

    except Exception as e:
        logger.error("=" * 60)
        logger.error(f"✗ 构建流程失败: {str(e)}", exc_info=True)
        logger.error("=" * 60)
        sys.exit(1)


if __name__ == "__main__":
    main()
