# B06 环境真实候选入口接线

本轮补齐5296572审计明确留下的入口缺口；没有开放普通发布门槛。

## 实际生产调用链

--candidate-b06 加 user://test_b06_candidate/ 内显式测试profile，经NumericalRules.b06_candidate_enabled校验。Main营地出发调用Game.start_run，再由Main._on_run_started创建真实room；ExpeditionController.current_context添加既有b06_candidate标记。room._activate_expedition_content建立真实b06_mechanics后调用_configure_b06_environment。L31选择pilot，其余六房选择batch；环境fixture不参与这条路径。

room公开只读引用b06_environment。需要进程开关、B06 biome、candidate layout及layout_id/room_id/tide.room_id全部匹配。Helper完整验证资源后成功configure才隐藏MineBackdrop及旧floor/terrain/depth canvas；演员、props、投射物、反馈、预警、机关、交互UI与HUD不隐藏。无匹配或配置失败保留旧背景。两个helper新增资源/manifest/placement前置检查；没有改变几何数据。

旧helper同步free后再配置新helper，保存并精确恢复先前visibility和native_water_visual。换房、重新配置、错误重试、退树/再入树与释放均覆盖。

## 实机暴露的真实缺陷与修复

首次真实Main完整回归384检查、11失败：10次重载旧环境仍存活，另外1次为测试把重复访问房间总数误当唯一房间数。失败日志保留于 ../_test_output/B06/20261002T195534584725Z-bc7e1cb5。

发现Main._continue_game→_on_run_started在已有room时直接覆盖引用，原房及其环境留在world。现先停用、隐藏、同步remove_child旧room，再queue_free和清空引用，然后初始化新room。同步退出使旧props/环境清理先于新房恢复，避免延迟清理干扰新房；不改战斗规则。测试唯一房间计数修正为去重，实际路线仍包含重复进入房间，未绕过重复访问。

更早的195447690563Z-990633bd为测试WeakRef推断警告当错误，未进入场景；已补明确WeakRef类型并保留日志，不计通过。

## 验证分层

- tests/test_b06_environment_lifecycle：真实room候选开关开启556/0、不开关163/0，日志 ../_test_output/B06/20261002T195305191563Z-18891016。七房连续切换、初次ready、重配、无效layout/runtime、null工厂、configure=false部分配置失败/重试、精确visibility/native旧值恢复、退树/再入树、service退出与重建释放。无engine/script ERROR。
- 既有test_room_failure：179/0，日志 ../_test_output/B06/20261002T195856394175Z-16d23794。双语失败、存储失败必需Retry、恢复真实房间/HUD/移动、结果释放。该轮在补同步detach前执行，detach后的Main重入以最终图形回归为准。
- tests/test_b06_environment_main：真实scenes/main.tscn、营地出发、既有路由事务、磁盘reload/_continue_game、真实撤离，完全不手动创建helper或隐藏旧环境。保留完整HUD。每个房间三潮态和恢复截图，Boss另外P1；shader逐块对照生产湿区。先前房间helper弱引用须释放，当前须唯一，无flag仍保持关闭。

Main图形测试使用隔离存档预置前五Boss完成与Lv25，以真实候选门槛进入。清敌用明确致死fixture、三潮相由真实host.tick推进、房间process受控停止用于截图；不等同自然完整战斗、强度、帧率或操作手感验收。没有修改生产碰撞/攻击数值/时钟以通过视觉。

最终图形结果与像素审查见末尾登记。所有截图、日志和测试存档仅托管输出，不入Git。

第二轮195954147304Z-b31f03d0为472/0断言，但旧HUD在队列删除前仍有最后一次_process访问已退树room，产生10条get_canvas_transform engine ERROR，故不作为clean通过。现Main重建前同时停止旧HUD process并隐藏，再退旧room。最终再次完整回归，未用零断言失败掩盖engine ERROR。

## 最终干净Main回归与明确视觉缺陷

- 完整Main：../_test_output/B06/20261002T200222743812Z-ca08c88e，**472检查、0失败**，.complete，日志无ERROR。30张2560×1440，覆盖七种房间（实际12站含重复访问）、每房低/预警/高、磁盘恢复、Boss P1及营地候选入口。L31–L33及营地13张逐图审过；其余17张SHA256与前轮已逐图审过的同名图完全一致，沿用审查。没有旧环境叠层。
- 近机关补测：../_test_output/B06/20261002T200613365114Z-da176267，**410检查、0失败**，.complete，无ERROR。7张2560×1440均逐图审过，覆盖L32/L34/L36阀门、L35潮钟、Boss双阀和近Boss视角。近处F提示清楚；L35潮钟靠近后可见，角色自然遮住部分机关。
- 上述实际Main通过证明自动接线、持续进房、重载释放和同源水态，不代表HUD全可读性通过。

**剩余HUD缺陷已移交独立修复**：L35中心视角远北潮钟被顶部路线/房间信息板覆盖；BO06中心及近处视角首领上缘、名称/血条受顶部房间板及技库提示遮挡；L36预警上中箭头和下中箭头分别受房间板、技能托盘覆盖。L34右侧目标板遮部分南侧湿区。环境建筑未侵入这些位置，不能通过移动冻结机关或隐藏危险信息规避。HUD布局修复不包含本提交。

推荐可复查证据：完整批次l35-main-warning.png、l36-main-warning.png、bo06-main-high.png；靠近批次l35-main-approach-tide_bell.png、bo06-main-approach-boss_near.png。没有将这些有遮挡图作为全部视觉通过。
