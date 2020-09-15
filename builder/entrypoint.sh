#!/bin/bash

set -euo pipefail

built_configs_path=${BUILT_CONFIGS_PATH-/built_configs}
final_configs_path=${FINAL_CONFIGS_PATH-/final_configs}
configs_repo_path=${CONFIGS_REPO_PATH-/configs_repo}
configs_repo_url=${CONFIGS_REPO_URL-https://github.com/jamesgoodhouse/openhab-configs.git}
running_flag_file="$configs_repo_path/.running"

cleanup () {
  exit_code=$?

  echo
  echo 'cleaning up'
  if [ -f "$running_flag_file" ]; then
    rm -f "$running_flag_file"
  fi

  exit $exit_code
}

clone_repo () {
  echo 'cloning configs repo'
  echo ================================================================================

  git clone "$configs_repo_url" --depth 1 "$configs_repo_path"
}

pull_latest () {
  echo pulling latest changes
  echo ================================================================================

  pushd "$configs_repo_path" > /dev/null
  git pull
  popd > /dev/null
}

build_configs () {
  echo building configs
  mkdir -p "$built_configs_path/folder"
  touch "$built_configs_path/folder/file"
  # gomplate and dump to $built_configs_path

  # ensure all these folders exists
  # html
  # icons
  # items
  # persistence
  # rules
  # scripts
  # services
  # sitemaps
  # sounds
  # things
  # transform
}

copy_configs () {
  echo copying built configs to final destination
  echo ================================================================================

  pushd "$built_configs_path" > /dev/null
  rsync --verbose --checksum --recursive --delete . "$final_configs_path"
  popd > /dev/null
}

# bow out early if this is already running elsewhere (e.g., openhab init container)
if [ -f "$running_flag_file" ]; then
  echo 'already running elsewhere; exiting'
  exit 0
fi

# register the cleanup function incase of unexpected error/interuption
trap cleanup ERR INT TERM

# both cronjob and init-container for openhab run this, so this should prevent them from colliding
touch "$running_flag_file"

if [ ! -d "$configs_repo_path"/.git ]; then
  clone_repo
else
  pull_latest
fi

build_configs
copy_configs

cleanup
