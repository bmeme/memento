#!/usr/bin/env bash

ROOT=($(memento schema root))
TOOLS=()
SUGGESTIONS=()

function jsonValue()
{
  KEY=$1
  num=$2
  awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'$KEY'\042/){print $(i+1)}}}' | tr -d '"' | sed -n ${num}p
}

_memento_get_tools()
{
  local tools_list=($(cd $ROOT/Memento/Tool && ls))

  for TOOL in ${tools_list[@]}
  do
    local tool_name=(${TOOL/.pm/})
    TOOLS+=(${tool_name})
  done
}

_memento_tool_completions()
{
  SUGGESTIONS=("${TOOLS[@]}")
}

_memento_bookmarks_completions()
{
  COMPREPLY=()
  SUGGESTIONS+=($(compgen -W "$(cat ~/.memento/history_cfg | jsonValue name)" -- "${COMP_WORDS[1]}"))
}

_memento_tool_command_completions()
{
  local TOOL=${COMP_WORDS[1]}

  if [[ -f $ROOT/Memento/Tool/${TOOL}.pm ]]; then
    local tool_suggestions=($(cd $ROOT/Memento/Tool && egrep -i '^sub [a-z]+' $TOOL.pm))
    local REPLY=()

    for tool_suggestion in ${tool_suggestions[@]}
    do
      local raw_suggestion=${tool_suggestion/sub}
      raw_suggestion=${raw_suggestion/\{}
      local suggestion=(${raw_suggestion})
      REPLY+=(${suggestion/,})
    done

    COMPREPLY=("${REPLY[@]}")
  fi
}

_memento_completions()
{
  _memento_get_tools

  if [[ "${COMP_CWORD}" == "1" ]];then
    _memento_tool_completions
    _memento_bookmarks_completions
    COMPREPLY=("${SUGGESTIONS[@]}")
  elif [[ "${COMP_CWORD}" == "2" ]];then
    _memento_tool_command_completions
  else
    COMPREPLY=()
  fi
}

complete -F _memento_completions memento
