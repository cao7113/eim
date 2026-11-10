# Design

Eim - English IMproved for continuous learners.

## 业务描述和定位

这是一款英语持续学习的工具，包括浏览器插件用于划词翻译和 web 网页用于学习中心

初期功能：

浏览器插件
- 划词 翻译
- 收藏 auto-save

Web 和 Admin
- 生词管理 & llm 调用
- 缓存管理

### 进度

- phoenix 项目已初步搭建
- wxt 项目未搭建

## 整体架构设计

- 主项目是 phoenix 项目，phoenix 默认布局结构，方便业务开发
    - 目前网页 Web 版主要基于 phoenix liveview 开发
- 浏览器插件单独维护在一个自己的独立目录 extension/
    - 后期可单独拆出去独立维护或开源等

## 技术框架

### 浏览器插件

- bun
- WXT https://wxt.dev/ 
- WXT 本身基于 Vite。真正缺的是插件 UI 框架，建议在文档里定下来（浮窗追求小体积，Svelte、Solid、Preact 都合适）

### 后端

- phoenix v1.8+
- ash v3.0+
- json-api & openapi & swappterUI
- PostgreSQL、AshAuthentication、Oban、HTTP 客户端（Req & ReqClient）
- AshTypescript? 用于类型共享？

## 插件开发

- https://wxt.dev/guide/installation.html

```
bunx wxt@latest init extension
✔ Choose a template › svelte
✔ Package Manager › bun
Next steps:        
  1. cd extension    
  2. bun install 
```

### Links

- http://localhost:4000/api/json/swaggerui
- http://localhost:4000/admin
- http://localhost:4000/oban
