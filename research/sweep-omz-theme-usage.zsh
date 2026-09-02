#!/usr/bin/env zsh

builtin emulate -L zsh -o no_aliases -o err_return -o pipe_fail -o extended_glob

usage() {
  print -r -- 'usage: sweep-omz-theme-usage.zsh [--omz DIR] [--output FILE] [--delay SECONDS] [--limit N]'
  print -r -- ''
  print -r -- 'Queries GitHub REST code search once per bundled Oh My Zsh theme.'
  print -r -- 'Existing rows in the output TSV are resumed automatically.'
}

fail() {
  print -u2 -r -- "error: $*"
  return 1
}

local script_dir=${0:A:h}
local omz_dir=${ZSH:-${HOME}/.oh-my-zsh}
local snapshot_date
snapshot_date=$(command date -u +%F)
local output="$script_dir/omz-theme-usage-${snapshot_date}.tsv"
local delay=6.5
local limit=0
local gh_bin=${GH_BIN:-/home/linuxbrew/.linuxbrew/bin/gh}

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
    --delay)
      (( $# >= 2 )) || fail '--delay requires seconds'
      delay=$2
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

[[ $delay =~ '^[0-9]+([.][0-9]+)?$' ]] || fail '--delay must be a non-negative number'
[[ $limit == <-> ]] || fail '--limit must be a non-negative integer'

if [[ ! -x $gh_bin ]]; then
  gh_bin=${commands[gh]:-}
fi
[[ -n $gh_bin && -x $gh_bin ]] || fail 'GitHub CLI not found; set GH_BIN to its path'
"$gh_bin" auth status --hostname github.com >/dev/null 2>&1 || fail 'GitHub CLI is not authenticated'

omz_dir=${omz_dir:A}
output=${output:A}
[[ -d $omz_dir/themes ]] || fail "theme directory not found: $omz_dir/themes"

local omz_commit
omz_commit=$(command git -C "$omz_dir" rev-parse HEAD 2>/dev/null) \
  || fail "not a Git checkout: $omz_dir"

local -a theme_paths theme_names
local theme_path theme_name
theme_paths=("$omz_dir"/themes/*.zsh-theme(N))
(( ${#theme_paths} )) || fail "no .zsh-theme files found in $omz_dir/themes"

for theme_path in $theme_paths; do
  theme_name=${${theme_path:t}%.zsh-theme}
  theme_names+=("$theme_name")
done

if (( limit > 0 && limit < ${#theme_names} )); then
  theme_names=("${theme_names[@]:0:$limit}")
fi

command mkdir -p "$output:h"

local header=$'snapshot_at_utc\tomz_commit\tmetric\ttarget\tcount\tincomplete_results\tquery'
if [[ -e $output ]]; then
  local existing_header
  IFS= read -r existing_header < "$output"
  [[ $existing_header == $header ]] || fail "unexpected TSV header: $output"
else
  print -r -- "$header" > "$output"
fi

local -A completed
local row_time row_commit row_metric row_target row_count row_incomplete row_query
while IFS=$'\t' read -r row_time row_commit row_metric row_target row_count row_incomplete row_query; do
  [[ $row_time == snapshot_at_utc ]] && continue
  [[ $row_commit == $omz_commit ]] \
    || fail "output contains a different OMZ commit: $row_commit"
  completed[$row_target]=1
done < "$output"

local total=${#theme_names}
local cached=0
for theme_name in $theme_names; do
  (( ${+completed[$theme_name]} )) && (( cached += 1 ))
done
local pending=$(( total - cached ))

print -r -- "themes=$total cached=$cached pending=$pending"
print -r -- "output=$output"

local queried=0
local requests=0
local query result count incomplete first_error
local rate_data rate_remaining rate_reset wait_seconds now_epoch

for theme_name in $theme_names; do
  (( ${+completed[$theme_name]} )) && continue

  if (( requests > 0 )) && [[ $delay != 0 && $delay != 0.0 ]]; then
    command sleep "$delay"
  fi

  rate_data=$("$gh_bin" api rate_limit \
    --jq '[.resources.code_search.remaining, .resources.code_search.reset] | @tsv') \
    || fail 'could not read GitHub code-search rate limit'
  rate_remaining=${rate_data%%$'\t'*}
  rate_reset=${rate_data#*$'\t'}

  if (( rate_remaining == 0 )); then
    now_epoch=$(command date +%s)
    wait_seconds=$(( rate_reset - now_epoch + 1 ))
    (( wait_seconds < 1 )) && wait_seconds=1
    print -r -- "wait=${wait_seconds}s rate-limit"
    command sleep "$wait_seconds"
  fi

  query="\"ZSH_THEME=\\\"${theme_name}\\\"\""
  if ! result=$("$gh_bin" api -X GET search/code \
      -f q="$query" -f per_page=1 \
      --jq '[.total_count, .incomplete_results] | @tsv' 2>&1); then
    first_error=${result%%$'\n'*}
    print -u2 -r -- "error $theme_name: $first_error"
    print -u2 -r -- "saved=$output"
    return 1
  fi
  (( requests += 1 ))

  count=${result%%$'\t'*}
  incomplete=${result#*$'\t'}
  [[ $count == <-> && ($incomplete == true || $incomplete == false) ]] \
    || fail "unexpected GitHub response for $theme_name: $result"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(command date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "$omz_commit" github_code_search_total "$theme_name" "$count" "$incomplete" "$query" \
    >> "$output"

  (( queried += 1 ))
  if [[ $incomplete == true ]]; then
    printf '%03d/%03d %s %s incomplete\n' "$queried" "$pending" "$theme_name" "$count"
  else
    printf '%03d/%03d %s %s\n' "$queried" "$pending" "$theme_name" "$count"
  fi
done

print -r -- "done=$total queried=$queried cached=$cached"
print -r -- "output=$output"
