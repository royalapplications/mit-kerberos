#!/usr/bin/env bash

set -e

SCRIPT_PATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
echo "Script Path: ${SCRIPT_PATH}"

if [[ -z $MITKERBEROS_VERSION ]]; then
  echo "MITKERBEROS_VERSION not set; aborting"
  exit 1
fi

BUILD_DIR="${SCRIPT_PATH}/../build/mitkerberos-${MITKERBEROS_VERSION}"
echo "Build Path: ${BUILD_DIR}"

if [[ ! -d "${BUILD_DIR}" ]]; then
  echo "Build dir not found: ${BUILD_DIR}"
  exit 1
fi

pushd "${BUILD_DIR}"

echo "Creating ${BUILD_DIR}/mitkerberos.tar.gz"
rm -f "mitkerberos.tar.gz"
tar czf "mitkerberos.tar.gz" macosx

echo "Creating ${BUILD_DIR}/MITKerberos.xcframework.tar.gz"
rm -f "MITKerberos.xcframework.tar.gz"
tar czf "MITKerberos.xcframework.tar.gz" MITKerberos.xcframework

popd