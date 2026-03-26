#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/sg-common.sh"

sg_warn_unregistered "$@"
