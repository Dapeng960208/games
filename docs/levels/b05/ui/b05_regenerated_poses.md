# B05 当前普通怪动作资源

更新：2026-10-03。**状态：隔离候选已接入；连续动作和自然群战待验证。**

18种普通怪各登记 idle、telegraph、execute 三张独立原生图，共54姿态。纹理与来源位于 `assets/levels/b05/enemies/m01...m18`，共享注册位于 `enemies/shared`；完整路径由 `assets/manifest.json` 解析。旧批次结果和云端日志不作为本次验收。

`scripts/levels/b05/art/enemy_art.gd` 提供身份对应的姿态库，EnemyArt、EnemyVisual 与图鉴共用登记。每物种以 idle 解剖高度统一比例，各帧独立登记脚点、核心和器官；表现出口不改变实际技能伤害原点。左右翻转与受击使用统一身体变换。

`tests/levels/b05/test_b05_pose_sources.py` 核对当前源字节、prompt摘要、原始RGBA尺寸与注册；角色/怪物目录整理不修改图片像素。实际机关、身份招式、图鉴与群战可读性仍按各自检查范围报告。

三张关键姿态不等于连续动画。walk/recovery 使用已有姿态和运行变换，全方向连续动作、细装饰边缘与自然群战比例仍待验证。候选默认未发布，不能由源文件检查开启正式闸门。
