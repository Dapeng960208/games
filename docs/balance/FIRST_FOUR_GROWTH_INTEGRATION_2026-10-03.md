# B01–B04 archive14 正式入口定向回归

## 已验证

2026-10-03，生产数值源为 `aca0c65e05481015029a17789905b1d66efbdd86`，运行时 HEAD `59f2ac22819549e4ed27ff1bf87d18c64268450f`；两者的 scripts/config/data 无差异。Godot 4.6.3 headless，未启用 candidate，隔离合成档。`test_first_four_growth_integration` **2457 项，0 失败**。

- 三职业真实 `new_profile → select_hero → start_run` 使用 archive14；等级1、正常初始HP/资源、每职业6件可穿starter均保留，腿/戒仍空槽。
- 真实 `save_expedition_checkpoint → reload_profile` 保持受伤HP/资源：CH01 1526/199，CH02 1319/999，CH03 1293/1199；完整已提交receipt恢复一致。
- 合成归档1–14分别经生产保存/重载，均保持自己的合法冻结标尺，受伤1234HP/321资源不回满、不升级。
- 每版B01–B04入口/尾级、D0/D4、普通/精英，共448个真实room.spawn_enemy，HP/攻击/护甲/魔抗与指定归档工厂精确一致；112个Boss配置端点也保持相应归档数值。
- archive14的32个普通/精英端点各承受100物理、100魔法包，64次真实take_damage扣血吻合相应双防结算，无忽略护甲/魔抗或二次缩放。
- 24个当前版本、本章room奖励生成事件均成功生成合法、职业相容实例。21件当前等级可穿；3件正常等级门槛暂不可穿：CH01 B02 Lv6→物品Lv7 EQ05；CH01 B03 Lv11→物品Lv12 EQ08；CH02 B02 Lv10→物品Lv11 EQ02。测试不放宽生产门槛，也不声称所有奖励即刻可穿。

## 夹具修正和边界

首轮测试发现嵌套Dictionary的JSON float与int直接比较不适合作为归档一致性断言，改为生产 `Calibration.valid` 对照不可变归档内容并核对版本。受伤保存使用真实checkpoint API，不把普通receipt安全边界行为误判成回血。

没有沿用旧S11非法配装，也没有静默替换其装备后复用旧结论。本套测试直接使用当前原生starter和生产room奖励实例；未修改任何生产数值、starter、掉落或装备路线。

这是生成/保存/真实actor与有限受击链检查；room自动生成、AI持续战斗和图形绘制被禁用。**不证明三职业连续整关自然平衡、裸装整关失败标准、早期游玩容错、Boss战时长或实际图形性能已验收。** 单调性由相邻的shared_enemy_growth专项检查覆盖，本套不重复扩成长矩阵。旧档验证为合成已知版本存档，不是读取真实玩家历史档。

## 复现和证据

```sh
python tools/test_workspace.py run --biome B05 -- bash -c 'godot --headless --path . res://tests/test_first_four_growth_integration.tscn -- --test-profile="$GAMES_TEST_OUTPUT_DIR/test_first_four_growth_integration.json"'
```

管理器仅支持B05/B06，这里的B05是统一工作树QA存储批次，不表示只测第五章。使用管理器内置单锁，无外层flock。

原始结果：`games-recovery/_test_output/B05/20261002T235837321230Z-4bdcfc69/first_four_growth.json` 与同目录console.log。测试输出、合成存档不入Git。

生产输入审计指纹：scripts/config/data下236个`.gd`/`.json`按路径排序，每文件`路径UTF-8 + NUL + 内容 + NUL`计算SHA256为 `457a4ba784bda6def1e9d31d99e6186c9f568755d1cfda48aae0751b372251aa`。此为保守生产源集（包括未走到的模块），文档/测试/导入缓存不纳入。
