# Extenstion


## 调试位置（插件开发最容易迷路的地方）

要看什么	去哪看
内容脚本的 console.log	目标网页的 DevTools 控制台
background 的日志	chrome://extensions → 找到插件 → 点"service worker"链接
popup 的日志	右键 popup → 检查
看清单是否生成正确	extension/.output/chrome-mv3-dev/manifest.json

background（service worker）会被浏览器回收，不要在模块变量里存状态