# Android in-place update signing

Qalam Muslim keeps the Android application ID `com.ahmed.qalammuslim` and increments `versionCode` for every update. That preserves Android's package identity and application data **only when the APK is signed with the same certificate as the currently installed app**.

## Required GitHub Actions secrets

In the repository, open **Settings → Secrets and variables → Actions** and add:

- `QALAM_RELEASE_KEYSTORE_BASE64`: Base64 contents of the original release keystore (.jks or .keystore).
- `QALAM_RELEASE_STORE_PASSWORD`: keystore password.
- `QALAM_RELEASE_KEY_ALIAS`: original key alias.
- `QALAM_RELEASE_KEY_PASSWORD`: key password.

The key must be the exact key that signed the installed Qalam Muslim APK. A newly generated keystore is not a replacement for the old one. Android APKs contain the public signing certificate, not the private signing key, so the private key cannot be recovered from an APK.

The workflow now uses these secrets when they are present and records the APK signer certificate fingerprint. If the secrets are absent, it warns and builds with the temporary GitHub runner debug key for CI testing only; such an APK is **not guaranteed to install over an existing app**.

Do not change `applicationId = "com.ahmed.qalammuslim"` and do not lower the version code. Never commit `key.properties`, keystores, or passwords to the repository.
