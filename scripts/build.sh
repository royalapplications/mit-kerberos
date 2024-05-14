#!/usr/bin/env bash

set -e

MITKERBEROS_VERSION_STABLE="1.21.2" # https://kerberos.org/dist/
MITKERBEROS_VERSION_SHORT_STABLE="1.21"

IOS_VERSION_MIN="13.4"
MACOS_VERSION_MIN="11.0"
CODESIGN_ID="-"

SCRIPT_PATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
echo "Script Path: ${SCRIPT_PATH}"

BUILD_ROOT_DIR="${SCRIPT_PATH}/../build"
echo "Build Path: ${BUILD_ROOT_DIR}"
mkdir -p "${BUILD_ROOT_DIR}"

if [[ -z $MITKERBEROS_VERSION ]]; then
  echo "MITKERBEROS_VERSION not set; falling back to ${MITKERBEROS_VERSION_STABLE} (Stable)"
  MITKERBEROS_VERSION="${MITKERBEROS_VERSION_STABLE}"
fi

if [[ -z $MITKERBEROS_VERSION_SHORT ]]; then
  echo "MITKERBEROS_VERSION_SHORT not set; falling back to ${MITKERBEROS_VERSION_SHORT_STABLE} (Stable)"
  MITKERBEROS_VERSION_SHORT="${MITKERBEROS_VERSION_SHORT_STABLE}"
fi

if [[ ! -f "${BUILD_ROOT_DIR}/krb5-${MITKERBEROS_VERSION}.tar.gz" ]]; then
  echo "Downloading krb5-${MITKERBEROS_VERSION}.tar.gz"
  curl -fL "https://kerberos.org/dist/krb5/${MITKERBEROS_VERSION_SHORT}/krb5-${MITKERBEROS_VERSION}.tar.gz" -o "${BUILD_ROOT_DIR}/krb5-${MITKERBEROS_VERSION}.tar.gz"
fi

BUILD_DIR="${BUILD_ROOT_DIR}/v${MITKERBEROS_VERSION}"

if [[ ! -d "${BUILD_DIR}" ]]; then
  echo "Unpacking krb5-${MITKERBEROS_VERSION}.tar.gz to ${BUILD_DIR}"

  mkdir -p "${BUILD_DIR}"
  tar xzf "${BUILD_ROOT_DIR}/krb5-${MITKERBEROS_VERSION}.tar.gz" -C "${BUILD_DIR}" --strip-components=1
fi

TARGET_DIR="${BUILD_ROOT_DIR}/mitkerberos-${MITKERBEROS_VERSION}"

if [[ -d "${TARGET_DIR}" ]]; then
  rm -rf "${TARGET_DIR}"
fi

mkdir "${TARGET_DIR}"

SRC_DIR="${BUILD_DIR}/src"

build() {
  local os="$1"
  local arch="$2"
  local build_target_dir="$3"

  if [[ -d "${build_target_dir}" ]]; then
    rm -rf "${build_target_dir}"
  fi

  mkdir "${build_target_dir}"

  cd "${build_target_dir}"

  local cflags="-DDEFAULT_RDNS_LOOKUP=0"
  local ldflags="-framework Kerberos"
  local target=""

  local os_name=""

  # TODO: OpenSSL

  if [ "$os" = "macosx" ]; then
    os_name="macOS"
    local sdk_root=$(xcrun --sdk macosx --show-sdk-path)

    # TODO
    local openssl_lib_dir="/Users/fx/dev/royalapps/freerdpkit/bin/OpenSSL/openssl-3.2.1/macosx/lib"
    local openssl_include_dir="/Users/fx/dev/royalapps/freerdpkit/bin/OpenSSL/openssl-3.2.1/macosx/include"

    cflags="${cflags} -isysroot ${sdk_root} -mmacosx-version-min=${MACOS_VERSION_MIN} -I ${openssl_include_dir}"
    ldflags="${ldflags} -isysroot ${sdk_root} -mmacosx-version-min=${MACOS_VERSION_MIN} -L ${openssl_lib_dir}"
    target="${arch}-apple-darwin"
  elif [ "$os" = "iphoneos" ]; then
    os_name="iOS"
    local sdk_root=$(xcrun --sdk iphoneos --show-sdk-path)

    cflags="${cflags} -isysroot ${sdk_root} -miphoneos-version-min=${IOS_VERSION_MIN} -target ${arch}-apple-ios"
    ldflags="${ldflags} -isysroot ${sdk_root} -miphoneos-version-min=${IOS_VERSION_MIN} -target ${arch}-apple-ios"
  elif [ "$os" = "iphonesimulator" ]; then
    os_name="iOS Simulator"
    local sdk_root=$(xcrun --sdk iphonesimulator --show-sdk-path)

    cflags="${cflags} -isysroot ${sdk_root} -miphoneos-version-min=${IOS_VERSION_MIN} -target ${arch}-apple-ios-simulator"
    ldflags="${ldflags} -isysroot ${sdk_root} -miphoneos-version-min=${IOS_VERSION_MIN}  -target ${arch}-apple-ios-simulator"
  fi

  # echo "Cleaning"
  # make clean -C "${SRC_DIR}"

  echo "Configuring MIT Kerberos for ${os_name} ${arch}"
  "${SRC_DIR}/configure" \
    CC=clang \
    LDFLAGS="${ldflags}" \
    CFLAGS="${cflags}" \
    --host=${target} \
    --without-system-verto \
    --with-crypto-impl=openssl \
    --enable-static \
    --disable-shared

  echo "Making MIT Kerberos for ${os_name} ${arch}"
  make

  # make install -C "${BUILD_DIR}" \
  #   DESTDIR="${build_target_dir}" \
  #   PREFIX="" \
  #   ARCH="${arch}" \
  #   CFLAGS="${cflags}" \
  #   LDFLAGS="${ldflags}"

  # echo "Removing all dylibs"
  # find "${build_target_dir}/lib" -iname '*.dylib' -delete

  # echo "Removing pkgconfig dir"
  # rm -fr "${build_target_dir}/lib/pkgconfig"
}

# make_universal_lib() {
#   local file_name="$1"
#   local target_dir="$2"
#   local source_dir_1="$3"
#   local source_dir_2="$4"

#   if [[ -d "${target_dir}" ]]; then
#     rm -rf "${target_dir}"
#   fi

#   mkdir -p "${target_dir}"

#   echo "Making universal binary at ${target_dir}/${file_name} out of ${source_dir_1}/${file_name} and ${source_dir_2}/${file_name}"

#   lipo -create \
#     "${source_dir_1}/${file_name}" \
#     "${source_dir_2}/${file_name}" \
#     -output "${target_dir}/${file_name}"
# }

TARGET_DIR_MACOS_ARM64="${TARGET_DIR}/macosx-arm64"
TARGET_DIR_MACOS_X86="${TARGET_DIR}/macosx-x86_64"
# TARGET_DIR_IOS_ARM64="${TARGET_DIR}/iphoneos"
# TARGET_DIR_IOS_SIMULATOR_ARM64="${TARGET_DIR}/iphonesimulator-arm64"
# TARGET_DIR_IOS_SIMULATOR_X86="${TARGET_DIR}/iphonesimulator-x86_64"

build "macosx" "aarch64" "${TARGET_DIR_MACOS_ARM64}"
# build "macosx" "x86_64" "${TARGET_DIR_MACOS_X86}"
# build "iphoneos" "aarch64" "${TARGET_DIR_IOS_ARM64}"
# build "iphonesimulator" "aarch64" "${TARGET_DIR_IOS_SIMULATOR_ARM64}"
# build "iphonesimulator" "x86_64" "${TARGET_DIR_IOS_SIMULATOR_X86}"

# TARGET_DIR_MACOS_UNIVERSAL="${TARGET_DIR}/macosx"
# TARGET_DIR_IOS_SIMULATOR_UNIVERSAL="${TARGET_DIR}/iphonesimulator"

# make_universal_lib \
#   "libmitkerberos.a" \
#   "${TARGET_DIR_MACOS_UNIVERSAL}/lib" \
#   "${TARGET_DIR_MACOS_ARM64}/lib" \
#   "${TARGET_DIR_MACOS_X86}/lib"

# cp -r \
#   "${TARGET_DIR_MACOS_ARM64}/include" \
#   "${TARGET_DIR_MACOS_UNIVERSAL}/include"

# make_universal_lib \
#   "libmitkerberos.a" \
#   "${TARGET_DIR_IOS_SIMULATOR_UNIVERSAL}/lib" \
#   "${TARGET_DIR_IOS_SIMULATOR_ARM64}/lib" \
#   "${TARGET_DIR_IOS_SIMULATOR_X86}/lib"

# cp -r \
#   "${TARGET_DIR_IOS_SIMULATOR_ARM64}/include" \
#   "${TARGET_DIR_IOS_SIMULATOR_UNIVERSAL}/include"

# echo "Creating Apple-Universal XCFramework at ${TARGET_DIR}/MITKerberos.xcframework"

# xcodebuild -create-xcframework \
#   -library "${TARGET_DIR_MACOS_UNIVERSAL}/lib/libmitkerberos.a" \
#   -library "${TARGET_DIR_IOS_ARM64}/lib/libmitkerberos.a" \
#   -library "${TARGET_DIR_IOS_SIMULATOR_UNIVERSAL}/lib/libmitkerberos.a" \
#   -output "${TARGET_DIR}/MITKerberos.xcframework"

# echo "Codesigning XCFramework"

# codesign \
#     --force --deep --strict \
#     --sign "${CODESIGN_ID}" \
#     "${TARGET_DIR}/MITKerberos.xcframework"