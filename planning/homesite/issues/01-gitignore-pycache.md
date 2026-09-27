# 01. Stop tracking __pycache__

Status: ready-for-agent
Type: task
Repo: homesite
Source: review finding 39

```bash
printf '\n# Python\n__pycache__/\n*.pyc\n' >> .gitignore
git rm --cached -r src/www/hooks/__pycache__
```

## Comments
