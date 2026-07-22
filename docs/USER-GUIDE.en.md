# N Agent Bridge — English User Guide

N Agent Bridge currently supports **NuPhy Air75 V3 ANSI** with official firmware **1.0.16.6** on macOS 13 or later.

## Install

1. Download the latest Development DMG from the GitHub Releases page.
2. Open the DMG and drag **N Agent Bridge.app** to **Applications**. Do not run it directly from the DMG.
3. This free Development build is not Apple-notarized. If macOS blocks the first launch, open **System Settings → Privacy & Security** and choose **Open Anyway**. Do not disable Gatekeeper.
4. Allow **Input Monitoring** and **Accessibility** for N Agent Bridge, then quit and reopen the app.

## First-time keyboard setup

1. Update the Air75 V3 ANSI to official firmware `1.0.16.6` in NuPhyIO.
2. Fully close the NuPhyIO browser page so it does not compete for the same HID configuration channel.
3. Put the keyboard in wired mode and connect it with a USB-C data cable.
4. In N Agent Bridge, choose **Connect and Enable** or **Configure Air75 V3**.
5. Wait for the app to back up the complete keymap, install F13–F24, and verify the full readback. Do not unplug the cable during this process.
6. Quit and reopen Codex Desktop once after the first setup.

## Language

The first launch follows the Mac language. Choose **Settings → General → Interface Language** to switch between **中文** and **English** immediately.

## Connections

| Connection | Key controls | Agent status lights | Configuration |
| --- | --- | --- | --- |
| USB-C | Yes | Yes | Full first-time setup and restore |
| Official U1 2.4G receiver | Yes | Yes | Available when firmware forwards the S4 channel |
| Bluetooth | Yes | No | Firmware does not expose a verified live lighting channel |

## Privacy

The app does not record normal typing, passwords, or chat text. It stores no API keys and uploads no HID reports. Keyboard writes are restricted to the exact verified Air75 V3 ANSI identity and are backed up, written, read back, and verified before completion.
