# 01. Stop tracking __pycache__

Status: resolved
Type: task
Repo: homesite
Source: review finding 39

```bash
printf '\n# Python\n__pycache__/\n*.pyc\n' >> .gitignore
git rm --cached -r src/www/hooks/__pycache__
```

## Comments

- 2026-10-17: verified done in the homesite repo: `.gitignore` lists `__pycache__/` and
  `git ls-files` tracks no `__pycache__` files.
