#!/usr/bin/env bash

set -e

MITKERBEROS_VERSION_STABLE="1.22.1_openssl-3.5.4" # https://kerberos.org/dist/

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

if [[ "${MITKERBEROS_VERSION}" =~ ^([^_]+)_openssl-(.*)$ ]]; then
  MITKERBEROS_VERSION="${BASH_REMATCH[1]}"
  OPENSSL_VERSION="${BASH_REMATCH[2]}"
  echo "MITKERBEROS_VERSION extracted: ${MITKERBEROS_VERSION}"
  echo "OPENSSL_VERSION extracted: ${OPENSSL_VERSION}"
else
  echo "Cannot parse MITKERBEROS_VERSION: ${MITKERBEROS_VERSION}"
  exit 1
fi

if [[ -z $MITKERBEROS_VERSION_SHORT ]]; then
  if [[ "${MITKERBEROS_VERSION}" =~ ^([0-9]+\.[0-9]+)\.[0-9]+$ ]]; then
    MITKERBEROS_VERSION_SHORT="${BASH_REMATCH[1]}"
  else
    MITKERBEROS_VERSION_SHORT="${MITKERBEROS_VERSION}"
  fi

  echo "MITKERBEROS_VERSION_SHORT not set; falling back to ${MITKERBEROS_VERSION_SHORT} (Stable)"
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

TARGET_DIR="${BUILD_ROOT_DIR}/mitkerberos-${MITKERBEROS_VERSION}_openssl-${OPENSSL_VERSION}"

if [[ -d "${TARGET_DIR}" ]]; then
  rm -rf "${TARGET_DIR}"
fi

mkdir "${TARGET_DIR}"

SRC_DIR="${BUILD_DIR}/src"

echo "Initializing git"
git init "${BUILD_DIR}"

echo "Adding all files to git"
git -C "${BUILD_DIR}" add .

echo "Committing initial state to git"
git -C "${BUILD_DIR}" commit -m "Initial"

NO_URI_LOOKUP_PATCH_FILENAME="no_uri_lookup.patch"

echo "Applying ${NO_URI_LOOKUP_PATCH_FILENAME} patch to git"
git -C "${BUILD_DIR}" apply "${SCRIPT_PATH}/${NO_URI_LOOKUP_PATCH_FILENAME}"

OPENSSL_BASE_DIR="${BUILD_ROOT_DIR}/openssl-${OPENSSL_VERSION}"

if [[ -d "${OPENSSL_BASE_DIR}" ]]; then
  rm -rf "${OPENSSL_BASE_DIR}"
fi

mkdir "${OPENSSL_BASE_DIR}"

OPENSSL_URL="https://github.com/royalapplications/openssl/releases/download/${OPENSSL_VERSION}/openssl.tar.gz"

OPENSSL_DL_FILENAME="openssl-${OPENSSL_VERSION}.tar.gz"

echo "Downloading OpenSSL release from ${OPENSSL_URL}"
curl -fL "${OPENSSL_URL}" -o "${BUILD_ROOT_DIR}/${OPENSSL_DL_FILENAME}"

echo "Extracting OpenSSL"
tar -xvf "${BUILD_ROOT_DIR}/${OPENSSL_DL_FILENAME}" --directory "${OPENSSL_BASE_DIR}"

build() {
  local os="$1"
  local arch="$2"
  local build_target_dir="$3"

  if [[ -d "${build_target_dir}" ]]; then
    rm -rf "${build_target_dir}"
  fi

  mkdir "${build_target_dir}"

  cd "${build_target_dir}"

  local install_dir="${build_target_dir}/bin"

  local cflags="-DDEFAULT_RDNS_LOOKUP=0"
  local ldflags=""
  local target=""

  local os_name=""

  local openssl_lib_dir="${OPENSSL_BASE_DIR}/${os}/lib"
  local openssl_include_dir="${OPENSSL_BASE_DIR}/${os}/include"

  if [ "$os" = "macosx" ]; then
    os_name="macOS"
    local sdk_root=$(xcrun --sdk macosx --show-sdk-path)

    target="${arch}-apple-darwin"

    cflags="${cflags} -isysroot ${sdk_root} -mmacosx-version-min=${MACOS_VERSION_MIN} -target ${target} -I ${openssl_include_dir}"
    ldflags="-framework Kerberos -isysroot ${sdk_root} -mmacosx-version-min=${MACOS_VERSION_MIN} -L ${openssl_lib_dir}"
  elif [ "$os" = "iphoneos" ]; then
    os_name="iOS"
    local sdk_root=$(xcrun --sdk iphoneos --show-sdk-path)

    target="${arch}-apple-ios"

    # Manually set the correct values for configure checks that MIT Kerberos won't be able to perform because we're cross-compiling.
    export krb5_cv_attr_constructor_destructor=yes
    export ac_cv_func_regcomp=yes
    export ac_cv_printf_positional=yes

    cflags="${cflags} -isysroot ${sdk_root} -miphoneos-version-min=${IOS_VERSION_MIN} -target ${target} -I ${openssl_include_dir}"
    ldflags="${ldflags} -isysroot ${sdk_root} -miphoneos-version-min=${IOS_VERSION_MIN} -L ${openssl_lib_dir}"
  elif [ "$os" = "iphonesimulator" ]; then
    os_name="iOS Simulator"
    local sdk_root=$(xcrun --sdk iphonesimulator --show-sdk-path)

    target="${arch}-apple-ios-simulator"

    # Manually set the correct values for configure checks that MIT Kerberos won't be able to perform because we're cross-compiling.
    export krb5_cv_attr_constructor_destructor=yes
    export ac_cv_func_regcomp=yes
    export ac_cv_printf_positional=yes

    cflags="${cflags} -isysroot ${sdk_root} -miphoneos-version-min=${IOS_VERSION_MIN} -target ${target} -I ${openssl_include_dir}"
    ldflags="${ldflags} -isysroot ${sdk_root} -miphoneos-version-min=${IOS_VERSION_MIN} -L ${openssl_lib_dir}"
  fi

  # MIT Kerberos cannot be built statically directly as there's a duplicate symbols in dbutil and so, we have to first build dynamically, then statically.

  echo "Configuring MIT Kerberos for ${os_name} ${arch}, dynamic"
  "${SRC_DIR}/configure" \
    CC=clang \
    LDFLAGS="${ldflags}" \
    CFLAGS="${cflags}" \
    --host=${target} \
    --without-system-verto \
    --with-crypto-impl=openssl \
    --prefix "${install_dir}"

  echo "Making MIT Kerberos for ${os_name} ${arch}, dynamic"
  make

  echo "Configuring MIT Kerberos for ${os_name} ${arch}, static"
  "${SRC_DIR}/configure" \
    CC=clang \
    LDFLAGS="${ldflags}" \
    CFLAGS="${cflags}" \
    --host=${target} \
    --without-system-verto \
    --with-crypto-impl=openssl \
    --enable-static \
    --disable-shared \
    --prefix "${install_dir}"

  echo "Making MIT Kerberos for ${os_name} ${arch}, static"
  make

  echo "Making MIT Kerberos for ${os_name} ${arch}, install"
  make install
}

TARGET_DIR_MACOS_ARM64="${TARGET_DIR}/macosx-arm64"
TARGET_DIR_MACOS_X86="${TARGET_DIR}/macosx-x86_64"
TARGET_DIR_IOS_ARM64="${TARGET_DIR}/iphoneos"
TARGET_DIR_IOS_SIMULATOR_ARM64="${TARGET_DIR}/iphonesimulator-arm64"
TARGET_DIR_IOS_SIMULATOR_X86="${TARGET_DIR}/iphonesimulator-x86_64"

build "macosx" "aarch64" "${TARGET_DIR_MACOS_ARM64}"
build "macosx" "x86_64" "${TARGET_DIR_MACOS_X86}"

# TODO: iOS
# build "iphoneos" "aarch64" "${TARGET_DIR_IOS_ARM64}"
# build "iphonesimulator" "aarch64" "${TARGET_DIR_IOS_SIMULATOR_ARM64}"
# build "iphonesimulator" "x86_64" "${TARGET_DIR_IOS_SIMULATOR_X86}"

TARGET_DIR_MACOS_UNIVERSAL="${TARGET_DIR}/macosx"
# TARGET_DIR_IOS_SIMULATOR_UNIVERSAL="${TARGET_DIR}/iphonesimulator"

make_universal_lib() {
  local file_name="$1"
  local target_dir="$2"
  local source_dir_1="$3"
  local source_dir_2="$4"

  echo "Making universal binary at ${target_dir}/${file_name} out of ${source_dir_1}/${file_name} and ${source_dir_2}/${file_name}"

  lipo -create \
    "${source_dir_1}/${file_name}" \
    "${source_dir_2}/${file_name}" \
    -output "${target_dir}/${file_name}"
}

make_universal_libs() {
  local target_dir="$1"
  local source_dir_1="$2"
  local source_dir_2="$3"

  local lib_names=(\
    "libcom_err.a" \
    "libgssapi_krb5.a" \
    "libgssrpc.a" \
    "libk5crypto.a" \
    "libkadm5clnt_mit.a" \
    "libkadm5srv_mit.a" \
    "libkdb5.a" \
    "libkrad.a" \
    "libkrb5_db2.a" \
    "libkrb5_k5tls.a" \
    "libkrb5_otp.a" \
    "libkrb5_pkinit.a" \
    "libkrb5_spake.a" \
    "libkrb5_test.a" \
    "libkrb5.a" \
    "libkrb5support.a" \
    "libverto.a" \
  )

  if [[ -d "${target_dir}" ]]; then
    rm -rf "${target_dir}"
  fi

  mkdir -p "${target_dir}"

  for lib_name in ${lib_names[@]}; do
    make_universal_lib \
      "${lib_name}" \
      "${target_dir}" \
      "${source_dir_1}" \
      "${source_dir_2}"
  done
}

merge_static_libs() {
  local target_dir="$1"
  local output_file="$2"

  xcrun libtool -static \
    "${target_dir}/libkrb5.a" \
    "${target_dir}/libkrb5support.a" \
    "${target_dir}/libk5crypto.a" \
    -o "${output_file}"
}

echo "Making universal libs for macOS"
make_universal_libs \
    "${TARGET_DIR_MACOS_UNIVERSAL}/lib" \
    "${TARGET_DIR_MACOS_ARM64}/bin/lib" \
    "${TARGET_DIR_MACOS_X86}/bin/lib"

merge_static_libs \
  "${TARGET_DIR_MACOS_UNIVERSAL}/lib" \
  "${TARGET_DIR_MACOS_UNIVERSAL}/lib/libMITKerberos.a"

echo "Copying headers for macOS"
cp -r \
  "${TARGET_DIR_MACOS_ARM64}/bin/include" \
  "${TARGET_DIR_MACOS_UNIVERSAL}/include"

echo "Creating macOS-Universal XCFramework at ${TARGET_DIR}/MITKerberos.xcframework"

if [[ -d "${TARGET_DIR}/MITKerberos.xcframework" ]]; then
  rm -rf "${TARGET_DIR}/MITKerberos.xcframework"
fi

xcodebuild -create-xcframework \
  -library "${TARGET_DIR_MACOS_UNIVERSAL}/lib/libMITKerberos.a" \
  -output "${TARGET_DIR}/MITKerberos.xcframework"

echo "Codesigning XCFramework"

codesign \
    --force --deep --strict \
    --sign "${CODESIGN_ID}" \
    "${TARGET_DIR}/MITKerberos.xcframework"
