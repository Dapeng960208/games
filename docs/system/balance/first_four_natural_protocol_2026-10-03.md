# B01–B04最低入口等级自然整章协议

> 状态：当前参考：具体已实现范围以开发进度和运行代码为准。

用户最新要求：只有B01的D0–D2允许无装备通过；B01 D3–D4、B02–B04 D0–D4不应裸装完整通过。允许不等于强制保证通关。所有测试从各章最低等级开始：1、6、11、16；不采用章末等级。

## 运行路径与控制

`tests/balance/test_first_four_natural_chapter.gd`独立适配现有B05整章观察器。使用真实生产房间、AI、有限波次、机关、伤害、技能解锁、资源支付、冷却、掉落、路线和结算。控制器每0.1秒读取可见危险并提出合法移动/闪避/技能；物理/枪手保持合法普攻，法师普攻为零。不是人类游玩，也不是站桩或强制命中试验。

- 使用正式前四章入口，并显式传入测试专用`--enemy-species-candidate=15`与隔离`user://test_...`路径以冻结archive15；默认生产仍14。无需B05/B06章节candidate开关。否则拒收结果。
- 同一player连续逐房，转换必须保持绝对HP/资源/冷却，不重置或加血；通过原生API跳过遗物，原生skip最多6%恢复单列记录；不购买补给、不人为激活机制或击杀。
- 只在原生房间完成后选下一合法路线（房ID字典序首项），不跳过生成路线节点；击败最终Boss后实际extracted结算。
- run等级和永久profile等级分别逐房记录。保留原生XP和run等级变化，不写入提高测试等级，也不掩盖永久等级变化。已实测B02最低Lv6出发后在第三房自然升7、Boss结算升8，因此最低等级指入口，不能把该Boss样本标作Lv6交战。
- 裸装零实例、零套装/装备proc，无遗物/购买Buff。奖励留在原生pending中，不装备。正常装备在入口冻结持有，测试不伪称已通过自然获取路线。

## 合法装备夹具

不用旧S11模板表。按当前生产本章natural_pool、职业可穿规则选择每槽首个合法模板，实例等级等于角色最低入口等级；所有实例须经Instances.create与can_equip通过。

- 裸装：八槽空。
- green0：八件绿+0，仅低配补充。
- G2：八件金+2、4词缀。
- P5：八件紫+5、3词缀。

每件主属性/词缀50分位，强化每步10%并保留规范价格记录；合法词缀按当前注册顺序选取。G2/P5是已持有配装标尺，不证明最低等级已能自然获取/锻造这些物品。天赋按mastery、precision、dexterity、vitality、resistance、agility依序分配到合法rank cap，用满入口等级点数；分支保持默认未选。实际技能必须通过生产等级/资源/冷却门槛。

48组当前合法夹具已通过97项短检查，0失败；此不是archive15自然战斗验收。

## 批次、停止与判定

每命令只跑一个职业/章节/难度/配装/种子，完成释放共享Godot锁。先B01 D2/D3与B02 D0三职业裸装边界，禁区裸通立即报告；随后补各章其他D与必要的正常G2/P5对照。不能把一个种子推广成全种子结论。

自然死亡或完整结算为终局。观察时间上限/控制器导航/任务无进展单独记为未决，不能当作“不能通关”；遇到这些结果要诊断/延长或修复控制器后重新验证。完整Boss时长仅从连续章流程最终Boss房统计，完整章耗时不能混作Boss时长。

```sh
python tools/balance/run_first_four_natural.py --chapter 1 --difficulty 3 --hero CH03 --equipment naked --seed 1001
```

工具自动进入B05工作树的托管QA批次（管理器目前只接受B05/B06），并保存协议、精确传递依赖闭包的源码hash、原始观察/技能支付/收伤、引擎日志、总结。文档和无关测试不纳入源码闭包。不得外层再加同一flock。

## 准备状态

生产于b222dcbf885ce57b996ad0ba72f43399471f28ac整体冻结后开始分场实测；结果另记验收报告。入口暴击检查走真实RunState setter：先赋冻结snapshot15，再赋Resolver统计，验证crit_policy_version=1及裸基准25%/2倍；上限使用版本化CritPolicy的100%/3倍，不改仍供旧档使用的默认Resolver或旧JSON caps。正式run与独立policy处理后的合法夹具核对。freeze后重新解析97项通过，首场真实new_run与snapshot15/暴击检查通过。97项仅为合法夹具检查，不冒充自然战斗通过。

首批命令每场独立执行（按当前可用锁顺序，不一次持锁包下整批）：

```sh
python tools/balance/run_first_four_natural.py --chapter 1 --difficulty 2 --hero CH01 --equipment naked --seed 1001
python tools/balance/run_first_four_natural.py --chapter 1 --difficulty 3 --hero CH01 --equipment naked --seed 1001
python tools/balance/run_first_four_natural.py --chapter 2 --difficulty 0 --hero CH01 --equipment naked --seed 1001
```

对应CH02/CH03同样三组。若禁区出现整章裸通，先报告反例再决定后续调校/回归；仅自然死亡的种子样本不推广成数学上绝无裸通。

控制器适配v1识别前四章普通房生产目标的attackable或breakable字段；只提交正常攻击/技能，不直接扣目标HP或完成机关。每60模拟秒输出活敌/击杀/HP/目标HP；连续90秒无战斗、目标、位置进展保存未决并让出共享锁，诊断后修测试再重跑。
