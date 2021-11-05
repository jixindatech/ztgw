## ztgw
这是ztserver的网关组件，主要用来做策略检测，测试阶段。

## 安装
建议通过 luarocks 进行安装。
支持docker, docker build -t ztgw .

## 配置文件说明
- secret需要与ztserver的保持一致，需要解密token的内容。
- 日志可以通过rsyslog转发或者发往kafka，直接配置。
- 只读 redis 中的数据

## Contributing
PRs accepted.

## Discussion Group
QQ群: 254210748

## License 

