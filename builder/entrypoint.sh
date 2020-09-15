#!/bin/bash

set -euo pipefail

build_configs=false
built_configs_path=${BUILT_CONFIGS_PATH-/built_configs}
final_configs_path=${FINAL_CONFIGS_PATH-/final_configs}
configs_repo_path=${CONFIGS_REPO_PATH-/configs_repo}
config_yaml_path=${CONFIG_YAML_PATH-/yamls/config/config.yaml}
secrets_yaml_path=${SECRETS_YAML_PATH-/yamls/secrets/secrets.yaml}

clone_repo () {
  echo cloning configs repo
  echo ================================================================================

  git clone "$CONFIGS_REPO_URL" --depth 1 "$configs_repo_path"
}

pull_latest () {
  echo pulling latest changes
  echo ================================================================================

  pushd "$configs_repo_path" > /dev/null

  git fetch

  if [ "$(git rev-parse HEAD)" != "$(git rev-parse 'master@{upstream}')" ]; then
    git pull
    build_configs=true
  fi

  popd > /dev/null
}

build_configs () {
  echo building configs
  echo ================================================================================

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
  echo copying built configs to final destination
  echo ================================================================================

  # ensure src dir has trailing slash so we only copy its contents
  [[ "${built_configs_path}" != */ ]] && src="${built_configs_path}/"

  rsync --verbose --checksum --recursive --delete "$src" "$final_configs_path"
}

if [ -z ${CONFIGS_REPO_URL+x} ]; then
  echo ''\''CONFIGS_REPO_URL'\'' environment variable required'
  exit 1
fi

if [ ! -d "$configs_repo_path"/.git ]; then
  clone_repo
  build_configs=true
else
  pull_latest
fi

if [ "$build_configs" = true ]; then
  build_configs
  copy_configs
fi
