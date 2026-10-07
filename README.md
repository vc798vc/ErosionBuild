<div align="center">
  <h1>Erosion</h1>
  <p>A collection of customization tweaks that use the <a href="https://github.com/forcequitOS/bad_query">bad_query</a> sandbox escape.</p>
  <p>iOS 26.0 - iOS 26.6.1 & iOS 27.0db1-db4</p>
  <p><a href="https://jailbreak.party">Website</a> • <a href="https://jailbreak.party/discord">Discord</a> • <a href="https://x.com/jbdotparty">Twitter</a></p>
  <a href="https://github.com/jailbreakdotparty/Erosion/stargazers">
    <img src="https://img.shields.io/github/stars/jailbreakdotparty/Erosion?style=social" alt="GitHub stars">
  </a>
</div>

>[!WARNING]
>If a tweak does not work on your device, **do not ask us for any support regarding it!** Many of tweaks are reliant on your device, and not our tool, cooperating properly. In some cases this can even involve Apple's servers. We will be unable to help you if a tweak does not give you the behavior you're hoping for. **Use all of these own tweaks at your own risk, and have a backup please!**

## Supported Versions
>[!NOTE]
>If your version doesn't show up on this list, your device is not supported. **Do not ask us for any support regarding extending version support!** Exploits that apps like these rely on are very rare to come by, so there's nothing we can do if your device isn't supported.
- iOS 26.0 - iOS 26.6.1
- iOS 27.0 (24A5355q) -> Developer Beta 1
- iOS 27.0 (24A5370h) -> Developer Beta 2
- iOS 27.0 (24A5380h) -> Developer Beta 3/Public Beta 1
- iOS 27.0 (24A5390f) -> Developer Beta 4/Public Beta 2

All iOS 26 versions cannot use some of the tweaks that this toolbox contains. The section below tells you what tweaks work on what versions.

## Tweaks
- iOS 26.0 - iOS 26.6.1 & 27 betas
  - Custom Wallpapers: Import and apply custom .tendies, like you would inside of [Nugget](https://github.com/leminlimez/Nugget). Supports collections, video and mercury wallpapers!
  - File Operations: Allows you to overwrite and place custom files at a desired destination that bad_query can access.
    - /var/containers/Data/System (iOS 27)
    - /var/containers/Shared/SystemGroup/* (iOS 27)
    - /var/mobile/Containers/Data/Application/*
    - /var/mobile/Containers/Data/InternalDaemon/*
    - /var/mobile/Containers/Data/PluginKitPlugin/*
    - /var/mobile/Containers/Shared/AppGroup/* (iOS 27)
    - /var/mobile/Containers/Shared/AppGroup (iOS 27)
- iOS 27.0db1-db4 ONLY
    - MobileGestalt Tweaks: Enable gated features and add device functionality. If enabling Apple Intelligence does NOT work, **do not ask us for any support about it!** This tweak is reliant on Apple's servers and your device cooperating properly, so there is nothing we can do in the event where something never works properly.
    - Config Tweaks: Add custom footnotes and enable device supervision!

## Build this fork (unsigned IPA via GitHub Actions)

本仓库已改造为可在 GitHub Actions（macOS runner + Xcode）上无人值守编译并产出未签名 IPA。
需自备 GitHub 个人 token（含 `repo` 权限）。

```bash
python3 make_ipa.py --token ghp_xxxxxxxxxxxx
```

脚本会：把源码推到你的 `ErosionBuild` 仓库 → 触发 Actions 构建 → 轮询结果 →
下载 `Erosion-unsigned-ipa` 解包为 `dist/Erosion.ipa`。产物为 ad-hoc（无签名）包，
安装前请用 Sideloadly / TrollStore / 自签 重签名。

> 改造点：原工程用 `PBXFileSystemSynchronizedRootGroup`（文件夹同步），在 CI 命令行
> 构建时不会扫描到源文件，导致产出空的 `.app`（仅含一个 SPM 资源包）。本仓库改为
> 显式文件引用，并加入"产物必须含 >1MB 的 Mach-O"硬校验，避免再次打包空壳。
> 另：原版 `isSupported()` 仅在 4 个 iOS 27.0 beta 构建号上放行，已放宽为整个 27.x，
> 否则在 TQ 的设备上启动即弹"不支持"并退出。

## MDM 移除用法（Config Tweak）

打开 Erosion → 进入 **Configurations**（配置）→ 右上角 **Restore Tweaks**（恢复调整）→
确认"设备将不受监管 / device will be unsupervised"→ 触发 **Respring**（重启 SpringBoard）。
该操作会删除 `SharedDeviceConfiguration.plist`、把 `CloudConfigurationDetails.plist` 的
`IsSupervised` 置为 false 并清空 `OrganizationName`，即完成"移除 / 覆盖 MDM 描述文件"。

## Credits
- **[lunginspector](https://github.com/lunginspector)** - Primary developer and tweak creator.
- **[forcequitOS](https://github.com/forcequitOS/bad_query)** - Author of the bad_query exploit that this app utilizes.
- **[rooootdev](https://github.com/rooootdev/mond)** - Some minor backend components, taken from mond.
