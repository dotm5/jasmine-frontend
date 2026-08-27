# 保持与上游前端同步

本仓库保留 [ComicSparks/jasmine](https://github.com/ComicSparks/jasmine) 的真实 Fork 关系、
完整默认分支历史和共同祖先。私有后端是另一个独立仓库，不参与上游前端同步。

## 网页入口：查看差异，再合并

1. 打开 [上游相对本 Fork 的新增差异](https://github.com/dotm5/jasmine-frontend/compare/master...ComicSparks:master)。
   这里展示共同祖先之后的上游变化，不是两端完整文件树的逐文件对比。
2. 在 [本 Fork 首页](https://github.com/dotm5/jasmine-frontend) 使用 **Sync fork → Update branch**。
   无冲突时可以直接同步；有冲突时转入 PR/本地解决，不覆盖自己的提交。
3. 合并后更新本地前端、检查接口并回归。网页合并本身不代表本项目构建或业务测试通过。

希望**验证通过后再合并 `master`**时，使用下一节的同步分支与 PR 流程。
不要使用强制同步，也不要把上游更新压成 squash commit；保留祖先关系便于下一次合并。

## 本地远程配置

当前维护工作区已配置：

```text
origin    https://github.com/dotm5/jasmine-frontend.git
upstream  https://github.com/ComicSparks/jasmine.git
```

Git remotes 是本地配置，不会随普通克隆自动继承。新克隆中只需补充一次：

```powershell
git remote add upstream https://github.com/ComicSparks/jasmine.git
git config --local remote.pushDefault origin
gh repo set-default dotm5/jasmine-frontend
```

已有 `upstream` 时先用 `git remote -v` 核对，不重复添加。
上游默认分支和本 Fork 默认分支均为 `master`，后端默认为 `main`。

## 同步分支与 PR

先确认前端和子模块没有未提交工作，切回已同步的本地 `master`，再获取上游：

```powershell
git status --short
git -C native status --short
git switch master
git pull --ff-only origin master
git fetch upstream master
git log --oneline master..upstream/master
git diff --stat master...upstream/master
git diff master...upstream/master
```

`git log` 没有上游新增提交时，本轮无需合并。已有改动先单独处理，不自动 stash、reset
或覆盖。仅前端开发者可以省略未初始化子模块的状态检查。

确认存在待合并更新后：

```powershell
$branch = 'sync/upstream-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
git switch -c $branch master
git merge --no-ff --no-commit upstream/master
```

若有冲突，手动处理相关路径并逐个 `git add -- <path>`，随后检查暂存区。
不要混入新的后端版本或本地审计文件。需要退出本次合并时使用 `git merge --abort`。

维护者在已有本地工具环境中验证完整契约；公开前端开发者可以先跑 `flutter test test`
中的 mock 测试，并由后端维护者补完整集成验收：

```powershell
pwsh -NoLogo -NoProfile -NonInteractive -File scripts/test-api-contracts.ps1
git diff --cached --stat
git diff --cached --submodule=log
git commit -m "Merge upstream frontend changes"
git push -u origin $branch
gh pr create --repo dotm5/jasmine-frontend --base master --head $branch `
  --title 'Merge upstream frontend changes' `
  --body 'Preserve upstream history; review the diff and recorded integration results before merging.'
```

测试失败时保留同步分支继续处理，验证后才提交和合并。PR 选择 **Create a merge commit**，
不选择 Squash/Rebase，以保留真正的上游合并关系。该 Fork 已启用 merge commit。

完成后拉取前端 `master`；若别的变更同时更新了后端 gitlink，再按前端固定版本初始化：

```powershell
git switch master
git pull --ff-only origin master
git submodule update --init -- native
```

同步只合并上游已公开的前端提交；它不会自动更新私有后端、安装工具或创建定时任务。
