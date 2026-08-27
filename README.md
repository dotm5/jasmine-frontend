<div align="center">
  <h1 align="center">
    Jasmine 

[![license](https://img.shields.io/github/license/ComicSparks/jasmine)](https://raw.githubusercontent.com/ComicSparks/jasmine/master/LICENSE)
[![releases](https://img.shields.io/github/v/release/ComicSparks/jasmine)](https://github.com/ComicSparks/jasmine/releases)
  </h1>
</div>

A comic browser，support Android / iOS / MacOS / Windows / Linux.

## This fork / 前后端分仓

本仓库是 [ComicSparks/jasmine](https://github.com/ComicSparks/jasmine) 的公开前端 Fork，
保留上游 Git 历史和原有声明，便于查看差异与合并更新。

- **公开前端**：[dotm5/jasmine-frontend](https://github.com/dotm5/jasmine-frontend)，默认分支 `master`。
- **私有后端**：[dotm5/jmbackend](https://github.com/dotm5/jmbackend)，默认分支 `main`，通过 `native/` 子模块锁定提交。
- **构建与接口**：[前后端分仓说明](docs/FRONTEND-BACKEND-SPLIT.md)。前端可接入后端产物包，单独打包时不需要 Rust 源码或编译器。
- **上游更新**：[查看上游差异](https://github.com/dotm5/jasmine-frontend/compare/master...ComicSparks:master) · [同步与合并说明](docs/UPSTREAM-SYNC.md)。

普通克隆只获取公开前端；初始化 `native/` 需要后端仓库读取权限。公开 Git 历史只保存
后端仓库地址与提交指针，不包含其 Rust 源码。后端基于 Jenny 并复用固定版本
jmcomic-downloader，继承来源与条件保留在后端仓库中。

当前本地构建入口面向 Android ARM64，应用 ID 为 `opensource.jasmine.local`；
其他平台、真实账号和线上业务需要分别验收。下文特性列表和截图沿用上游介绍，
不代表独立后端的逐项验证结果。原上游 Actions 尚未适配本后端，在此 Fork 中保持禁用。


1. This APP has restricted content
2. Please know local laws before using these codes
3. The owner of the repo will not release these codes and its assets to the community outside github

## Screenshot

#### Browser

![](images/app_screen.png)

#### Reader

![](images/reader_screen.png)

## Features

- [x] Comics
  - [x] Comic categories
  - [x] Comic reader
  - [x] Comic search
  - [x] Comic favours
  - [x] Histories
  - [x] Cache comic
- [ ] Games
- [x] Community
  - [x] List comments
  - [x] Send comments
- [x] User
  - [x] Login / Register
- [x] Devices adaptation
  - [x] Android's high frequency screen

## Technical architecture

Flutter: high-performance UI

Rust: High performance service

![](images/technologies.png)

## Please follow the rules

- These codes can only be learned and used, and are prohibited for commercial use
- Do not send Assets to anyone

