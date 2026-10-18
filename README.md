# 福音诗歌 (Gospel Songs)

![CI](https://github.com/OldWooood/fysg_flutter/actions/workflows/ci.yml/badge.svg)

一个基于 Flutter 开发的高颜值、极简主义福音诗歌音乐播放器。本项目旨在为弟兄姊妹提供愉悦的查阅和聆听体验，特别针对年长用户进行了字体和操作优化。

## 特色功能

*   **杂志级视觉设计**：采用大字体、粗线条的杂志化排版（Magazine Style），视觉冲击力强且易于阅读。
*   **智能搜索联想**：支持关键词自动补全，助您快速找到心仪的诗歌。
*   **强大播放体验**：
    *   支持后台播放及通知栏控制。
    *   内置三种播放模式：顺序播放、随机播放、单曲循环。
    *   实时歌词同步，支持多时间戳解析及平滑滚动。
*   **离线与缓存**：
    *   支持歌曲下载，可在无网络环境下播放。
    *   智能图片缓存，即便在网络波动时也能流畅显示封面。
*   **分类浏览**：支持按歌单、专辑探索。
*   **长辈适配**：深度优化了大字体下的排版布局，确保文字不重叠、不溢出。
*   **多语言支持**：原生支持中文与英文。

## 技术栈

*   **核心框架**: [Flutter](https://flutter.dev/)
*   **状态管理**: [Flutter Riverpod](https://riverpod.dev/)
*   **音频引擎**: [just_audio](https://pub.dev/packages/just_audio) + [audio_service](https://pub.dev/packages/audio_service)
*   **网络请求**: [dio](https://pub.dev/packages/dio)（API 与下载统一走 dio，带超时/重试/取消）
*   **图片处理**: [cached_network_image](https://pub.dev/packages/cached_network_image)
*   **本地存储**: [shared_preferences](https://pub.dev/packages/shared_preferences) & [path_provider](https://pub.dev/packages/path_provider)

## 特别鸣谢

本项目所有音频、图片及歌词数据均通过公开接口获取，在此对 **[福音诗歌 (www.fysg.org)](https://www.fysg.org/)** 表示最诚挚的感谢。该平台为福音事工提供了宝贵的资源支持。

## 如何运行

1.  克隆本项目：
    ```bash
    git clone https://github.com/OldWooood/fysg_flutter.git
    ```
2.  进入项目目录：
    ```bash
    cd fysg_flutter
    ```
3.  安装依赖：
    ```bash
    flutter pub get
    ```
4.  运行程序：
    ```bash
    flutter run
    ```

## 开发

```bash
flutter analyze                              # 静态检查（CI 必过）
flutter test                                 # 单元/服务层测试
dart format --output=none --set-exit-if-changed lib test integration_test
```

持续集成见 `.github/workflows/ci.yml`（格式检查 + analyze + test）。

### 发布构建

Flutter 默认已在 release 构建启用 R8 代码压缩与资源收缩；Dart 侧建议同时开启混淆与符号分离，
包体更小且线上堆栈可回溯（符号文件务必归档，崩溃还原依赖它）：

```bash
flutter build apk --release --obfuscate --split-debug-info=build/symbols
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols
```

崩溃还原：`flutter symbolize -i <stacktrace> -d build/symbols/app.android-arm64.symbols`

> 注：Android 网络安全配置只允许 HTTPS（`android/app/src/main/res/xml/network_security_config.xml`），
> 已为 localhost/模拟器保留明文回环。若服务端 CDN 迁移到 http 域名，需把该域名加进白名单，
> 否则封面/播放会被系统拦截。

---

*“用诗章、颂词、灵歌，彼此说照，口唱心和地赞美主。” (以弗所书 5:19)*
