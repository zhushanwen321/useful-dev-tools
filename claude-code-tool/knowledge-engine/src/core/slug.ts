import { existsSync, statSync } from 'node:fs'
import { join } from 'node:path'

// 用户主目录前缀，用于从绝对路径中去除以生成 slug
const HOME_PREFIX = '/Users/'

/**
 * 将项目绝对路径转换为 slug 标识符
 * 规则：去掉前导 /Users/，路径分隔符替换为 -，保留原始大小写
 */
export function projectPathToSlug(projectPath: string): string {
  // 规范化路径，去除末尾斜杠
  const normalized = projectPath.replace(/\/+$/, '')

  // 去掉 /Users/ 前缀
  const withoutHome = normalized.startsWith(HOME_PREFIX)
    ? normalized.slice(HOME_PREFIX.length)
    : normalized

  // 路径分隔符替换为 -，保留大小写
  return withoutHome.replace(/\//g, '-')
}

/**
 * 从指定目录向上查找 .git 目录，确定项目根路径
 * 找到返回根路径，找不到返回 null
 */
export function findProjectRoot(startDir: string): string | null {
  let current = startDir

  while (current !== '/') {
    if (existsSync(join(current, '.git'))) {
      return current
    }

    const parent = join(current, '..')

    // 防止无限循环：如果父目录和当前目录相同（已到达文件系统根），停止
    if (statSync(current).ino === statSync(parent).ino) {
      break
    }

    current = parent
  }

  // 检查根目录本身
  if (existsSync(join('/', '.git'))) {
    return '/'
  }

  return null
}
