# 当前随机锻造规则

> 状态：已接入；自然获取时长、强化价值和高难度配装平衡待验证。

运行实现为 `scripts/domain/equipment/instance_forging.gd`、`instance_economy.gd` 与 `equipment_acquisition.gd`，参数以 `data/rules/numerical.json` 为准。

支持强化至 +10、每阶随机 8–12%、有界重锻保底、固定词条槽重铸、精炼、逐阶取优继承、出售和拆解。重铸先扣款并冻结候选，再明确选择；失败重试沿用原结果。金装自然掉落最多 +1，其他品质的预强化范围以当前获取规则为准。

交易以唯一 operation ID 提交。穿戴、锁定、未结算装备不能绕过回收保护；退款按当前实例实付账本计算，材料保留对应种族归属。已存在于当前格式的历史付款与资格元数据保留，仅删除旧格式运行转换入口。

接口见 [装备服务](../../../scripts/app/services/equipment_service.gd)，资格见 [职业规则](../equipment/class_policy.md)。药品与身体附件换装未实现。
