# Erosion 使用手册（MDM 移除 / 描述文件覆盖删除）

适用产物：`dist/Erosion.ipa`（com.jbdotparty.Erosion，ARM64，MinOS 18.0，ad-hoc 未签名，需自签后安装）
漏洞依赖：`bad_query` 沙箱逃逸（forcequitOS）。设备端运行，**不需要电脑、不需要 VPN、不需要 iTunes 配对**。

---

## 0. 先看清能力边界（重要）

- 本工具做的是**改写设备端的管理状态标记**：把 `CloudConfigurationDetails.plist` 的 `IsSupervised` 置为 `false`、移除 `OrganizationName`、删除 `SharedDeviceConfiguration.plist`。
- **它不会解除服务器端的 MDM 注册**。设备下次向 MDM 服务器 check-in 时，策略**仍可能被重新下发**，监管状态可能复活。要彻底解决必须走组织流程释放设备。
- 写入范围仅限 `bad_query` 能触达的路径。
- **操作前请整机备份**。Respring 后有可能看到设置/配置界面（源码内 `supWarning` 明确提示过这点）。

---

## 1. 主界面导览

打开 Erosion 后是一个列表：

- 顶部一块**黑色日志终端**，会打印 `[*] Erosion v0.1 (...)` 和当前 iOS 版本。出问题先看这里。
- **Tweaks** 分组里有四项：
  - `MobileGestalt`（仅 iOS 27.x 显示）
  - **`Config Tweaks`** ← **MDM 移除走这里**
  - `Custom Wallpapers`
  - `File Operations` ← 手动删除/覆盖描述文件走这里
- 左上角图标（顺时针箭头 `goforward`）= **手动 Respring**
- 右上角齿轮 = Settings

> 若 `Config Tweaks` 不显示，说明版本门把你挡住了（正常构建已放宽到整个 iOS 27.x，一般不会出现）。

---

## 2. 移除 MDM（推荐路径）

1. 打开 Erosion → 点 **`Config Tweaks`**。
2. 进入后页面标题是 **Configurations**。页面加载时会**自动申请写入权限**（bad_query 提权）。
   - 若弹出 `Failed to get write access!` → 说明逃逸在本机没成功，停止操作，看第 5 节。
3. 页面中部 **Supervision** 区会显示当前状态：
   - `Enable Supervision` 开关 = 当前 `IsSupervised` 的实际值
   - 开关下方 `OrganizationName` = 当前管理组织名
4. 点**右上角的回退箭头图标**（`gobackward`，**纯图标、没有文字**）。
   > 右上角有两个按钮：一个是这个箭头图标（Restore Tweaks），另一个是文字 **Apply**。别点错 —— **Apply 是把当前开关状态写回去**，不是恢复。
5. 弹出确认框 `Are you sure you'd like to reset your tweaks?`
   正文：`By clicking "Confirm", your footnote will be removed and your device will be unsupervised.`
   → 点 **Confirm**。
6. 成功弹出 `Successfully reset config tweaks!` → 点 **Respring**。
7. 等待 SpringBoard 重启完成。

**这一步实际做的事**（`ConfigView.reset()`）：
- `CloudConfigurationDetails.plist` 的 `IsSupervised` → `false`
- 移除 `OrganizationName` 键
- **删除** `SharedDeviceConfiguration.plist`
- 重写 `CloudConfigurationDetails.plist`

**验证**：设置 → 通用 → VPN 与设备管理 中不再显示受监管信息；重新进 `Config Tweaks`，`Enable Supervision` 应为关闭且组织名为空。

---

## 3. 手动删除 / 覆盖描述文件（File Operations）

当你需要直接动 `ConfigurationProfiles` 目录下的文件时走这条。

1. 主界面 → **`File Operations`**。
2. **Directory** 填：
   ```
   /private/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles
   ```
3. **File Name** 填目标文件名，例如 `CloudConfigurationDetails.plist`、`SharedDeviceConfiguration.plist`、`MDM.plist`。
4. 点 **Grant Access** → 出现绿色 `Access Granted` 才算成功。
   - 授权后 Directory / File Name 输入框会被锁定；要换路径先点 **Change Path**。
5. 按需操作：
   - **Export File** —— 把目标文件导出（先备份原文件再改）
   - **Import File** → **Overwrite File** —— 覆盖写入
   - **Import File** → **Move File** —— 移动/改名写入
   - **Delete File** —— 删除

> **两个坑（源码里就是这样，不是你操作错）**：
> 1. `Delete File` 按钮在**没有先 Import 任何文件之前是灰色不可点**的（代码里 `.disabled(imprtData.isEmpty)`）。想删除文件，必须**先随便 Import 一个文件**，按钮才会亮，然后点 Delete File —— 它删的是你在 Directory/File Name 里指定的目标，跟你 import 的内容无关。
> 2. 同理 `Overwrite File` / `Move File` 也必须先 Import。

---

## 4. 设置项

右上角齿轮 → Settings → **Show Tooltips**。

**建议保持开启（默认开）**。关掉后：
- 点 Restore Tweaks 图标会**直接执行、不弹确认**
- 成功也**不弹 Respring 按钮**，你得自己回主界面点左上角的 Respring 图标

---

## 5. 故障排查

| 现象 | 含义 / 处理 |
|---|---|
| 启动弹 `Your ... version is not supported!` + Exit | 版本门拦截。本构建已放宽到 iOS 27.x，若仍出现说明设备不是 27.x 或构建未包含该改动 |
| `Failed to get write access!` | bad_query 逃逸失败 → 当前系统版本/构建号已封堵该漏洞 |
| `Failed to reset tweaks!` | 提权成功但写入被拒，看主界面日志终端的具体 error |
| `Config Tweaks` 项不显示 | `mgSupported()` 为 false；本构建应为 true |
| 装了打不开 / 闪退 | 签名或信任环节问题（自签需信任开发者） |
| 移除后监管又回来了 | 服务器端重新下发，见第 0 节 —— 这是预期行为，不是工具失效 |

日志终端（`LogView`）会打印所有 `(cn)`、`(ov)` 前缀的操作结果，排查时以它为准。

---

## 6. 一句话速查

**Erosion → Config Tweaks → 右上角回退箭头图标 → Confirm → Respring。**
