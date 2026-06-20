# Confluence 热门 iOS

一个面向 Confluence Server / Data Center 自建站点的原生 SwiftUI 客户端。它保留官方移动端的清爽信息流风格，并补上“热门”板块。

## 功能

- 支持输入第三方自建站点 URL、用户名和密码。
- 使用 Basic Auth 访问 Confluence REST API，密码保存在 iOS Keychain。
- “热门”优先读取 `/rest/popular/1/stream/content`，站点未启用该插件时降级到 CQL 最近活动内容。
- “最新”使用 `/rest/api/content/search` 和 CQL 拉取页面、博客。
- 支持搜索、详情渲染、评论列表、添加回复，以及跳转到 Confluence Web 页面。
- 支持夜间模式、字号调整、霞鹜文楷字体、横屏分栏阅读。
- 支持本地热门提醒：每天或每周在系统允许的后台刷新窗口中检查新的热门内容。

## 验证过的接口

已用提供的测试站点验证：

- `GET /rest/api/user/current`
- `GET /rest/api/content/search`
- `GET /rest/popular/1/stream/content`
- `GET /rest/api/content/{id}/child/comment`

密码没有写入仓库。请在 App 登录页手动输入测试账号。

热门提醒使用 iOS Background App Refresh 和本地通知，执行时间由系统调度，不保证严格准点。未配置 Apple Push Notification 服务，因此不是服务器实时推送。

## 构建

用 Xcode 打开 `ConfluenceHot.xcodeproj`，选择 `ConfluenceHot` scheme 后运行到 iPhone 模拟器或真机。

当前机器只有 Command Line Tools，没有完整 Xcode，因此这里无法执行 `xcodebuild` 的 iOS 构建。

## 打包资源

- App Icon 使用 Atlassian 在 App Store 发布的 Confluence Data Center 官方图标资源生成。
- 中文字体打包 `LXGW WenKai / 霞鹜文楷`，文件位于 `ConfluenceHot/Resources/Fonts/LXGWWenKai-Regular.ttf`。

## 本地真机验证

最方便的方式是 Xcode 直接安装到 iPhone，不需要先导出 IPA：

1. 安装完整 Xcode，并打开一次完成组件安装。
2. 打开 `ConfluenceHot.xcodeproj`。
3. 在 Xcode 的 `Settings > Accounts` 添加 Apple ID，免费账号即可本机调试。
4. 选中 `ConfluenceHot` target，在 `Signing & Capabilities` 里选择你的 Personal Team。
5. 用数据线连接 iPhone，在 iPhone 上信任这台 Mac。
6. Xcode 顶部设备选择你的 iPhone，点击 Run。

免费 Apple ID 安装到真机后通常有效 7 天；付费 Apple Developer 账号可用于更稳定的真机包、Ad Hoc、TestFlight 或 App Store 分发。

IPA 只有在你要发给别人安装、走 TestFlight、Ad Hoc，或用 AltStore/SideStore 这类侧载工具时才需要。单机验证优先用 Xcode Run。

## GitHub Actions 构建 IPA

仓库已经包含 `.github/workflows/ios-ipa.yml`。推送到 GitHub 后，每次 push 到 `main` 或手动运行 workflow，都会在 GitHub 的 macOS runner 上构建：

- artifact 名称：`ConfluenceHot-unsigned-ipa`
- 文件：`ConfluenceHot-unsigned.ipa`

这个 IPA 是未签名包，不能直接从 Safari 下载后安装到 iPhone。免费账号路线可以用 AltStore、SideStore 等工具在本地用 Apple ID 重新签名安装。付费 Apple Developer 账号路线则可以继续把证书和 provisioning profile 放进 GitHub Secrets，改成 Ad Hoc 或 TestFlight 分发。

上传 GitHub 后的使用方式：

1. 打开仓库的 `Actions`。
2. 进入 `Build iOS IPA`。
3. 点 `Run workflow`，或 push 到 `main` 自动触发。
4. 构建完成后，在页面底部下载 `ConfluenceHot-unsigned-ipa` artifact。
5. 用 AltStore/SideStore 导入 `ConfluenceHot-unsigned.ipa` 后安装到 iPhone。

## 发布 Release

Release 推荐用 tag 触发。推送 `v*` tag 后，GitHub Actions 会自动构建 unsigned IPA，并创建或更新对应的 GitHub Release：

```bash
git tag v1.0.2
git push origin v1.0.2
```

如果只 push 到 `main`，Actions 只生成临时 artifact，不会自动生成 Release。
