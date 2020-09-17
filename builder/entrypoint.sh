#!/bin/bash

set -euo pipefail

. /usr/local/lib/color-logger.bash
export COLOR_INFO=$COLOR_BLUE

build_configs=false

built_configs_path=${BUILT_CONFIGS_PATH-/built_configs}
final_configs_path=${FINAL_CONFIGS_PATH-/final_configs}
configs_repo_branch=${CONFIGS_REPO_BRANCH-master}
configs_repo_path=${CONFIGS_REPO_PATH-/configs_repo}
configs_repo_git_path="$configs_repo_path/.git"
config_yaml_path=${CONFIG_YAML_PATH-/yamls/config/config.yaml}
secrets_yaml_path=${SECRETS_YAML_PATH-/yamls/secrets/secrets.yaml}

clone_repo () {
  info 'cloning configs repo'

  git clone "$CONFIGS_REPO_URL" --depth 1 --single-branch --branch "$configs_repo_branch" "$configs_repo_path"
}

get_configs_git_sha () {
  git --git-dir="$configs_repo_git_path" rev-parse "$1"
}

pull_configs () {
  info 'pulling latest changes'

  git --git-dir="$configs_repo_git_path" fetch

  if [ "$(get_configs_git_sha HEAD)" != "$(get_configs_git_sha "$configs_repo_branch@{upstream}")" ]; then
    git --git-dir="$configs_repo_git_path" pull

    return 0
  fi

  return 1
}

build_configs () {
  info 'building configs'

  gomplate --input-dir="/$configs_repo_path/configs" \
           --output-map="/$built_configs_path/{{ .in | strings.ReplaceAll \".tmpl\" \" \" }}" \
           --exclude='*.yaml' \
           --exclude='.gitignore' \
           --datasource="configs=$config_yaml_path" \
           --datasource="secrets=$secrets_yaml_path"

  # openhab seems a little happier (in its logs at least) when all of these dirs exist
  local default_conf_dirs=(html icons items persistence rules scripts services sitemaps sounds things transform)

  for d in "${default_conf_dirs[@]}"; do
    mkdir -p "$built_configs_path/$d"
  done
}

copy_configs () {
  info 'copying built configs to final destination'

  # ensure src dir has trailing slash so we only copy its contents
  [[ "${built_configs_path}" != */ ]] && src="${built_configs_path}/"

  rsync --verbose --checksum --recursive --delete "$src" "$final_configs_path"
}

if [ -z ${CONFIGS_REPO_URL+x} ]; then
  error ''\''CONFIGS_REPO_URL'\'' environment variable required'
  exit 1
fi

if [ ! -d "$configs_repo_path"/.git ]; then
  clone_repo
  build_configs=true
else
  if pull_configs; then
    build_configs=true
  fi
fi

if [ "$build_configs" = true ]; then
  build_configs
  copy_configs
  success 'done'
else
  warn 'no need to build configs'
fi
