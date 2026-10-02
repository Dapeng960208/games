# 2K 游戏房间美术：源图密度与分区重绘试验

日期：2026-10-02。范围为实际 B01–B04 的 28 个完整房间背景（地面、墙体、建筑与外围环境）。不是路线缩略图或房间 UI 徽记。

## 当前结论

**28/28 原画已审计；10/28 完整房间原生细节升级已验收并启用：L01–L05、L16、L19–L22。** 每房完成五个真实 2560×1440 镜头的原图/新图对照及 46 项检查，0 失败。剩余 18 房尚未验收，正在分批制作。原生产图片保持 fallback；房间 JSON、可走边界、摄像机、敌人、奖励及实际玩家存档未改。L20 东南测试锚点与背景墙体的视觉重叠在原图中已存在，未通过移动几何来掩盖。不能把候选数量记为交付完成。

## 真实瓶颈

- 28 张独立房间 PNG 均为 **1536×1024**，不是 2K 原画
- 3×2 的六个 Sprite2D 共享完整母纹理；切块不会增加细节
- 2800×1800 蓝图经 0.58 映射为 1624×1044；placement rect 为 [0.11,0.13,0.78,0.74] 时完整画面约为 2082.05×1410.81 世界单位
- `world_camera.gd` 基准 zoom 0.85；生产 `canvas_items` 使用 1280×720 逻辑尺寸，2560×1440 窗口为 2 倍物理像素
- 因而原画一个 texel 在 2K 正常镜头下约占 **2.304×2.342 屏幕像素**，可见屏幕只有约 **1111×615 原生 texel**；完整画面要达到约 **3539×2398** 原生尺寸才接近 1:1
- `environment_sampling.gdshader` 已有放大 Catmull–Rom 重建；`texture_sampler.gd` 在运行时生成 mipmap。PNG 导入项 mipmaps=false 不等于最终运行纹理没有 mipmap。现有采样改善不会创造新的材质细节
- 路线小图和 UI 徽记的适配另行负责；其显示尺度不能证明游戏场景已经满足原生 2K

## 内置生成工具试验及诚实边界

1. L16 全图参考编辑明确请求 3840×2560，实际 PNG 仍为 1536×1024。未作为高分辨率升级使用
2. 仅提供全图并描述源坐标的局部特写能输出 1254²，但会重新取景；未采用
3. 机械裁切确切源区域并作为编辑目标，生成六张对应的原生细节图：五张 1254²，一张 1244×1264。源区域约 520–528 像素，增加的是新绘制细节，未把原图简单放大，也未对生成 PNG 做像素修改
4. 六图覆盖 L16 全房，各自保留原位置与大构图；但石块细节、材质光泽、色彩及边缘存在变化，必须检查真实拼合效果。上中/上右重叠区在源坐标尺度比较的平均 RGB 差约 4.26%，95 分位约 13.73%；这只是差异诊断，不是合格阈值
5. 试验渲染把高密度区块按原图归一化坐标放置于原背景之上，内边缘作短距离羽化。原背景继续作为底层 fallback。羽化处保留部分低分辨率底图，不能声称整个场景每个像素均来自无损拼接的独立高分辨率母图

最初的试验候选保存在隔离验收目录，未直接启用；来源、完整提示词、生成输出、每图原生尺寸、SHA-256 和源区域保存在隔离验收产物 `artifacts/world-2k-pilot/generation_provenance.json`。被拒收的全图/坐标提示试验不启用。

## 可复现的下一步

隔离的 `artifacts/world-2k-pilot/gameplay_pilot.tscn` 继承已有环境清晰度检查，仅在测试场景加载六张候选；使用生产 L16 房间及 HUD。启动时强制要求包含 `test_environment_native_pilot` 的隔离 profile 和图形渲染。它捕获：

- `L16_actual_gameplay_original_2560x1440.png`
- `L16_actual_gameplay_native_pilot_2560x1440.png`

检查 framebuffer 真为 2560×1440；叠图前后 layout 序列化、walkable polygon 和 camera zoom 必须完全一致。随后人工逐块检查建筑脚点、道路图案、重叠边缘、交叉接缝、颜色/光泽一致性及与角色的比例；需要至少一个中心镜头与能看到边缘建筑的镜头。未通过时保留原图，不扩展 28 房。

早期环境受限尝试：孤立源图样例项目的 Godot 4.7.2 导入/解析通过，未发现 SCRIPT ERROR/ERROR；这不等于生产测试脚本执行通过。图形尝试失败原因：Xvfb 不存在、Godot 无可用 X11/Wayland；已安装的 Chromium 无头实例因 socket() Operation not permitted 失败。未绕过限制或改变正在查看的游戏。

若 L16 拼合成立，28 房最低需要 168 张有来源记录的分区原生图；当前六图区块并行一轮约三分多钟，但实际生成排队、重试和每房接缝/建筑边界检查决定耗时，不能承诺按单图线性推算的完成时间。若局部漂移在羽化后仍明显，需要可控的配准/接缝修复工作流或另一可返回大尺寸原生原画的授权工具；不能用额外锐化或普通材质覆盖层替代这项验收。

## L16 验收与加载实现（04:12 UTC）

- 真实 Godot 4.7.2 / 私有 Xorg :97 / llvmpipe，2560×1440，中央及西北/东北/西南/东南五个实际游戏镜头，各有原图与重绘图。46 项检查通过、0 失败，无 ERROR/SCRIPT ERROR；仅软件驱动不能切换 VSync 的警告
- 五处 native 图已逐一查看：石材、蜡、屋瓦、花叶边缘有真实细节增益；未见明显硬接缝、门洞/可走边界移动或玩法标记偏移。边缘羽化仍保留部分底图；不称无损拼接的完整大母图
- 同一实际 layout/polygon/camera 保持完全相同；L16→L17→L18→L16 检查通过。六张纹理释放后 WeakRef 均为空，回房可重新加载
- 六张纹理 RGBA+mip 保守上界 50,305,616 bytes（47.98 MiB）。图形监视器加载时 577,689,599 bytes、清理后 539,960,387 bytes、重载恢复相同值；差值与 RGB 纹理的实际存储相符。该监视器包含整个游戏素材，不是单房独占，也不构成硬件帧率基准
- `environment_detail.gd` 由当前房间节点独占纹理，不设跨房永久缓存。`WorldArt` 的原背景缓存限制为 2 项，环境不再放入 UI 的永久 `TextureSampler` 缓存；现有 UI 缓存不改
- 仅 `assets/generated/world/rooms_2k/L16/manifest.json` 的 approved=true 生效；未批准/缺失包继续加载完整原画。PNG→lossless WebP 逐像素解码相同，六图体积 13,438,612 bytes；导入时生成 mip，不改原生分辨率
- 现有 `environment_sampling.gdshader` 的内置 TEXTURE sampler 参数写法触发 Godot 4.7 headless 编译错误；现以内联相同九采样公式替换，直接材质创建与释放检查无 ERROR。未改变重建数学、放大阈值或缩小 mip 采样

维护工具 `tools/package_environment_tiles.py`：prepare 只机械提取确切参考区，不生成/修图；package 要求 6 个来源作业、原生密度至少 2.35、逐像素无损检查，并且默认 approved=false。各包包含完整提示词、源图/生成图/无损文件与解码像素哈希。当前 L16 的五张验收截图哈希已记入该包 QA 字段；完整截图属于可重建 artifacts，不入 Git。

## 正式可复现测试

- `tests/test_environment_native.gd/.tscn`：正式图形场景测试，只读取 `assets/generated/world/rooms_2k` 的正式包与 manifest，不依赖 ignored 的裁切图、生成 PNG 或 jobs 文件。`tools/test.ps1 -Suite environment_native -Graphical`；直接引擎调用可额外传 `--native-room=L01`。截图写到 ignored 的 `artifacts/environment-native/`
- `tests/test_environment_native_resources.gd/.tscn`：无图形资源完整性与生命周期检查，只读正式资产；核对批准包原画哈希、WebP 文件哈希、运行时解码 RGB 与生成像素哈希、原生密度、归一化坐标映射、mip 和释放后 WeakRef。未批准包必须保持不可加载，不以候选为完成数量
- 已完成一次针对当前批准 L16 的 headless 正式资源检查：61 项、0 失败（该时点其他候选数量影响总检查数，不是固定覆盖量）；图形逐房检查的具体数量和证据见各批准 manifest 的 QA 字段
- 临时 private-display 批处理 runner、profile、log 和所有截图留在 ignored artifacts 或隔离临时目录，均不是 GitHub 交付物
