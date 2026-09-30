#!/usr/bin/env bash
set -euo pipefail

: "${API_BASE_URL:?Set API_BASE_URL to the deployed Render API URL before building.}"

FLUTTER_VERSION="3.44.9"
FLUTTER_ROOT="${FLUTTER_ROOT:-${HOME}/flutter}"
FLUTTER_ARCHIVE="/tmp/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"

if [[ ! -x "${FLUTTER_ROOT}/bin/flutter" ]]; then
  curl --fail --location --retry 3 \
    "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    --output "${FLUTTER_ARCHIVE}"
  tar -xf "${FLUTTER_ARCHIVE}" -C "${HOME}"
fi

export PATH="${FLUTTER_ROOT}/bin:${PATH}"
cd frontend
flutter --version
flutter pub get
flutter build web --release --dart-define="API_BASE_URL=${API_BASE_URL%/}"
