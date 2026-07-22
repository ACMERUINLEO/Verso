#!/bin/sh

set -eu

PROJECT_FILE="Verso.xcodeproj/project.pbxproj"
SUPPORTED_OBJECT_VERSION="77"

object_version="$(sed -n 's/^[[:space:]]*objectVersion = \([0-9][0-9]*\);/\1/p' "$PROJECT_FILE")"
preferred_version="$(sed -n 's/^[[:space:]]*preferredProjectObjectVersion = \([0-9][0-9]*\);/\1/p' "$PROJECT_FILE")"

if [ "$object_version" != "$SUPPORTED_OBJECT_VERSION" ]; then
    echo "Unsupported Xcode project format: objectVersion=$object_version (expected $SUPPORTED_OBJECT_VERSION)."
    echo "Keep the project compatible with the Xcode 26.5 CI floor and the stable macOS 26 development Macs."
    exit 1
fi

if [ "$preferred_version" != "$SUPPORTED_OBJECT_VERSION" ]; then
    echo "Unexpected preferred project format: $preferred_version (expected $SUPPORTED_OBJECT_VERSION)."
    exit 1
fi

echo "Xcode project format $SUPPORTED_OBJECT_VERSION is compatible with the supported toolchain floor."

for scheme in Verso VersoUnitTests; do
    scheme_file="Verso.xcodeproj/xcshareddata/xcschemes/$scheme.xcscheme"
    if [ ! -f "$scheme_file" ]; then
        echo "Missing shared scheme: $scheme_file"
        echo "Schemes required by CI and additional development Macs must not live only in xcuserdata."
        exit 1
    fi
done

echo "Required shared schemes are available to CI and other development Macs."
