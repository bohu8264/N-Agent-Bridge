# Air75HIDInspector

源码位于 `Sources/Air75HIDInspector/main.swift`，复用 Core 的可信设备匹配。

```sh
swift run Air75HIDInspector
swift run Air75HIDInspector --listen 30
```

第二条命令会在 30 秒内只读打印已识别 Air75 V3 的 HID Usage，供物理校准使用。
