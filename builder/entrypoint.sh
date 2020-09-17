#!/bin/bash

set -euo pipefail

. /usr/local/lib/color-logger.bash
export COLOR_INFO=$COLOR_BLUE

built_configs_path=${BUILT_CONFIGS_PATH-/built_configs}
final_configs_path=${FINAL_CONFIGS_PATH-/final_configs}
configs_repo_branch=${CONFIGS_REPO_BRANCH-master}
configs_repo_path=${CONFIGS_REPO_PATH-/configs_repo}
config_yaml_path=${CONFIG_YAML_PATH-/yamls/config/config.yaml}
secrets_yaml_path=${SECRETS_YAML_PATH-/yamls/secrets/secrets.yaml}

configs_need_building=false
configs_repo_git_path="$configs_repo_path/.git"
existing_config_yaml_checksum_path="$final_configs_path/.configs.yaml.sha256sum"
existing_secrets_yaml_checksum_path="$final_configs_path/.secrets.yaml.sha256sum"
new_config_yaml_checksum_path="$built_configs_path/.configs.yaml.sha256sum"
new_secrets_yaml_checksum_path="$built_configs_path/.secrets.yaml.sha256sum"

clone_repo () {
  info 'cloning configs repo'

  git clone "$CONFIGS_REPO_URL" --depth 1 --single-branch --branch "$configs_repo_branch" "$configs_repo_path"
}

pull_configs () {
  info 'pulling latest changes'

  git --git-dir="$configs_repo_git_path" fetch

  if [ "$(_get_configs_git_sha HEAD)" != "$(_get_configs_git_sha "$configs_repo_branch@{upstream}")" ]; then
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

yamls_changed () {
  local changed=false

  _create_yaml_checksums

  if _config_yaml_updated; then
    changed=true
  fi

  if _secrets_yaml_updated; then
    changed=true
  fi

  if [ "$changed" = true ]; then
    return 0
  fi

  return 1
}

setup () {
  mkdir -p "$built_configs_path"
}

_create_yaml_checksums () {
  info 'creating checksums for yamls'

  _checksum "$config_yaml_path" > "$new_config_yaml_checksum_path"
  _checksum "$secrets_yaml_path" > "$new_secrets_yaml_checksum_path"
}

_checksum () {
  sha256sum "$1" | awk '{print $1}'
}

_get_configs_git_sha () {
  git --git-dir="$configs_repo_git_path" rev-parse "$1"
}

_config_yaml_updated () {
  if [ ! -f "$new_config_yaml_checksum_path" ]; then
    error "'$new_config_yaml_checksum_path' must exist prior to calling 'config_yaml_updated'"
    exit 1
  fi

  if [ "$(cat "$new_config_yaml_checksum_path")" != "$(cat "$existing_config_yaml_checksum_path" 2>/dev/null || echo '')" ]; then
    info 'config.yaml changed'
    return 0
  fi

  return 1
}

_secrets_yaml_updated () {
  if [ ! -f "$new_secrets_yaml_checksum_path" ]; then
    error "'$new_secrets_yaml_checksum_path' must exist prior to calling 'secrets_yaml_updated'"
    exit 1
  fi

  if [ "$(cat "$new_secrets_yaml_checksum_path")" != "$(cat "$existing_secrets_yaml_checksum_path" 2>/dev/null || echo '')" ]; then
    info 'secrets.yaml changed'
    return 0
  fi

  return 1
}

################################################################################

if [ -z ${CONFIGS_REPO_URL+x} ]; then
  error ''\''CONFIGS_REPO_URL'\'' environment variable required'
  exit 1
fi

setup

if [ ! -d "$configs_repo_path"/.git ]; then
  clone_repo
  configs_need_building=true
else
  if pull_configs; then
    configs_need_building=true
  fi
fi

if yamls_changed; then
  configs_need_building=true
fi

if [ "$configs_need_building" = true ]; then
  build_configs
  copy_configs
  success 'done'
else
  warn 'no need to build configs'
fi
