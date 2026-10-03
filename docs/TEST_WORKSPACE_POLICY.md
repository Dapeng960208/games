# 测试输出与临时目录规范

适用于当前 dot 云端 `games-recovery`，B05/PR7 与 B06/PR8 共用现有 `repository.git`。不新建容器、克隆或复制正式资源库。

## 路径

- 原始测试日志、截图、测量 JSON、合成隔离档：`games-recovery/_test_output/B05/<UTC时间-随机ID>/`，B06 同理。
- 一次性无 autoload 小项目、临时转换和 Python 临时文件：`games-recovery/_tmp/B05/<同一ID>/`，B06 同理。
- 正式源码、正式美术、prompt、许可证、设计文档和玩家存档/备份仍在原位置；它们不是清理目标。
- worktree 的 `.godot/` 是必要引擎缓存，单独管理，不在此清理脚本范围。不要为每次检查复制整仓库或正式美术。
- 最终有意义的 QA 样例如需长期保留，应经确认选取并单独归档；原始重复截图留在测试目录，不批量提交。

## Linux 入口

在 b05 或 b06 worktree 中运行：

```sh
python tools/test_workspace.py run --biome B05 -- bash -c 'godot --headless --path . --script res://tests/test_b05_root_network.gd -- --test-profile="$GAMES_TEST_OUTPUT_DIR/test_b05_root_network.json"'
python tools/test_b05_root_network.py --suite root_network
# B06 的基础入口同样自动使用管理器
python tools/run_b06_foundation_tests.py --godot /path/to/godot --suites content
```

管理器设置 `GAMES_TEST_OUTPUT_DIR`、`GAMES_TEST_TMP_DIR`、`TMPDIR/TMP/TEMP`、XDG 和 Windows 风格 userdata 环境变量，保存 `console.log`。自定义输出必须显式使用上述环境变量；绝对硬编码路径不会被环境变量魔法重写。生产场景还必须传入各套件要求的 `--test-profile`，不能读真实玩家档。

所有 Godot 导入、无界面检查和图形检查使用同一个 `/tmp/games-godot.lock`。管理器已获取 flock，禁止在外层再获取同一锁后运行管理器，否则会死锁。没有使用管理器的旧命令必须显式 `flock /tmp/games-godot.lock ...`；迁移后优先统一入口。锁只对遵守规范的命令生效，不会强制终止已有引擎。

## 保留与清理

```sh
# 默认只列出超过最近5个已完成批次的候选；不会删除
python tools/test_workspace.py cleanup --biome B05
python tools/test_workspace.py cleanup --biome B06 --keep 3
# 仅在审阅清单、取得相应删除授权后执行
python tools/test_workspace.py cleanup --biome B05 --keep 5 --apply --confirm-delete-managed-runs
```

按批次保留上限可通过 `--keep` 调整；这不是磁盘字节硬上限。没有自动删除定时任务。清理只能处理这两个专用根下、ID和marker都匹配的已完成批次；运行中锁定、异常中断未完成、手工目录均保留。拒绝路径穿越、符号链接、缺失/错误marker；不删除专用根自身、worktree、`.git` 或 `repository.git`。活动输出不可改名或删锁文件。中断残留须先确认没有进程使用，再单独审阅，不能只靠时间自动认定死亡。

## 当前迁移边界

已接入：两个 worktree 的 B05 Python 纯逻辑入口、B06基础入口、B05 codex/environment pilot/monster pose三类截图输出。B05装备美术输出原本随 `--test-profile` 所在目录，运行时须将 profile 设在管理目录中。

尚未整体迁移：Windows `tools/test.ps1` 仍使用 `tools/godot/test-runs`；旧 B01–B04 等历史 GDScript 中仍有 `res://artifacts` 路径；历史手动命令和现存 `/tmp` 输出不自动迁移或删除。Windows入口不是本Linux规范的已验证入口。运行旧截图套件前先检查并改其输出路径，不能据管理器存在宣称所有测试完成迁移。

验证范围：`tools/test_workspace_paths.py` 检查路径拒绝、符号链接、默认dry-run、保留数量、活跃/未完成批次保护；不运行全游戏回归。修改后的图形捕获仍需实际调用时验证，不据路径检查宣称视觉验收通过。


## B08 独立候选

B08 复用同一 `repository.git` 和全局 `/tmp/games-godot.lock`；输出与临时目录分别为 `_test_output/B08/<批次>/` 和 `_tmp/B08/<批次>/`。`python tools/run_b08_candidate.py` 只做当前首切片定向无界面检查，无可见游戏与自动清理。已有缓存可只读复用，但不得共享 `.godot` 根或通过 editor/import 写原 worktree 缓存；正式资源不复制，真实存档不读取/写入。B08 清理仍必须显式审阅与授权。
