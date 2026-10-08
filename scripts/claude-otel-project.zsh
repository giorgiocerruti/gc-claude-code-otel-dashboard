# Aggiunge la label project.name alle metriche OTel di Claude Code.
# Per i worktree git usa il nome del repository principale, non della cartella del worktree.
# Installazione: aggiungi in ~/.zshrc  ->  source /percorso/claude-otel-project.zsh

_claude_otel_project() {
  local common name
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  if [ -n "$common" ] && [ "${common##*/}" = ".git" ]; then
    name=$(basename "$(dirname "$common")")
  else
    name=$(basename "$PWD")
  fi
  # niente virgole, spazi o uguali: separatori di OTEL_RESOURCE_ATTRIBUTES
  print -r -- "${name//[ ,=]/_}"
}

claude() {
  # OTEL_LOG_TOOL_DETAILS=1: nomi reali di agenti custom, skill e MCP (altrimenti "custom"/"third-party")
  OTEL_LOG_TOOL_DETAILS=1 \
  OTEL_RESOURCE_ATTRIBUTES="project.name=$(_claude_otel_project)${OTEL_RESOURCE_ATTRIBUTES:+,$OTEL_RESOURCE_ATTRIBUTES}" command claude "$@"
}
