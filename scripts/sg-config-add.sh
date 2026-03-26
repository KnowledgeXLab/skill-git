#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/sg-common.sh"

sg_config_add_skill "$@"
