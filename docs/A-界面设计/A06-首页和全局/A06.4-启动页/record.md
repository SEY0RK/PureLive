# A06.4 启动页

- 日期：2026-10-01
- 设计：[docs/A-界面设计/A06-首页和全局/A06.4-启动页/README.md](README.md)（第 1 版，用户已确认；K1、K2 按建议 A）
- 范围：启动页，和启动后自动弹出的提示的先后（两个对话框本身在 [A06.3](../A06.3-全局弹窗/record.md)）。系统启动画面（原生）属于 A14.1，没做。
- 改动的目录：`apps/pure_live/lib/features/splash/`、`apps/pure_live/lib/shared/app_prompts.dart`（新）、文档。没有改原生部分。

## 逐条对照

| 编号 | 要求 | 做到 | 说明 |
|---|---|---|---|
| c1 | 设置“启动动画”（默认开）；图标、“欢迎使用”、进度条三样居中；停 1 秒、最多再等 0.35 秒关注核验；关掉时直接进首页 | ✅ | 去掉了 v4 原来多加的一行“纯粹直播”（v3 没有）；图标 150（v4 原来 132） |
| c2 | 动画 0.4 秒做完（淡入加 0.9→1 放大，减速、不回弹） | ✅ | `Curves.decelerate`；离开时图标和文字完整显示 |
| c3 | 背景跟主题：表面色，右下角带一点主色容器色；深色用深色表面 | ✅ | 渐变 表面色 → 表面色（45%）→ 主色容器（浅色 70%、深色 45%，叠在表面色上），方向照效果图的 160° |
| c4 | 进度条主色，底轨主色 15%，圆头 | ✅ | 宽 200、高 4 |
| c5 | 图标和“欢迎使用”之间留 16 | ✅ | 文字 20 号 600 字重；进度条在文字下 32 |
| c6 | 点一下直接进首页 | ✅ | 另外电脑上按任意键也直接进（“各客户端”一节） |
| c7 | 启动后的提示排队：同一时间只开一个；口令导入先，新版本后；新版本只在首页弹，进了直播间就等回到首页 | ✅（口令导入的触发在 M12.5） | 见下 |
| c8 | Android 系统启动画面同底色 | — | 交给 A14.1（任务书要求不做） |
| 各客户端 | 状态栏透明，图标颜色跟深浅色 | ✅ | `AnnotatedRegion` |

**提示的先后**（`shared/app_prompts.dart` 的 `AppPrompts`）：应用自己弹的提示（`AppPromptKind.share` 口令导入、`AppPromptKind.update` 新版本）排一个队：同一时间只开一个；几个同时等时口令导入先；一个提示可以带“时机”（新版本的时机是首页在最上面）。页面或对话框每变一次（`liveRouteObserver`）、一个提示关掉一帧以后，重新看等着的提示能不能弹——所以口令导入点“进入房间”后，新版本会等直播间盖上去再判断，回到首页才弹。

偏差：口令导入的识别（读剪贴板、解码分享口令）不在 v4 主线上，在暂停的 M12.5 分支（`ClipboardRoomWatcher`）。这次做了对话框和排队（`showRoomPrompt` 自动排在新版本前面），合并 M12.5 时它的 `prompt` 回调改用这里的 `showRoomPrompt` 即可，见 [A06.3](../A06.3-全局弹窗/record.md)“需要决定的”。

## v3 文件 → v4 文件

| v3 | v4 |
|---|---|
| `modules/splash/splash_screen.dart`、`routes/app_pages.dart:188-235` | `features/splash/splash_page.dart` |
| `common/global/platform/desktop_manager.dart:595-650`（口令导入的时机）、`modules/home/home_page.dart:99-104`、`:198-216`（新版本的时机） | `shared/app_prompts.dart`；`features/version/update_prompt.dart`（`checkForUpdateOnStartup` 走队列） |

## 新设置

无。

## 门禁

`splash` 没有直接写的颜色和图标（前后都是 0）。

## 测试

- `test/features/splash/splash_page_test.dart`：3 → 8 个：0.4 秒内透明度只增、放大不超过 1、0.4 秒时完整；图标 150、文字在图标下 16、进度条 200 宽在文字下 32、主色和 15% 底轨、没有“纯粹直播”；浅色和深色的背景都取主题颜色（没有 3.x 的青色）；电脑按任意键进首页。原有三个照旧。
- `test/shared/app_prompts_test.dart` 的排队部分 2 个：第二个提示等第一个关掉、口令导入插到新版本前面、返回顺序；没到时机的提示在页面变化后才弹。
- `update_dialogs_test.dart` 里“另一个页面在上面时新版本不弹，回到首页才弹”1 个（总数见 A06.3）。

## 2026-11-16 启动页改成首页的子路由（Windows 上启动时转场顿卡）

现象（Windows 便携版）：启动页停一秒后左滑进首页，动画头几帧顿。

原因：启动页原来是首页**前面**的一个路由，两页不在同一个位置，所以首页整个第一帧都落在那 450 毫秒动画里——整棵树第一次 build、第一次 layout、第一次 paint，关注列表的第一次核验结果正好在这几百毫秒里落地并把整页重建一遍，封面也从这时才开始解码上传。启动页那一秒是白等的：它盖着的时候首页一行都还没建。

改动：

- `apps/pure_live/lib/routes/route_path.dart`：`kSplash` 从 `/splash` 改成 `/home/splash`（`kInitial` + `kSplashSegment`），是首页的子路由，一个位置同时建两页；没有别的地方链到 `/splash`。
- `apps/pure_live/lib/routes/app_router.dart`：新增 `splashRoute()`，挂在 `kInitial` 的 `routes` 下（`pageRoutes` 里删掉 `kSplash`）；`apps/pure_live/lib/routes/tv_router.dart` 同样挂一次。
- `apps/pure_live/lib/features/splash/splash_page.dart`：新增 `SplashRoutePage` / `_SplashRoute`，启动页的路由**半透明**（`opaque: false`）。这一条是关键：不透明的话，下面的首页虽然建好了，但 Flutter 不给不在台上的页量尺寸，而网格的卡片是在量尺寸时才建的；半透明让首页一直在台上，启动页那一秒里首页就建完、量完、画完，关注列表落地和封面解码上传也都在这一秒里。
- `packages/live_ui/lib/src/theme/page_transitions.dart`：新增 `SplashExitTransition`，只有启动页往左整页滑出（450 毫秒，同一个弹簧，不淡入淡出，不给下面的页加阴影），下面的页按它自己的转场回位。
- `apps/pure_live/lib/features/home/home_page.dart`：命令行给的房间等启动页退场再开（`_roomAfterReveal`，`didPopNext` 里放）——现在就开会盖住启动页，再被启动页“回首页”冲掉。

手感变了：以前是启动页退 1/4、首页从右边推进来；现在是启动页整页滑出左边、首页从左边 1/4 处回位并变亮。

计时：`home` 仍然是首页到顶（启动页退场）的时刻；但首页在下面已经开始出内容，所以 `firstPage` 现在可能比 `home` 早（以前一定在它之后）。要量“用户看到内容”的时刻，看 `home`。提示排队照旧：路由观察者看到的当前路由还是 `kSplash`，启动页在的时候不会弹（`ready` 看的是首页 `isCurrent`）。

测试：`packages/live_ui/test/page_transitions_test.dart` +1：启动页在第一帧就往左边走了 100 以上、没有 `OpacityLayer`、退完下面的页回到原位、时长等于推入的 450 毫秒。`apps/pure_live/test/features/splash/splash_page_test.dart` +1：启动页的路由 `opaque` 为假（首页才会被量、被画）、退场时长等于转场时长；其余 8 个没改（它们自己搭路由，行为照旧）。
