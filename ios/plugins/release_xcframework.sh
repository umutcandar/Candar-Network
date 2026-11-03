#!/bin/bash
set -e

lib=apple_signin

# Compile Plugin
./scripts/generate_xcframework.sh release
./scripts/generate_xcframework.sh release_debug
mv ./bin/${lib}.release_debug.xcframework ./bin/${lib}.debug.xcframework


# Move to release folder

rm -rf ./bin/release
mkdir -p ./bin/release

# Move Plugin
mkdir -p ./bin/release/${lib}
mv ./bin/${lib}.{release,debug}.xcframework ./bin/release/${lib}
cp ./${lib}/${lib}.gdip ./bin/release/${lib}
cp ./LICENSE ./bin/release/${lib}

# ZIP plugin
cd ./bin/release
zip -r ${lib} ${lib}
cd ../..
