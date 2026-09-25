# App 图标与菜单栏首屏外观设计

- 日期：2026-09-13
- 范围：`StatusTrio.app` 的 Finder/Launchpad 图标，以及菜单栏图标首次渲染时的明暗外观

> **已核实的边界。** 本文第 3 节的 App 图标只有深色一版，而且**至今仍只有深色一版**。
> macOS 26 的图标主题化需要一份带外观变体的 `Assets.car`，但经实测，手工编写的
> `.icon` 无法表达按外观区分的位图图层；1.3.3 曾上线该方案并已回退。原因、证据与
> 将来若要真正跟随系统需要怎么做，见 [app-icon.md](../../app-icon.md)。
> 第 4 节（菜单栏首屏）仍然有效。

## 1. 背景

当前 SwiftPM 打包产物没有 `CFBundleIconFile`，Resources 中也没有图标资源，因此 Finder 和 Launchpad 显示空白 App 图标。

菜单栏图标在暗色模式下首次打开时先显示黑色，随后才切换为白色。原因是控制器初始化期间状态栏按钮尚未获得最终外观，首次绘制读取到浅色外观；后续快照更新或外观变化触发重绘后，颜色才正确。

## 2. 目标

1. 使用现有 `status-menubar.svg` 的满状态外形作为 App 图标视觉来源。
2. 生成 macOS 可识别的 `.icns`，并正确写入 App bundle。
3. 菜单栏图标首次绘制即使用当前菜单栏外观，不再出现明显黑变白。
4. 保留菜单栏图标的实时状态与充电绿色、低电量黄色。

## 3. App 图标设计

- 新增专用 `Support/AppIcon.svg`，画布为 1024 x 1024。
- 图标由深色圆角方形底和白色前景组成，前景为满状态电池弧、满格 Wi-Fi 和四个音量点。
- 前景几何沿用 `status-menubar.svg`，但不使用依赖 `pathLength` 的轨道实现；满状态电池使用完整实线路径，确保系统 SVG 渲染器输出稳定。
- 构建脚本使用系统自带 `sips` 从 SVG 生成各尺寸 PNG，再使用 `iconutil` 生成 `AppIcon.icns`。
- 打包后将图标复制到 `Contents/Resources/AppIcon.icns`，并在 `Info.plist` 中设置 `CFBundleIconFile` 为 `AppIcon`。

## 4. 菜单栏首屏修复

- 状态栏控制器增加对按钮自身 `effectiveAppearance` 的观察。
- 首次绘制安排到主线程下一轮，让状态栏按钮先获得最终菜单栏外观。
- 解析外观时优先使用按钮窗口的外观，其次使用按钮自身外观，最后回退到应用外观。
- 保持现有 `StatusIconRenderer` 的非模板图片策略，从而继续支持状态颜色。

## 5. 验收

- 重新打包后 `dist/StatusTrio.app/Contents/Resources/AppIcon.icns` 存在。
- `Info.plist` 的 `CFBundleIconFile` 为 `AppIcon`。
- Finder 或 Launchpad 不再显示空白图标，图标为满状态白色前景。
- 暗色模式下首次启动菜单栏图标直接显示白色，不经过可见的黑色阶段。
- 现有测试通过，Release app bundle 可成功构建、签名并启动。
