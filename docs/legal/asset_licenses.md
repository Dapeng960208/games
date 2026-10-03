# 素材来源与许可

当前正式素材、纹理注册和完整来源记录一起保留。目录搬迁不改变 PNG/WebP/WAV 字节、作者归属或许可。

- 角色、普通怪、首领、装备、环境和界面图使用本项目登记的原创 ImageGen 资源。每个资源旁的 JSON、prompt 或 provenance 保留原始生成说明、身份和必要哈希；脚点/region 登记不代表新增逐帧动作。
- 当前角色身体统一 112 世界像素，关键姿态与镜像不代表完整八方向连续动画。图形来源与当前可玩范围分开，后者见 [开发进度](../DEVELOPMENT_PROGRESS.md)。
- 战斗音效由本项目程序合成；音乐为原创音符/振荡器合成，不使用外部录音采样。配器和哈希登记在 `assets/system/audio/music/score.json`，生成器为 `tools/assets/audio/compose_audio.py`，素材自身说明与许可随目录保留。
- Noto Sans SC 来自 Google Fonts 官方字体目录，遵循 SIL Open Font License 1.1。字体位于 `assets/system/fonts/notosanssc.ttf`，完整许可为 `assets/system/fonts/ofl.txt`，分发时一起保留。
- Godot 遵循 MIT 许可；仓库不包含引擎二进制。独立分发时附带引擎及依赖许可。

已退役资源的必要归属见 [retired_asset_sources](retired_asset_sources.json)。它只保存来源/版权所需信息，旧素材不再作为游戏加载入口。生成工作副本、截图副本和隔离存档不纳入正式资源或 Git。
