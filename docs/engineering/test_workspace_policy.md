# 测试输出与临时目录规范

更新：2026-10-03。Windows 使用 `tools/test.ps1`；Linux 关卡采样使用 `tools/testing/test_workspace.py`。项目根由 `project.godot` 定位。

## Windows 入口

```powershell
./tools/test.ps1 -ImportOnly
./tools/test.ps1 -SkipImport -Suite hero_storybook_family,enemy_art,boss_hd_art
```

每次调用在 `tools/godot/test-runs/<run_id>` 创建独立档、APPDATA/LOCALAPPDATA 与日志，结束后恢复调用者的环境变量。套件从 `tools/testing/suites.json` 读取；退出码为零仍检查引擎与脚本错误。实际玩家档不进入测试或清理。

## Linux 入口

```sh
python tools/testing/test_workspace.py run --biome B05 -- bash -c 'godot --headless --path . --script res://tests/levels/b05/test_b05_root_network.gd -- --test-profile="$GAMES_TEST_OUTPUT_DIR/test_b05_root_network.json"'
python tools/testing/run_b06_foundation_tests.py --godot /path/to/godot --suites content
```

原始日志、截图、测量和隔离档放入 `artifacts/test_runs/<B05|B06>/<run_id>`；一次性项目与转换文件放入 `_tmp/test_runs/<B05|B06>/<run_id>`。管理器设置 `GAMES_TEST_OUTPUT_DIR`、`GAMES_TEST_TMP_DIR`、临时目录和 userdata 环境变量；运行场景仍须传入套件要求的 `--test-profile`。

管理器使用 Linux `fcntl` 与 `/tmp/games-godot.lock` 串行调用 Godot，外层不能再锁同一文件。它不是 Windows 入口；此次 Windows 整理只对其 Python 语法和路径改动做检查，Linux 路径保护测试需在 Linux 运行。

## 保留与清理

```sh
python tools/testing/test_workspace.py cleanup --biome B05 --keep 5
python tools/testing/test_workspace.py cleanup --biome B05 --keep 5 --apply --confirm-delete-managed-runs
```

默认只列出候选。执行清理须具有对应删除授权；管理器只处理 ID、marker 和完成状态匹配的批次，保留运行中、未完成、手工目录，拒绝路径穿越、符号链接及仓库元数据。Windows 输出由独立入口管理，不能套用 Linux 批次清理命令。

构建、缓存、临时档与重复截图不入库。保留正式资源、来源、许可与玩家存档。截图套件和自然采样各自声明输出位置、源码版本与运行环境；路径检查不能替代实际图形或自然玩法验收。

## B08 独立候选

B08 使用同一 `/tmp/games-godot.lock`，但测试输出与临时文件按本工作区的 `artifacts/test_runs/B08/<批次>` 和 `_tmp/test_runs/B08/<批次>` 隔离。入口为 `python tools/testing/run_b08_candidate.py`。不得写其他工作区缓存或真实档；清理仍须显式审阅授权。
