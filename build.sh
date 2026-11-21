#!/bin/zsh
set -e
cd "${0:A:h}"
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
sdk=${SADE_SDK_PATH:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}
compiler=/Library/Developer/CommandLineTools/usr/bin/swiftc
common=(Updates.swift Localization.swift TaskModels.swift SharedStyle.swift Companion.swift StartupSplash.swift Settings.swift Planner.swift CategoryBooks.swift)
flags=(-parse-as-library -sdk "$sdk" -target arm64-apple-macosx14.0 -module-cache-path "${SADE_MODULE_CACHE:-.module-cache}")
destination=${1:-.}
task_app="$destination/Sade.app"
canvas_app="$destination/Sade Tuval.app"
mkdir -p "$task_app/Contents/MacOS" "$canvas_app/Contents/MacOS"
cp Info.plist "$task_app/Contents/Info.plist"
cp Tuval-Info.plist "$canvas_app/Contents/Info.plist"
mkdir -p "$task_app/Contents/Resources" "$canvas_app/Contents/Resources"
cp Sade.icns "$task_app/Contents/Resources/"
cp SadeTuval.icns "$canvas_app/Contents/Resources/"
cp -R Resources/*.lproj "$task_app/Contents/Resources/"
cp -R Resources/*.lproj "$canvas_app/Contents/Resources/"
"$compiler" "${flags[@]}" "${common[@]}" Sade.swift -o "$task_app/Contents/MacOS/Sade"
"$compiler" "${flags[@]}" "${common[@]}" Workspace.swift WorkspaceCanvas.swift CanvasInspector.swift CanvasApp.swift -o "$canvas_app/Contents/MacOS/SadeTuval"
codesign --force --sign - "$task_app"
codesign --force --sign - "$canvas_app"
