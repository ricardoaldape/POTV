#!/usr/bin/env python3
"""Configure Flutter Android Gradle files for release signing.

Follows https://docs.flutter.dev/deployment/android#signing-the-app
"""

from __future__ import annotations

from pathlib import Path


KTS_IMPORTS = """import java.util.Properties
import java.io.FileInputStream

"""

KTS_LOADER = """
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

"""

KTS_SIGNING = """    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

"""

GROOVY_LOADER = """
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

"""

GROOVY_SIGNING = """    signingConfigs {
        release {
            keyAlias = keystoreProperties['keyAlias']
            keyPassword = keystoreProperties['keyPassword']
            storeFile = keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword = keystoreProperties['storePassword']
        }
    }

"""


def closing_brace(text: str, open_index: int) -> int:
    depth = 0
    for i in range(open_index, len(text)):
        if text[i] == '{':
            depth += 1
        elif text[i] == '}':
            depth -= 1
            if depth == 0:
                return i
    raise SystemExit('Unbalanced braces in Gradle file')


def insert_after_plugins(text: str, snippet: str) -> str:
    if 'keystoreProperties' in text:
        return text
    marker = 'plugins {'
    start = text.find(marker)
    if start == -1:
        raise SystemExit('plugins { block not found')
    end = closing_brace(text, start + len(marker) - 1)
    return text[: end + 1] + '\n' + snippet + text[end + 1 :]


def ensure_signing_block(text: str, snippet: str) -> str:
    if 'signingConfigs' in text and 'create("release")' in text:
        return text
    if 'signingConfigs' in text and 'release {' in text:
        return text
    needle = '    buildTypes {'
    if needle not in text:
        raise SystemExit('buildTypes { block not found')
    return text.replace(needle, snippet + needle, 1)


def patch_kts(text: str) -> str:
    if 'import java.util.Properties' not in text:
        text = KTS_IMPORTS + text
    text = insert_after_plugins(text, KTS_LOADER)
    text = ensure_signing_block(text, KTS_SIGNING)
    text = text.replace(
        'signingConfig = signingConfigs.getByName("debug")',
        'signingConfig = signingConfigs.getByName("release")',
    )
    return text


def patch_groovy(text: str) -> str:
    if 'import java.util.Properties' not in text and 'new Properties()' not in text:
        text = 'import java.util.Properties\nimport java.io.FileInputStream\n\n' + text
    if 'keystoreProperties' not in text:
        if 'def flutterRoot' in text or 'android {' in text:
            android = text.find('android {')
            if android == -1:
                raise SystemExit('android { block not found')
            text = text[:android] + GROOVY_LOADER + text[android:]
        else:
            text = insert_after_plugins(text, GROOVY_LOADER)
    text = ensure_signing_block(text, GROOVY_SIGNING)
    text = text.replace(
        'signingConfig signingConfigs.debug',
        'signingConfig signingConfigs.release',
    )
    text = text.replace(
        'signingConfig = signingConfigs.debug',
        'signingConfig = signingConfigs.release',
    )
    return text


def main() -> None:
    app = Path('android/app')
    kts = app / 'build.gradle.kts'
    groovy = app / 'build.gradle'
    if kts.exists():
        kts.write_text(patch_kts(kts.read_text(encoding='utf-8')), encoding='utf-8')
        print(f'Configured release signing in {kts}')
        return
    if groovy.exists():
        groovy.write_text(patch_groovy(groovy.read_text(encoding='utf-8')), encoding='utf-8')
        print(f'Configured release signing in {groovy}')
        return
    raise SystemExit('android/app/build.gradle(.kts) not found')


if __name__ == '__main__':
    main()
