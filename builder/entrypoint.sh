#!/bin/bash
#
# Construct configs from templates for openHAB

set -euo pipefail

# shellcheck disable=SC1091
. /usr/local/lib/color-logger.bash
export COLOR_INFO=$COLOR_BLUE # override info color

readonly built_configs_path=${BUILT_CONFIGS_PATH-/built_configs}
readonly final_configs_path=${FINAL_CONFIGS_PATH-/final_configs}
readonly configs_repo_branch=${CONFIGS_REPO_BRANCH-master}
readonly configs_repo_path=${CONFIGS_REPO_PATH-/configs_repo}
readonly config_yaml_path=${CONFIG_YAML_PATH-/yamls/config/config.yaml}
readonly secrets_yaml_path=${SECRETS_YAML_PATH-/yamls/secrets/secrets.yaml}

readonly previous_error_flag_file="$final_configs_path/.previous_error"
readonly existing_config_yaml_checksum_path="$final_configs_path/.configs.yaml.sha256sum"
readonly existing_secrets_yaml_checksum_path="$final_configs_path/.secrets.yaml.sha256sum"
readonly new_config_yaml_checksum_path="$built_configs_path/.configs.yaml.sha256sum"
readonly new_secrets_yaml_checksum_path="$built_configs_path/.secrets.yaml.sha256sum"

build_configs () {
  info 'building configs'

  gomplate --input-dir="/$configs_repo_path/configs" \
           --output-map="/$built_configs_path/{{ .in | strings.ReplaceAll \".tmpl\" \" \" }}" \
           --exclude='*.yaml' \
           --exclude='.gitignore' \
           --datasource="configs=$config_yaml_path" \
           --datasource="secrets=$secrets_yaml_path"

  # openhab seems a little happier (in its logs at least) when all of these dirs exist
  local -r default_conf_dirs=(html icons items persistence rules scripts services sitemaps sounds things transform)

  for d in "${default_conf_dirs[@]}"; do
    mkdir -p "$built_configs_path/$d"
  done
}

# https://medium.com/@dirk.avery/the-bash-trap-trap-ce6083f36700
catch () {
  if [ "$1" != "0" ]; then
    error 'creating error state file'
    touch "$previous_error_flag_file"
  fi
}

checksum () {
  sha256sum "$1" | awk '{print $1}'
}

clone_repo () {
  info 'cloning configs repo'

  git clone "$CONFIGS_REPO_URL" --depth 1 --single-branch --branch "$configs_repo_branch" "$configs_repo_path"
}

copy_configs () {
  info 'copying built configs to final destination'

  # ensure src dir has trailing slash so we only copy its contents
  [[ "${built_configs_path}" != */ ]] && src="${built_configs_path}/"

  rsync --verbose --checksum --recursive --delete "$src" "$final_configs_path"
}

create_yaml_checksums () {
  checksum "$config_yaml_path" > "$new_config_yaml_checksum_path"
  checksum "$secrets_yaml_path" > "$new_secrets_yaml_checksum_path"
}

get_configs_git_sha () {
  git -C "$configs_repo_path" rev-parse "$1"
}

has_config_yaml_changed () {
  has_yaml_changed "$new_config_yaml_checksum_path" "$existing_config_yaml_checksum_path"
}

had_previous_error () {
  if [ -f "$previous_error_flag_file" ]; then
    warn 'found previous error state'
    rm -f "$previous_error_flag_file" # will get recreated if errors again
    return 0
  fi

  return 1
}

has_secrets_yaml_changed () {
  has_yaml_changed "$new_secrets_yaml_checksum_path" "$existing_secrets_yaml_checksum_path"
}

has_yaml_changed () {
  if [ "$(cat "$1")" != "$(cat "$2")" ]; then
    return 0
  fi

  return 1
}

pull_configs () {
  local head_hash
  local upstream_hash

  info 'pulling latest changes'

  git -C "$configs_repo_path" fetch

  head_hash=$(get_configs_git_sha HEAD)
  upstream_hash=$(get_configs_git_sha "$configs_repo_branch@{upstream}")

  if [ "$head_hash" != "$upstream_hash" ]; then
    debug 'found changes'
    git -C "$configs_repo_path" pull
    return 0
  fi

  return 1
}

setup () {
  trap 'catch $?' EXIT

  mkdir -p "$built_configs_path"

  if [ ! -f "$existing_config_yaml_checksum_path" ]; then
    debug "'$existing_config_yaml_checksum_path' not found; creating it"
    touch "$existing_config_yaml_checksum_path"
  fi

  if [ ! -f "$existing_secrets_yaml_checksum_path" ]; then
    debug "'$existing_secrets_yaml_checksum_path' not found; creating it"
    touch "$existing_secrets_yaml_checksum_path"
  fi
}

yamls_changed () {
  local changed=false

  create_yaml_checksums

  if has_config_yaml_changed; then
    info "'config.yaml' has changed"
    changed=true
  fi

  if has_secrets_yaml_changed; then
    info "'secrets.yaml' has changed"
    changed=true
  fi

  if [ "$changed" = true ]; then
    return 0
  fi

  return 1
}

main () {
  local configs_need_building=false

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

  if had_previous_error; then
    configs_need_building=true
  fi

  if [ "$configs_need_building" = true ]; then
    build_configs
    copy_configs
    success 'done'
  else
    warn 'no need to build configs'
  fi
}

main "$@"
