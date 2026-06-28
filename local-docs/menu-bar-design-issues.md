# Menu Bar Design Issues

## P0: 控制权状态必须一眼可见

当前设计容易把 `Auto`、`Balanced preset`、`Manual RPM` 放在同一层级，用户无法快速判断现在是 macOS 在控制，还是 FanFlow 正在写入风扇。menubar 必须优先显示控制权：`macOS has control`、`FanFlow curve active` 或 `FanFlow manual override`。

## P0: 退出与恢复 Auto 是安全路径

风扇控制软件的退出按钮不能只是关闭应用。退出前必须恢复 macOS 自动控制，并在 UI 中保留显式 `Restore Auto` 操作，避免用户误以为退出后系统已接管但实际仍处于 manual mode。

## P1: Menu bar 不应承担主窗口职责

menubar 是快速状态与快速控制面板，不适合展示完整传感器列表、复杂表格或主窗口导航。推荐只保留当前 RPM、温度摘要、控制权切换、预设/手动快捷操作、设置与退出。

## P1: 所有硬件数字必须来自同一数据源

风扇数量、min/max RPM、当前 RPM、温度与模式必须从实时 `FanInfo` 和传感器读取派生。不要在 UI 中混用 mock 数字或固定范围，否则硬件可信度会下降。

## P1: 文案使用用户语言，避免内部字段名

避免直接展示 `fanCount`、`actualRPM`、`pollingInterval`、`manualRPM` 等内部命名。UI 文案应使用 `Fans`、`Current RPM`、`Polling`、`Manual target` 等面向用户的表达。

## P2: 图表必须说明含义

如果展示曲线或动态可视化，需要明确它代表历史 RPM、温度趋势还是控制曲线预览。menubar 中可以使用轻量动态风扇/气流视觉，但不要让装饰图表承担关键决策信息。
