#!/bin/bash
set -e

lib=apple_signin

# Compile static libraries

# ARM64 Device
scons target=$1 arch=arm64
# x86_64 Simulator
scons target=$1 arch=x86_64 simulator=yes
# ARM64 Simulator
scons target=$1 arch=arm64 simulator=yes

# Creating a fat libraries for device and simulator
# lib<plugin>.<arch>-<simulator|ios>.<release|debug|release_debug>.a
lipo -create "./bin/lib$lib.x86_64-simulator.$1.a" "./bin/lib$lib.arm64-simulator.$1.a" -output "./bin/lib$lib-simulator.$1.a"

# Creating a xcframework 
xcodebuild -create-xcframework \
    -library "./bin/lib$lib.arm64-ios.$1.a" \
    -library "./bin/lib$lib-simulator.$1.a" \
    -output "./bin/$lib.$1.xcframework"
