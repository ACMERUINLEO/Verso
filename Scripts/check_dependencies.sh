#!/bin/sh

set -eu

PACKAGE_ROOT="Packages/VersoCore/Sources"

check_forbidden_imports() {
    module="$1"
    pattern="$2"
    path="$PACKAGE_ROOT/$module"

    if rg --line-number "^import ($pattern)$" "$path"; then
        echo "Dependency rule violation in $module"
        exit 1
    fi
}

check_forbidden_imports \
    "VersoDomain" \
    "SwiftUI|AppKit|GRDB|EventKit|WebKit|OSLog"

check_forbidden_imports \
    "VersoApplication" \
    "SwiftUI|AppKit|GRDB|EventKit|WebKit|OSLog"

check_forbidden_imports \
    "VersoSyncProtocol" \
    "SwiftUI|AppKit|UIKit|GRDB|CloudKit|EventKit|WebKit|OSLog"

check_forbidden_imports \
    "VersoBundleFormat" \
    "SwiftUI|AppKit|UIKit|GRDB|CloudKit|EventKit|WebKit|OSLog"

if rg --line-number "^import (VersoApplication|VersoPersistence|VersoFileSystem|VersoObservability)$" \
    "$PACKAGE_ROOT/VersoBundleFormat"; then
    echo "VersoBundleFormat must remain a pure format adapter"
    exit 1
fi

if rg --line-number "CloudKit|CKSyncEngine|iCloud|NAS" \
    "$PACKAGE_ROOT/VersoSyncProtocol"; then
    echo "SyncTransport must remain provider-neutral"
    exit 1
fi

echo "Dependency rules passed."
