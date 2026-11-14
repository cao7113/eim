wxt/0.21.5

Usage:
  $ wxt [root]

Commands:
  [root]            start dev server
  build [root]      build for production
  zip [root]        build for production and zip output
  prepare [root]    prepare typescript project
  clean [root]      clean generated files and caches
  init [directory]  initialize a new project
  submit [...args]  Alias for publish-extension (https://www.npmjs.com/publish-browser-extension)

For more info, run any command with the `--help` flag:
  $ wxt --help
  $ wxt build --help
  $ wxt zip --help
  $ wxt prepare --help
  $ wxt clean --help
  $ wxt init --help
  $ wxt submit --help

Options:
  -c, --config <file>                   use specified config file 
  -m, --mode <mode>                     set env mode 
  -b, --browser <browser>               specify a browser 
  --host <host>                         specify a host for the dev server to bind to 
  -p, --port <port>                     specify a port for the dev server to bind to 
  -e, --filter-entrypoint <entrypoint>  only build specific entrypoints 
  --mv3                                 target manifest v3 
  --mv2                                 target manifest v2 
  --debug                               enable debug mode 
  --level <level>                       specify log level ("silent" | "fatal" | "error" | "warn" | "log" | "info" | "success" | "fail" | "ready" | "start" | "box" | "debug" | "trace" | "verbose") 
  -h, --help                            Display this message 
  -v, --version                         Display version number 
