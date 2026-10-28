#!/bin/bash
# Сборка игры: Android APK (release) и Windows (debug, с консольным exe для логов).
# Запуск из любой папки: tools/export.sh   (Godot не в PATH — GODOT=/путь/к/godot tools/export.sh)
#
# Подпись — debug-ключом проекта tools/debug.keystore: у всех сборок один ключ, и новая
# ставится поверх старой без удаления игры. Это ключ для тестов, секрета в нём нет.
# Для Google Play нужен отдельный release-ключ, и в репозиторий его класть НЕЛЬЗЯ.
set -e
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
KEYSTORE="$PWD/tools/debug.keystore"
for KIND in DEBUG RELEASE; do
	export GODOT_ANDROID_KEYSTORE_${KIND}_PATH="$KEYSTORE"
	export GODOT_ANDROID_KEYSTORE_${KIND}_USER=androiddebugkey
	export GODOT_ANDROID_KEYSTORE_${KIND}_PASSWORD=android
done
mkdir -p export/android export/windows
"$GODOT" --headless --path . --export-release Android export/android/Rankborn.apk
"$GODOT" --headless --path . --export-debug "Windows Desktop" export/windows/Rankborn.exe
rm -f export/android/*.idsig
echo "Готово: export/android/Rankborn.apk, export/windows/ (Rankborn.exe + Rankborn.pck)"
