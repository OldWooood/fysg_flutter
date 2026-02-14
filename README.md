# 福音诗歌 (Gospel Songs)

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
*   **分类浏览**：支持按歌单、专辑、诗歌本、作者等多种维度探索。
*   **长辈适配**：深度优化了大字体下的排版布局，确保文字不重叠、不溢出。
*   **多语言支持**：原生支持中文与英文。

## 技术栈

*   **核心框架**: [Flutter](https://flutter.dev/)
*   **状态管理**: [Flutter Riverpod](https://riverpod.dev/)
*   **音频引擎**: [just_audio](https://pub.dev/packages/just_audio) & [audio_service](https://pub.dev/packages/audio_service)
*   **网络请求**: [http](https://pub.dev/packages/http) & [dio](https://pub.dev/packages/dio) (用于下载)
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

---

*“用诗章、颂词、灵歌，彼此说照，口唱心和地赞美主。” (以弗所书 5:19)*
