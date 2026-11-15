# Action Button prototype check

## Device

- iPhone 16 Pro (iPhone17,1), iOS 27.2 (build 24B119), Developer Mode enabled.
- Xcode 26.6 is installed; command line builds require `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Prototype so far

- SwiftUI app with a Shortcuts App Intent conforming to `AudioRecordingIntent`.
- Background audio capture with `AVAudioRecorder`, a 5-minute stop, and an ActivityKit Live Activity / widget extension.
- iOS Simulator build succeeded.
- No install or Action Button behavior has been tested on the iPhone yet.
- Screenshot of the lock-screen failure is saved as `shots/action-button-session-activation-failed.jpeg`.

## Failure seen on the phone

- The Action Button shortcut notification reports `Session activation failed` on both presses.
- Source inspection found the prototype activated `AVAudioSession` before checking/requesting microphone permission. The order is corrected in source to request microphone permission first, then configure and activate the session.
- The corrected source builds for the simulator. The corrected build has not been installed on the phone because Xcode still has no development provisioning profiles and no signed-in team account.
- The permission-order change did not resolve the phone error. Sol assessed a possible interaction between the system handling of `AudioRecordingIntent` and app-side `AVAudioSession.setActive(true)`; this remains a hypothesis because the failing phone build does not include diagnostic logging.
- The Action Button command now uses a regular background `AppIntent`, with explicit logging around `perform()` and session activation. The simulator test invokes the intent twice: recording starts, the session activates, the recorder starts, and the second call stops it; 1 test passed.
- The simulator cannot emulate the physical Action Button. The iPhone result for this revised intent remains unverified until the new build is installed.
- The recording screen now displays the app version and build number; simulator screenshot verified `0.1.0 (build 2)`.

## Blocker

Device signing cannot proceed because Xcode has no signed-in Apple developer account and no provisioning profiles for the app or extension bundle identifiers. Automatic signing with the team ID currently present in the local signing certificate fails with `No Account for Team`.

## Advice from Sol

- A successful simulator build does not establish that Action Button launches the intent or that microphone capture continues while locked.
- The singleton's in-memory recording state could be lost if the process is relaunched between the start and stop presses. Check persistent/system recording state before treating the toggle as reliable.
- Minimum next check after signing is configured: install on the phone, assign the App Shortcut to Action Button, pre-grant microphone permission, lock the phone, then test start, visible recording state, file creation, and second-press stop.
- No system prohibition was identified from the supplied evidence; lock-screen intent launch, microphone access, and process lifetime remain device questions.

## Next action

Sign the app and extension with an Apple account configured in Xcode, install on the connected phone, and run the locked-screen test matrix. Do not mark Task 1 complete until the two-press flow creates one playable recording without unlocking.
