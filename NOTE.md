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

## API实现

- 优先使用 AshJsonApi 风格开发
- 方便内置的 SwaggerUI 支持

## 数据源

先 ECDICT、再 LLM，有两个好处：

ECDICT 阶段不花钱、延迟低，插件划词出中文释义就已经可用，能先验证"划词 → 收藏"的整条链路。
LLM 是增强层，不是依赖：LLM 调用失败、超限、断供时，产品仍能回退到词典结果，不会整体不可用。

词典数据（ECDICT） https://github.com/skywind3000/ECDICT

https://www.rememberry.in/
Dictionary by [FreeDictionaryAPI.com](http://freedictionaryapi.com/) & [Wiktionary.org](http://wiktionary.org/)

ECDICT（已有）：中文释义、词形、难度。
kaikki 子集：英文释义和例句，只导入高频词。
Tatoeba：给常用词补中英例句。
OEWN：作为 LLM 做语境释义的候选义项来源。
Microsoft 术语：做一个"技术释义"的标注层，浮窗里在技术页面优先展示。
LLM 兜底：以上都没有或语境特殊时。

7. 授权管理：从第一天就做

不同来源的授权不一样（MIT、CC BY、CC BY-SA、其他），混在一起容易出问题。建议每条数据记录三样东西：

来源（ecdict / wiktionary / tatoeba / oewn / ms_terms）
来源版本或日期
授权和署名信息

### Links

- http://localhost:4000/api/json/swaggerui
- http://localhost:4000/admin
- http://localhost:4000/oban
