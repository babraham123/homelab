export EDITOR="vim"

export HISTFILE=~/.zsh_history
export HISTSIZE=10000
export SAVEHIST=10000
setopt appendhistory

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
