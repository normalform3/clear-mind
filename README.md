# Clear Mind

Clear Mind 是一个本地优先的原生 macOS 应用，用来托管长期目标、近期事项和暂时无法处理的想法。它不包含账号、云同步、遥测，也不尝试替代每日 Todo。

## 功能

- 单一的一天时间表，支持整表编辑、时间冲突校验、自由归属和持久清单
- 可手动排序的长期目标、并行推进项、里程碑和固定月精度的纵向时间泳道
- 简洁的近期事项托管，不依赖截止或回看日期
- 想法库、低频收集箱、标签和全局搜索
- SwiftData 本地存储和完整 JSON 备份导入／导出

## 运行

1. 使用 Xcode 26 或兼容版本打开 `ClearMind.xcodeproj`。
2. 选择 `ClearMind` scheme 和 `My Mac`。
3. 按 `⌘R` 运行。

最低部署版本为 macOS 15。项目没有第三方依赖。

## 验证

```sh
xcodebuild -project ClearMind.xcodeproj \
  -scheme ClearMind \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/clearmind-derived \
  CODE_SIGNING_ALLOWED=NO test
```

UI 冒烟测试位于 `ClearMindUI` scheme。首次运行需要允许 Xcode 使用 macOS UI 自动化：

```sh
xcodebuild -project ClearMind.xcodeproj \
  -scheme ClearMindUI \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/clearmind-ui-derived \
  test
```

日常数据保存在应用的 Application Support 容器中。通过“Clear Mind → 设置”可以导出或导入 `.clearmindbackup` 文件。
