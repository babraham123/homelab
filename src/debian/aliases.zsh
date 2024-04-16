alias ls='ls -a'
alias ll='ls -l -a'
alias vi='vim'
alias result='echo $?'

function def {
  # Get the man page of a cmd, source code for a bash function, definition
  # of a cmd alias or the value of an environment variable.
  # Example: def def
  local name=$1
  man $name 2>/dev/null || declare -f $name || alias $name || eval "test -n \"\$$name\" && echo \\\
$$name=\$$name" || echo "$name is unknown"
}

function mans {
  # Jump to the flag meaning in a man page.
  # Example: mans ls -l
  man $1 | less -p "^ +$2"
}

alias master='git checkout master'
alias st='git status'
alias lg='git log --stat'
alias lgg='git log --stat -p'
alias lastcommit='git commit --amend --no-edit'
alias branches='git branch | cut -c 3- | xargs -I@ sh -c '"'"'printf "\e[1;31m%-6s\e[m -> " "@"; git --no-pager log --pretty=format:"%an, %cr%n  %s" --abbrev-commit @^..@; echo ""'"'"''
alias ggrep='git grep -n'
alias gprune='git remote prune origin && git gc --prune=now'

function cdg {
  # cd within your git repo using a relative path that starts from the repo root.
  # Example: cdg sinatra
  cd "$(git rev-parse --show-toplevel)/${1}"
}
