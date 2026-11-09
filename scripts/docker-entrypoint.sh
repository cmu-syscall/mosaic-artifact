#!/usr/bin/env bash
set -e
source /mosaic-artifact/scripts/mosaic_env_var.sh "${MOSAIC_LIBRARIES:-tblis,mkl}"
exec "$@"
