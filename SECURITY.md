# Security Policy

## Reporting

Do **not** open a public issue for a security problem in this project or in
the build infrastructure it documents. Contact the maintainer privately first
and give a reasonable response window.

This repository contains no credentials or private keys by design. If you find
any that were committed by accident, report them privately and do not reuse or
publish them.

## Safe-use boundary

- This project does not ship proprietary blobs, stock firmware, or flashable
  images.
- No script in this repository is permission to write a device partition.
  Flashing always requires a separate, explicit confirmation by the device
  owner.
- Builders referenced by documentation are private; configure your own
  `rom-builder` SSH alias and keep its host key verification enabled.

## 中文说明

安全问题请私下联系维护者，不要公开 issue。仓库按设计不含凭证与私钥；如
发现误提交请私下报告。本项目不带专有 blobs、stock 固件与刷机包；任何脚本
都不构成刷写设备分区的授权，刷机必须由机主单独明确确认。
