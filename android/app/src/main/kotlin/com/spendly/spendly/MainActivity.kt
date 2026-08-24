package com.spendly.spendly

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity, not FlutterActivity — local_auth's Android
// BiometricPrompt requires a FragmentActivity host to attach to.
class MainActivity : FlutterFragmentActivity()
