# L39 六详情制作状态

更新：2026-10-03。**候选／部分完成，用户已停止 B07 开发和美术生成。**

已返回 5 张原生详情：top_left、top_middle、top_right、bottom_left、bottom_middle。缺少 bottom_right；无在途生成，不继续补图。

冻结母图为 `assets/levels/b07/rooms/l39/background/courtyard_boundary_revision.png`，SHA-256：`770303def7180147167d16c60a2ac0b5474a60344391f1d92d2d521a59053bef`。母图本身仍为 `blocked_do_not_integrate`，详情不改变母图状态；若母图以后变化，全部详情需要重新配准。

已生成的五片均由 built-in image_gen 对实际查看过的精确裁区做原生材质重绘。原生尺寸依次为 1244×1265、1254×1254、1241×1268、1254×1254、1264×1244，最低轴向原生密度 2.375 倍。每片的原始 PNG 字节保存在 `assets/levels/b07/rooms/l39/detail/source/`；同名 WebP 无缩放无损编码，解码 RGB 与原生 PNG 一致。

本次只完成各输入裁图及各实际输出的单图查看。总体构图、主要建筑、院墙和纹样可识别地保留；生成输出仍可能有细部轮廓、砖缝与阴影差异。停止指令到达前尚未进行整幅拼图、重叠带检查、像素边界核对或运行验收，不能声称拼缝通过、可走边界通过或正式接入。

`detail/manifest.json` 标记 `approved=false`、`candidate_only=true`、`partial=true`、`missing_ids=["bottom_right"]`。源矩形沿用 L07 的六裁区；每个现存块包含原生尺寸、源与输出哈希、完整 prompt、原始生成输出路径及有限图像 QA。正式索引由父任务集中处理，本任务未修改共享 manifest、运行数据、母图或运行开关；未启动 Godot、提交或推送。

原始生成路径与 SHA 清单见 `detail_provenance.partial.json`。原生 PNG 已在 assets 下保全，artifacts 中工作副本与输入参考不应入库。
