# 深渊拾荒者 Abyss Salvager

Godot 4 单人动作游戏原型。当前正式入口开放 **B01–B06、等级 1–30、战士／枪手／法师**。B05、B06 按前章首领通关并撤离的顺序解锁；B07–B12 和召唤师为未实现设计。内容状态更新于 2026-10-03，以 [开发进度](docs/DEVELOPMENT_PROGRESS.md) 和运行配置为准。

明亮手绘卡通奇幻风，高机位三分之四斜俯视与 2.5D 质感；界面使用米白羊皮纸、黄铜、深紫文字和圆形技能徽章。

## 当前可玩范围

| 内容 | 已接入范围 | 待完成或待验证 |
|---|---|---|
| 职业 | 三职业、各四技能、职业被动、成长与连击反馈 | 全方向连续动作、可见换装、自然群战手感 |
| 正式六关 | 36 个普通房与 6 个首领场地；普通怪分别 9／12／15／18／18／18 种，共 90 种；6 名首领 | 长时间游玩、全种子自然平衡与硬件性能 |
| 装备 | 194 个模板、22 套、八槽独立实例、白绿紫金品质、随机词条、购买／打造、强化、重锻、重铸、精炼、继承、出售／拆解 | 自然获取时长及高难度构筑平衡；药品未实现 |
| 房间表现 | 固定蓝图、脚点排序与遮挡淡化、42 房独立完整原画；背景、边界、物件脚点和镜头共用坐标映射、首领和普通怪资源注册 | 图块共享本房纹理；显存流式加载未实现 |
| 保存 | 检查点、一次结算、写入互斥、七天回收站；当前格式继续读写 | 旧格式只保留原始备份并从新进度开始 |

当前默认采用新数值规则。死亡扣本局 50% 金币、丢弃未结算经验与临时装备，保留已有等级、已结算经验与永久装备；成功撤离后新装备永久入库。换装不会回血、重置冷却或重复发奖。本次正式开放不修改敌人校准、掉落概率或伤害规则。B05/B06 当前原画验收见 [全房原画与共用坐标](docs/levels/b05_b06_room_paintings.md)，开放与保存兼容见 [正式接入记录](docs/levels/b05_b06_release.md)。

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
  levels/b01...b06/{enemies,bosses,rooms,decorations,ui}/
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
