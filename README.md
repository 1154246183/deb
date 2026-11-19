# CocoaTop 中文注解

给 CocoaTop 进程列表加中文说明的越狱插件。

## 功能

把进程名显示为「进程名 · 中文说明」，例如：

```
SpringBoard · 主屏幕（桌面本体）
mediaserverd · 多媒体核心
backboardd · 后台事件守护
```

## 安装

下载 Actions 产物中的 `.deb`，用 Sileo / Filza / dpkg 安装。

## 翻译表

`/var/jb/Library/Application Support/CocoaTopAN/proc-cn.plist`

格式为 `<key>进程名</key><string>说明</string>`，改完重启 CocoaTop 生效。
