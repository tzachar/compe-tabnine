#!/usr/bin/env bash

# Based on https://github.com/codota/TabNine/blob/master/dl_binaries.sh
# Download latest TabNine binaries
set -o errexit
set -o pipefail
set -x

version=${version:-$(curl -sS https://update.tabnine.com/bundles/version)}

case $(uname -s) in
"Darwin")
    if [ "$(uname -m)" == "arm64" ]; then
        platform="aarch64-apple-darwin"
    else
        platform="$(uname -m)-apple-darwin"
    fi
    ;;
"Linux")
    platform="$(uname -m)-unknown-linux-musl"
    ;;
esac

# we want the binary to reside inside our plugin's dir
cd $(dirname $0)
path=$version/$platform

curl https://update.tabnine.com/bundles/${path}/TabNine.zip --create-dirs -o binaries/${path}/TabNine.zip
unzip -o binaries/${path}/TabNine.zip -d binaries/${path}
rm -rf binaries/${path}/TabNine.zip
chmod +x binaries/$path/*

target="binaries/TabNine_$(uname -s)"
rm $target || true # remove old link
ln -sf $path/TabNine $target
