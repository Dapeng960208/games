# 现有定向检查

本目录保存开发过程中已有的检查源码及场景，便于复现和回归；本次整理未新增或批量运行这些检查。部分历史检查反映旧操作和旧 UI，不能将其全部当作当前发布门槛。

使用 tools/test.ps1 的 -Suite 指定与改动有关的检查。当前操作可用 new_controls 或 control_settings；路线页可用 route_journal。前四关的种族、掉落、首领、机关、遗物和死亡检查由 tools/verify_first_four.ps1 按需运行。

脚本会在 tools/godot/test-runs 中创建隔离存档与日志。运行产物不入 Git，实际玩家存档不参与检查。资源或脚本整理可只做 -ImportOnly，界面与打击感变化补短段实机观察，不默认执行所有历史脚本。最新完成记录和限制见 docs/DEVELOPMENT_PROGRESS.md。
