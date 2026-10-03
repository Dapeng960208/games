# 深渊拾荒者 Abyss Salvager

Godot 4 单人动作游戏原型。当前正常入口开放 **B01–B06、战士／枪手／法师**；B10 星辉龙庭已登记为第十章及最终章，使用 Lv46／48／50，等级上限为 50。B10 保留 BO09 通关解锁条件，B07、B08 未实现且 B09 仍为隔离候选，因此当前正常流程不能连通终章；本轮终章统一验收使用隔离存档。内容状态以 [开发进度](docs/DEVELOPMENT_PROGRESS.md) 和运行配置为准，资源接入不代表验收通过。

明亮手绘卡通奇幻风，高机位三分之四斜俯视与 2.5D 质感；界面使用米白羊皮纸、黄铜、深紫文字和圆形技能徽章。

## 当前可玩范围

| 内容 | 已接入范围 | 待完成或待验证 |
|---|---|---|
| 职业 | 三职业、各十二技能任选四个，营地配置／出征冻结，职业被动、成长与连击反馈 | 全方向连续动作、可见换装、自然群战手感 |
| 基础正式六关 | 36 个普通房与 6 个首领场地；普通怪分别 9／12／15／18／18／18 种，共 90 种；6 名首领 | 长时间游玩、全种子自然平衡与硬件性能 |
| B10 最终章 | L55–L60 六守关龙房、BO10 单头星冠古龙、18 种普通怪；Lv46／48／50，保留 BO09 通关解锁条件 | 本轮统一验收中；当前正常路线尚不能连通终章，验收使用隔离存档 |
| 装备 | 基础六章 194 模板／22 套，最终 B10 另有 35 自然模板／4 套与一枚一次性彩蛋戒指（合计 230 模板）、八槽独立实例、白绿紫金品质、随机词条、购买／打造、强化、重锻、重铸、精炼、继承、出售／拆解 | 自然获取时长及高难度构筑平衡；药品未实现 |
| 房间表现 | 基础六章 42 房独立原画；B10 七房各有独立 background 与六片原生 detail，背景、边界、物件脚点和镜头共用坐标映射；脚点排序、遮挡淡化与演员资源注册沿用现有管线 | B10 像素预算、无拉伸／无放大与全部房间图形验收进行中；显存流式加载未实现 |
| 保存 | 检查点、一次结算、写入互斥、七天回收站；当前格式继续读写 | 旧格式只保留原始备份并从新进度开始 |

当前默认采用新数值规则。死亡扣本局 50% 金币、丢弃未结算经验与临时装备，保留已有等级、已结算经验与永久装备；成功撤离后新装备永久入库。换装不会回血、重置冷却或重复发奖。本次正式开放不修改敌人校准、掉落概率或伤害规则。B05/B06 当前原画验收见 [全房原画与共用坐标](docs/levels/b05_b06_room_paintings.md)，开放与保存兼容见 [正式接入记录](docs/levels/b05_b06_release.md)。

B09 为**隔离候选／地图与 2K 受控接入验收通过**：18 种普通怪、霜晶女王、七房有限遭遇与 35 装备运行链已接入。地图使用七张 background、42 张逐片原生高清 detail 和共用环境／镜头管线；职业头像、HP／资源条与底部技能栏复用既有 HUD。合并后的机制、装备、正式闸门及地图路径检查通过；合并后新地图 GPU 247 项通过。自然通关、完整设计、连续动画与长期性能仍待验证，B09 保留隔离候选闸门，正式入口未开放；它的候选装备不计入正常入口目录。详见 [B09 候选说明](docs/levels/b09/candidate.md) 与 [验收记录](docs/levels/b09/validation.md)。

## Windows 运行与检查

默认引擎为 Godot 4.7.2-stable，二进制不入库。首次安装会下载并校验配置的官方版本，游戏离线运行。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\setup.ps1
.\tools\run.ps1
# 编辑器
.\tools\run.ps1 -Editor
# 整理资源后的导入／解析
.\tools\test.ps1 -ImportOnly
# 只运行相关检查
.\tools\test.ps1 -Suite legacy_profile_reset -SkipImport
python tools/maintenance/audit_repository.py
# B09 原创霜晶资源、35装备与七房候选（独立测试档，默认2K）
.\tools\play_b09.ps1
.\tools\test.ps1 -Suite b09_candidate -SkipImport
.\tools\test.ps1 -Suite b09_monster_contract,b09_equipment,b09_inventory -SkipImport
.\tools\test.ps1 -Suite b09_map_native -Graphical -SkipImport
.\tools\test.ps1 -Suite b09_2k -Graphical -SkipImport
```

也可双击 `RUN_GAME.cmd`，已有引擎可通过 `-EnginePath` 或 `GODOT_BIN` 指定。测试会重定向到独立存档目录。实际玩家存档为 `%APPDATA%\AbyssSalvagerM1\profile.json`，不属于仓库清理范围。

## 默认操作

| 操作 | 按键 |
|---|---|
| 移动与按住跟随 | 鼠标右键；方向键辅助 |
| 普通攻击 | 鼠标左键 / A；可设置自动普攻 |
| 四个技能 | Q / W / E / R |
| 闪避／交互 | 空格／F；信标靠近自动触发 |
| 背包／路线／技能详情 | B／M／Tab |
| 暂停 | Esc |

可自定义按键、自动普攻、技能路径、降低特效和镜头震动。自动普攻遵守距离和视线，不自动追敌。

## 仓库目录

```text
assets/
  characters/{warrior,gunner,mage}/{animations,portraits,skills,ui}/
  system/{audio,fonts,equipment,ui,world,combat,relics}/
  levels/{b01...b06,b09,b10}/{enemies,bosses,rooms,decorations,ui}/
  manifest.json                   # 逻辑资源 ID → 实际文件
scripts/
  app/                           # 运行入口与用例服务
  domain/                        # 战斗、装备、远征、成长规则
  gameplay/                      # 游戏节点与房间生命周期
  presentation/                  # 界面与视觉反馈
  infrastructure/                # 资源、音频、输入、内容和保存
  levels/                        # 关卡专属行为
  shared/                        # 少量共用尺度
scenes/{app,gameplay,presentation}/
data/{characters,equipment,monsters,world,levels,rules,localization}/
shaders/{world,levels}/
tests/{app,persistence,characters,equipment,combat,world,levels,ui,audio,balance,support,captures}/
tools/{assets,maintenance,testing,balance}/
docs/{characters,system,levels,engineering,legal}/
```

角色按职业，系统按功能，关卡普通怪与首领分别归档。物理资源名称使用小写 `snake_case`；旧目录不再作为加载入口。新增资源先登记 `assets/manifest.json`，由 `AssetCatalog` 统一解析；文件搬迁不改变怪物、装备、房间和存档里的稳定 ID。

- [文档入口](docs/README.md)：与资源相同的职业、系统、关卡层级。
- [当前进度](docs/DEVELOPMENT_PROGRESS.md)与[路线图](docs/LEVEL_ROADMAP.md)：明确已接入、候选、待验证和未实现。
- [开发规范](docs/DEVELOPMENT_STANDARDS.md)：代码职责、命名、清理和保存边界。
- [目录结构规范](docs/engineering/repository_structure.md)：完整层级、放置责任、命名和搬迁检查。
- [素材许可与来源](docs/legal/asset_licenses.md)：字体许可、原创资源来源及退役资源的必要归属记录。

最终 B10 星辉龙庭包含六个守关龙房间与单头星冠古龙终战；入口要求 BO09 已通关，本轮保留该条件并用隔离存档验收。D4 终章通关后正常撤离可领取一次专属彩蛋戒指；统一验收仍在进行。
