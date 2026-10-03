# 世界与房间

> 状态：正式前四关的 28 房布局与环境已接入；B05/B06 为隔离候选，流式加载未实现。

运行蓝图在 `data/world/fixed_rooms.json`，表现配置在 `data/world/room_presentations.json`。设计 JSON 只供按字段合并，不能整房替换运行数据。脚点排序、遮挡淡化、碰撞足迹与移动多边形共用场景尺度。

每关的普通怪、首领、房间和陈设在 [关卡文档](../../levels/README.md) 分开；共用布局说明见 [room_presentation](room_presentation.md)，设计册入口见 [房间总览](../../levels/rooms.html)。逐房图块和源图共存，只供当前 fallback，不算显存流式加载。
