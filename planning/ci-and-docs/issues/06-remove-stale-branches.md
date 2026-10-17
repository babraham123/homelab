# 06. Delete the stale ansible/fixes/fixes0/worktree-ntfy branches on origin

Status: resolved
Type: task
Repo: homelab
Source: review finding 38

## Change

Check nothing unmerged is worth keeping, then delete:

```bash
git log --oneline main..origin/ansible | head
git log --oneline main..origin/fixes | head
git log --oneline main..origin/fixes0 | head
git push origin --delete ansible fixes fixes0 worktree-ntfy
```

`origin/worktree-ntfy` was merged in `e3b9348` (2026-09) and can go with the others.

Marked for a human because it is a destructive remote operation.

## Comments

- 2026-10-17: Resolved. `git ls-remote --heads origin` lists only `main`; ansible, fixes, fixes0
  and worktree-ntfy are gone from origin.
