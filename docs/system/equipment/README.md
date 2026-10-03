# 装备系统

> 状态：八槽独立实例、品质、词条、获取与工坊已接入；自然经济待验证。药品和可见换装未实现。

正式四章目录为 124 模板／14 套，槽位为 weapon、head、chest、hands、legs、feet、ring、accessory。模板 ID、实例 ID、品质、词条和强化分别保存，同模板允许多件。

白绿紫金与随机词条、购买/打造、强化、重锻、重铸、精炼、继承、出售/拆解使用值事务；失败和重试不重抽。新装备撤离后入库，换装不回血、不重置冷却。B05/B06 装备只在对应隔离候选中开放。

- [职业资格](class_policy.md)
- [当前工坊规则](../balance/random_forging_design.md)
- 代码：`scripts/domain/equipment` 与 `scripts/app/services/equipment_service.gd`
- 美术：`assets/system/equipment`；单关专用资源留在对应关卡目录。
