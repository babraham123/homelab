function def {
  # Get the man page of a cmd, source code for a bash function, definition
  # of a cmd alias or the value of an environment variable.
  # Example: def def
  local name=$1
  man $name 2>/dev/null || declare -f $name || alias $name || eval "test -n \"\$$name\" && echo \\\$$name=\$$name" || echo "$name is unknown"
}

function mans {
  # Jump to the flag meaning in a man page.
  # Example: mans ls -l
  man $1 | less -p "^ +$2"
}

function pull {
  # Update main and rebase your branch on top of it.
  # Example: pull
  local BRANCH="$(git rev-parse --abbrev-ref HEAD)"
  if [ "$BRANCH" = "main" ]; then
    git pull --rebase
    return 0
  fi

  if [ "$1" = "-s" ]; then
    git stash --include-untracked
  fi
  git checkout main || return 1
  git pull --rebase || return 1
  git checkout "$BRANCH" || return 1
  git rebase main || return 1

  if [ "$1" = "-s" ]; then
    git stash pop
  fi
}

function push {
  local BRANCH="$(git rev-parse --abbrev-ref HEAD)"
  if [ "$BRANCH" = "main" ]; then
    return 1
  fi
  git push -f origin "$BRANCH"
}

function gdiff {
  # customized version of `git diff`
  # Usage: gdiff [-l] [-f] [filename]
  # -l show lines
  # -f files only

  opt2="."
  if [ ! -z "$1" ] && [ "$1" != "-l" ] && [ "$1" != "-f" ]; then
    opt2="${1}"
  fi

  if [ ! -z "$2" ]; then
    opt2="${2}"
  fi

  if [ "$1" = "-l" ]; then
    git diff HEAD~..HEAD --color=always -- "$opt2" | \
    gawk '{bare=$0;gsub("\033[[][0-9]*m","",bare)};\
      match(bare,"^@@ -([0-9]+),[0-9]+ [+]([0-9]+),[0-9]+ @@",a){left=a[1];right=a[2];next};\
      bare ~ /^(---|\+\+\+|[^-+ ])/{print;next};\
      {line=gensub("^(\033[[][0-9]*m)?(.)","\\2\\1",1,$0)};\
      bare~/^-/{printf   "-%+4s     :%s\n", left++, line;next};\
      bare~/^[+]/{printf "+%+4s     :%s\n", right++, line;next};\
      {printf            " %+4s,%+4s:%s\n", left++, right++, line;next}' | less
  elif [ "$1" = "-f" ]; then
    git diff --stat HEAD~..HEAD
  else
    git diff HEAD~..HEAD --color=always -- "$opt2"
  fi
}

function hgrep {
  git grep -n "$@" $(git rev-list --all -- .) -- .
}

function cdg {
  # cd within your git repo using a relative path that starts from the repo root.
  # Example: cdg sinatra
  cd "$(git rev-parse --show-toplevel)/${1}"
}
