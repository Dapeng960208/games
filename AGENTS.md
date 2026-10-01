# 工作区约定

先阅读 docs/DEVELOPMENT_PROGRESS.md、docs/LEVEL_ROADMAP.md 和 docs/DEVELOPMENT_STANDARDS.md；需求以用户最新指令为准，不能把目标设计当作已实现功能。

Windows 中文 Markdown 必须使用 UTF-8：读取用 Get-Content -Encoding UTF8；必要时设置控制台 UTF-8，或使用 System.IO.File.ReadAllText 配合 UTF8Encoding。

若仓库根存在 .codegraph/，理解或定位代码时优先 CodeGraph explore；没有则跳过，不自行索引。普通文本与文件搜索优先 rg。

按用户授权范围开发。减少无意义测试与 review，只做变更直接相关的检查。已完成工作按责任提交，方便 diff；缓存、下载、构建、隔离存档和截图副本不入库。

固定房间设计 JSON 与运行 JSON 不同，草稿只能按字段合并，禁止整房覆盖而丢失种族、首领机关和奖励字段。清理资源前核对动态引用和兼容回退，保留玩家存档、来源与版权。
