# 素材、字体与运行依赖

| 资源 | 来源 | 许可与使用范围 |
|---|---|---|
| 拾荒者与锈壳寄生体 | 用户要求原创；本次通过内置 imagegen 根据主题独立生成 | `assets/characters/`；无竞品参考图，原图透明 PNG 未经后期；完整提示词、哈希见 [CHARACTER_ART.md](CHARACTER_ART.md) |
| 分裂镜片、余烬灯芯、弧电线圈 | 本次通过内置 imagegen 根据各自机制独立生成 | `assets/ui/relic_*.png`；地面装置、HUD、档案及详情共用图像；原始路径与完整提示词见 [IMAGEGEN_PROMPTS.md](IMAGEGEN_PROMPTS.md) |
| 矿井升降机／提灯主视觉 | 本次通过内置 imagegen 原创生成 | `assets/ui/mine_keyart.png`；仅作菜单和营地背景，按钮文字不烘焙在图片中；见 [KEYART_PROMPT.md](KEYART_PROMPT.md) |
| 井室地板 | 本次通过内置 imagegen 原创生成 | `assets/world/mine_floor.png`；低对比材质，不改变碰撞地图；见 [FLOOR_PROMPT.md](FLOOR_PROMPT.md) |
| 弹体、枪管、预警、反馈、矿轨、矿物、界面铆钉 | 本工程 GDScript 原创即时绘制 | 与真实状态同步；保留几何备用显示；未使用竞品或上一级 Phaser 项目中的资源 |
| UI 形状、配色与排版 | 根据用户范围基线实现 | 原创界面；色板来自用户附件 |
| Noto Sans SC 可变字体 | [Google Fonts 官方目录](https://github.com/google/fonts/tree/main/ofl/notosanssc) | SIL Open Font License 1.1；原文件 `assets/fonts/NotoSansSC.ttf`，完整许可 `assets/fonts/OFL.txt` |
| Godot 引擎与 Windows 导出模板 | [Godot 官方下载](https://godotengine.org/download/windows/)及 [4.7.2 官方发行](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable) | Godot MIT，附 `tools/godot/LICENSE.txt`；具体依赖许可遵循 [Godot 官方许可说明](https://godotengine.org/license/) |
| 截图 | 本机 Godot 4.7.2 Compatibility 实际运行 | 存放 `artifacts/`；是测试场景与主场景的引擎帧，不是概念图 |

字体通过 Godot FontVariation 以 450 字重使用，字体文件未修改。下载的具体 URL 与 SHA256 见 `tools/godot/ENVIRONMENT.md`。

当前没有背景音乐、采样音效或配音素材。人物与怪兽当前为单幅透明素材加程序摆动、瞄准、受伤与预警反馈，尚无逐帧方向动画。可在后续扩展同主题动画与声音；不要删除字体许可或引擎许可。上一级原 Phaser 项目的素材与第三方依赖未拷入本原生工程。

工程实现参考 Godot 官方 [FontVariation 文档](https://docs.godotengine.org/en/4.7/classes/class_fontvariation.html)，仅用于正确配置字体轴；文档不是游戏素材。
