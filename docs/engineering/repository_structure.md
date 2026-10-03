# 目录结构规范

更新：2026-10-03。适用于当前 Godot 仓库，新增和移动文件必须遵守本规范。当前实现范围见 [开发进度](../DEVELOPMENT_PROGRESS.md)，具体开发约束见 [开发规范](../DEVELOPMENT_STANDARDS.md)。

## 1. 根目录责任

| 目录／文件 | 内容与责任 |
|---|---|
| `project.godot` | 主场景、自动加载和引擎配置 |
| `README.md` | 当前可玩范围、运行方式、操作和主要入口 |
| `assets/` | 正式美术、音频、字体及其来源／许可 |
| `scripts/` | 运行代码，按规则、节点、表现与基础设施分层 |
| `scenes/` | 运行场景，按应用、游戏节点和表现分组 |
| `data/` | 机器读取的当前内容与规则配置 |
| `shaders/` | 共用世界和关卡专用着色器 |
| `docs/` | 当前规范、功能说明、设计与明确状态的候选资料 |
| `tests/` | 直接相关的检查源码、支持模块与固定输入夹具 |
| `tools/` | 安装／运行入口、资源维护、检查和数值工具 |
| `artifacts/`、`_tmp/` | 本地输出和临时工作，不入库 |

引擎程序、下载、Godot/Python 缓存、构建、截图副本、日志和隔离存档不放入正式内容目录，也不提交。实际玩家存档位于 `%APPDATA%/AbyssSalvagerM1`，不参与仓库整理。

## 2. 美术资源：职业、功能、关卡

```text
assets/
  manifest.json
  characters/
    warrior/
      animations/
      portraits/
      skills/
      ui/
    gunner/                     # 同样的职业内部层级
    mage/
  system/
    audio/music/
    fonts/
    equipment/
    ui/{common,workshop}/
    world/{environment,decorations}/
    combat/{effects,monsters}/
    relics/
  levels/
    b01/
      enemies/
        m01/
      bosses/
        bo01/
      rooms/
        l01/
          detail/
      decorations/
    b02...b06/
      enemies/
      bosses/
      rooms/
      decorations/
      equipment/               # 单关专用装备
      registration/            # 跨本关资源的登记
      ui/                      # 单关专用界面
```

上树描述分类位置，具体子目录随实际内容创建，不为未实现项目预建空资源。普通怪与 Boss 在所属关卡分开，每个身份按稳定 ID 建目录。共用图集供多个身份使用时放所属关卡的 `shared` 子目录；跨关的公共来源／登记放 `system/combat/monsters`，不复制相同像素充当多个新资源。

角色动作图、动作注册、region、脚点和来源一起维护。多个职业共用的单一图集放系统公共组件，由注册区分取样；专属身体／技能图放对应职业。单关房间、陈设、怪物和专用装备不得混进 `ui` 或 `system/shared` 兜底目录。

资源在 `assets/manifest.json` 登记稳定逻辑 ID 与物理路径。GDScript 通过 `AssetCatalog.resolve` 加载，工具通过 `tools/assets/asset_paths.py` 解析；逻辑目录枚举使用索引。搬迁物理文件只更新登记和必要静态引用，不重新编号角色、怪物、房间、装备或玩家实例。字体许可和必要版权来源必须保留。

## 3. 代码与场景

```text
scripts/
  app/
    game.gd
    expedition_controller.gd
    services/                   # 装备、成长、远征、设置用例
  domain/
    combat/
    equipment/
    expedition/
    progression/
    world/
  gameplay/
    characters/
    monsters/
    bosses/
    combat/
    equipment/
    world/services/             # 遭遇、交互、反馈、导航
  presentation/
    app/services/
    characters/
    monsters/
    combat/
    world/
    components/
    hud/
    equipment/
    screens/
  infrastructure/
    assets/
    audio/
    content/
    input/
    localization/
    persistence/
  levels/{shared,b01...b06}/
  shared/

scenes/
  app/
  gameplay/{characters,monsters,bosses,combat,world}/
  presentation/
```

应用层负责状态、用例提交与生命周期；domain 保存战斗／装备／成长规则；gameplay 负责节点与游戏行为；presentation 负责页面、绘制和反馈；infrastructure 负责文件、资源、输入、音频和保存。单关行为留在 levels，多个关卡共用的规则回到 domain，共用关卡流程可放 levels/shared。

新增功能按责任拆模块，不能持续堆回主控制器。服务通过所属控制器的明确接口访问上下文，不独立拥有该 Node 的生命周期。界面不发奖或重算独立经济，表现不驱动碰撞和伤害。GDScript 的 `.uid` 与脚本同步迁移，场景静态路径和自动加载同步更新。

## 4. 数据、着色器与工具

| 目录 | 放置内容 |
|---|---|
| `data/characters` | 英雄定义 |
| `data/equipment` | 装备模板、套装 |
| `data/monsters` | 普通怪、成长、种族策略 |
| `data/world` | 房间目录、运行蓝图、房间表现 |
| `data/levels/<chapter>` | 单关内容、装备和几何 |
| `data/rules` | 当前运行参数 |
| `data/localization` | 翻译字符串 |
| `shaders/world`、`shaders/levels/<chapter>` | 共用或单关视觉着色器 |
| `tools/assets/<feature>` | 资源维护；通过索引定位，不拼旧目录 |
| `tools/maintenance` | 目录、资源、来源及清理检查 |
| `tools/testing` | 检查注册、隔离输出管理与辅助脚本 |
| `tools/balance` | 当前数值导出和明确隔离的观察工具 |

`tools/run.ps1`、`setup.ps1`、`test.ps1` 和 `engine.ps1` 留在 tools 根，提供稳定入口。Python 工具从包含 `project.godot` 的祖先目录定位仓库，不依赖固定父层数。

## 5. 文档与检查

```text
docs/
  README.md
  DEVELOPMENT_PROGRESS.md
  LEVEL_ROADMAP.md
  DEVELOPMENT_STANDARDS.md
  characters/{warrior,gunner,mage,shared,planned}/
  system/{combat,equipment,balance,world,ui,saves}/
  levels/
    README.md
    b01...b10/
      README.md
      enemies/
      bosses/
      rooms/
      decorations/
      balance/                  # 该关当前候选／观察
      art/
  engineering/
  legal/

tests/
  app/ persistence/ characters/ equipment/ combat/
  world/ levels/ ui/ audio/ balance/
  support/
  fixtures/
  captures/
```

文档和资源按相同的职业、功能和关卡身份进入。关卡总览放本关 README，普通怪、Boss、房间和陈设分别维护。跨关规则放系统层，工程约束与版权独立保存。固定房间设计 JSON 放 docs，运行 JSON 放 data；禁止用整份设计房间覆盖运行蓝图。

状态统一写在正文开头：**已接入**、**候选／待验证**、**未实现**。B05/B06 已正式接入；B07、B08 和召唤师未实现，B09 仍为隔离候选，最终 B10 已接入并等待统一验收，保留 BO09 解锁条件。不把设计数量或候选检查计为正常可玩数量。已失效的阶段日志、旧 PR 过程、重复初稿直接移除，不新增 archive 目录。当前检查需要的固定数值输入放 tests/fixtures，不混为当前功能说明。

检查脚本和场景同目录、同名；套件名称在 `tools/testing/suites.json` 注册。执行 `tools/test.ps1 -Suite <name>`，不依赖 tests 根目录拼路径；输出和用户目录保持隔离。

## 6. 命名与搬迁检查

物理目录和文件使用小写 `snake_case`，例如 `warrior/animations/directional.json`、`b01/enemies/m01/codex_portrait.png`、`instance_forging.gd`。文件名表达用途，不重复所在目录的职业／关卡；现有同族有效备选通过注册区分，不继续追加无意义的版本串。根入口 README 与既有强制进度文档名称保持稳定。

稳定内容 ID 仍使用既有格式，如 CH01、M01、BO01、L01、EQ01；它们与物理文件命名分开。新规范不要求修改存档中的 ID、重排房间或改变数值。来源里的原始名称、生成版本、哈希与版权按事实保留。

搬迁必须同步检查静态路径、动态拼接、逻辑索引、场景、工具和文档链接。清理先确认当前动态依赖，校验绝对目标位于授权工作区。资源/代码变更执行相关导入、解析与运行检查，文档链接和注册使用：

`res://` 路径、资源索引和 Markdown 链接统一使用 `/`，大小写必须与 Git 中的文件名精确一致；例如数值入口是 `balance/README.md`。仓库检查覆盖 Git 已跟踪文件及尚未提交、未被忽略的新文件，不接受仅在本机存在的缓存、测试输出或截图链接。Markdown 标题锚点也须指向目标文档当前存在的标题；临时截图通过测试入口重新生成，再从本次输出目录查看。

```powershell
python tools/maintenance/audit_repository.py
python tools/testing/test_repository_audit.py
.\tools\test.ps1 -ImportOnly
.\tools\test.ps1 -Suite legacy_profile_reset -SkipImport
```
