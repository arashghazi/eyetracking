# participant_app

EyeTracking Participant App (English, left-to-right). Step 1: sign in, invitation,
information sheet and consent, profile, demographics, download my data.
Step 2: guided session (camera check, calibration, validation, baseline, summary)
on PC web; the camera is not available on other platforms yet.

```
flutter run -d chrome --web-port=8080 --dart-define=API_BASE_URL=http://localhost:8000 \
  --dart-define=GAZE_BASE_URL=http://localhost:8100
```

`GAZE_MODE=server` sends frames to `/gaze/*` on the research server instead.
