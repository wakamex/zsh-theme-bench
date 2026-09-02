#!/usr/bin/env zsh

builtin emulate -L zsh -o no_aliases -o err_return -o pipe_fail -o extended_glob

usage() {
  print -r -- 'usage: collect-omz-theme-metadata.zsh [--omz DIR] [--output FILE] [--limit N]'
  print -r -- ''
  print -r -- 'Collects last-update and Git/Zsh integration metadata from a full local OMZ history.'
  print -r -- 'Existing rows in the output TSV are resumed automatically.'
}

fail() {
  print -u2 -r -- "error: $*"
  return 1
}

source_uses() {
  local pattern=$1
  local source=$2
  print -r -- "$source" | command rg -q -- "$pattern"
}

count_direct_git_calls() {
  command awk '
    /^[[:space:]]*#/ { next }
    {
      line = $0
      pattern = "(^|[[:space:](;|&])((command|builtin)[[:space:]]+)?git[[:space:]]+"
      while (match(line, pattern)) {
        count += 1
        line = substr(line, RSTART + RLENGTH)
      }
    }
    END { print count + 0 }
  '
}

local script_dir=${0:A:h}
local omz_dir=${ZSH:-${HOME}/.oh-my-zsh}
local output=''
local limit=0

while (( $# )); do
  case $1 in
    --omz)
      (( $# >= 2 )) || fail '--omz requires a directory'
      omz_dir=$2
      shift 2
      ;;
    --output)
      (( $# >= 2 )) || fail '--output requires a file'
      output=$2
      shift 2
      ;;
    --limit)
      (( $# >= 2 )) || fail '--limit requires a count'
      limit=$2
      shift 2
      ;;
    -h|--help)
      usage
      return 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

[[ $limit == <-> ]] || fail '--limit must be a non-negative integer'
(( $+commands[rg] )) || fail 'rg is required'

omz_dir=${omz_dir:A}
[[ -d $omz_dir/.git ]] || fail "not a Git checkout: $omz_dir"

local omz_commit shallow
omz_commit=$(command git -C "$omz_dir" rev-parse HEAD 2>/dev/null) \
  || fail "cannot resolve HEAD: $omz_dir"
shallow=$(command git -C "$omz_dir" rev-parse --is-shallow-repository)
[[ $shallow == false ]] \
  || fail 'OMZ history is shallow; fetch --unshallow before collecting metadata'

if [[ -z $output ]]; then
  output="$script_dir/omz-theme-metadata-${omz_commit[1,12]}.tsv"
fi
output=${output:A}

local tree_paths
tree_paths=$(command git -C "$omz_dir" ls-tree -r --name-only "$omz_commit" -- themes)
local -a theme_paths
theme_paths=("${(@f)$(print -r -- "$tree_paths" | command rg '^themes/[^/]+[.]zsh-theme$')}")
(( ${#theme_paths} )) || fail "no .zsh-theme files found at $omz_commit"

if (( limit > 0 && limit < ${#theme_paths} )); then
  theme_paths=("${theme_paths[@]:0:$limit}")
fi

command mkdir -p "${output:h}"

local header=$'snapshot_at_utc\tomz_commit\ttheme\tlast_commit_at\tlast_commit_sha\tuses_git_prompt_info\tuses_parse_git_dirty\tuses_vcs_info\tdirect_git_calls\tuses_zle_fd_handler\tuses_zsh_hooks\tlast_commit_subject'
if [[ -e $output ]]; then
  local existing_header
  IFS= read -r existing_header < "$output"
  [[ $existing_header == $header ]] || fail "unexpected TSV header: $output"
else
  print -r -- "$header" > "$output"
fi

local -A completed
local row_time row_commit row_theme row_last_at row_last_sha
local row_git_info row_dirty row_vcs row_direct row_zle row_hooks row_subject
while IFS=$'\t' read -r \
    row_time row_commit row_theme row_last_at row_last_sha \
    row_git_info row_dirty row_vcs row_direct row_zle row_hooks row_subject; do
  [[ $row_time == snapshot_at_utc ]] && continue
  [[ $row_commit == $omz_commit ]] \
    || fail "output contains a different OMZ commit: $row_commit"
  completed[$row_theme]=1
done < "$output"

local total=${#theme_paths}
local cached=0
local theme_path theme_name
for theme_path in $theme_paths; do
  theme_name=${${theme_path:t}%.zsh-theme}
  (( ${+completed[$theme_name]} )) && (( cached += 1 ))
done
local pending=$(( total - cached ))

print -r -- "themes=$total cached=$cached pending=$pending"
print -r -- "output=$output"

local collected=0
local commit_row commit_sha commit_rest last_commit_at commit_subject theme_source
local uses_git_prompt_info uses_parse_git_dirty uses_vcs_info direct_git_calls
local uses_zle_fd_handler uses_zsh_hooks

for theme_path in $theme_paths; do
  theme_name=${${theme_path:t}%.zsh-theme}
  (( ${+completed[$theme_name]} )) && continue

  commit_row=$(command git -C "$omz_dir" log -1 \
    --format=$'%H\t%cI\t%s' "$omz_commit" -- "$theme_path")
  [[ -n $commit_row ]] || fail "no history found for $theme_path"
  commit_sha=${commit_row%%$'\t'*}
  commit_rest=${commit_row#*$'\t'}
  last_commit_at=${commit_rest%%$'\t'*}
  commit_subject=${commit_rest#*$'\t'}
  commit_subject=${commit_subject//$'\t'/ }
  commit_subject=${commit_subject//$'\r'/ }

  theme_source=$(command git -C "$omz_dir" show "${omz_commit}:${theme_path}")

  uses_git_prompt_info=0
  uses_parse_git_dirty=0
  uses_vcs_info=0
  uses_zle_fd_handler=0
  uses_zsh_hooks=0

  source_uses '^[[:space:]]*[^#].*\bgit_prompt_info\b' "$theme_source" \
    && uses_git_prompt_info=1
  source_uses '^[[:space:]]*[^#].*\bparse_git_dirty\b' "$theme_source" \
    && uses_parse_git_dirty=1
  source_uses '^[[:space:]]*[^#].*\bvcs_info\b' "$theme_source" \
    && uses_vcs_info=1
  source_uses '^[[:space:]]*[^#].*\bzle[[:space:]]+-F\b' "$theme_source" \
    && uses_zle_fd_handler=1
  source_uses '^[[:space:]]*[^#].*(add-zsh-hook|precmd_functions|preexec_functions)' "$theme_source" \
    && uses_zsh_hooks=1
  direct_git_calls=$(print -r -- "$theme_source" | count_direct_git_calls)

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(command date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "$omz_commit" "$theme_name" "$last_commit_at" "$commit_sha" \
    "$uses_git_prompt_info" "$uses_parse_git_dirty" "$uses_vcs_info" \
    "$direct_git_calls" "$uses_zle_fd_handler" "$uses_zsh_hooks" "$commit_subject" \
    >> "$output"

  (( collected += 1 ))
  printf '%03d/%03d %s %s git_prompt=%s direct_git=%s\n' \
    "$collected" "$pending" "$theme_name" "${last_commit_at[1,10]}" \
    "$uses_git_prompt_info" "$direct_git_calls"
done

print -r -- "done=$total collected=$collected cached=$cached"
print -r -- "output=$output"
