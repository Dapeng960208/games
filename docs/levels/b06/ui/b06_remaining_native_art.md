# B06 当前候选美术登记

更新：2026-10-03。**状态：隔离候选已接入；正式入口与自然体验待验证。**

普通怪18种、54关键姿态；装备4套×8槽和3件独立装备，共35图标。首领、机关和房间资源分别在同关的 bosses、decorations、rooms 下。来源、选择状态、prompt和原始hash与纹理共同维护，目录整理不重绘、缩放或裁边。

普通怪共享注册为 `assets/levels/b06/registration/manifest.json`，装备注册为 `assets/levels/b06/equipment/b06_equipment.manifest.json`。B06NativeArt、EnemyArt、EnemyVisual 与图鉴按当前身份读取；候选装备仅在显式隔离模式合入。资源的 `enabled` 与 `runtime_quality_gate_passed` 保持原候选状态。

每物种以 idle 的来源高度统一比例，独立登记各姿态脚点与视觉出口。视觉核心和出口不替换技能碰撞、伤害原点或波次。当前 `tools/maintenance/audit_b06_native_sources.py` 核对106份源图的精确hash、尺寸、来源及注册；图形、设备与自然群战应单独验收。

关键姿态不等于全方向连续动画。姿态之间的解剖比例、展开轮廓、贴边装饰与自然遮挡仍属候选验证项；装备图标不能证明套装效果已实现。旧运行批次和截图日志已从当前说明中移除，不据图片登记宣称完整关卡或图鉴已验收。
