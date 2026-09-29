# Step 1 — Flutter snapshot

Scope: Participant App and Research Admin for build step 1 (English, left-to-right, teal #0F6F6F, square-ish corners).

## What exists
- `packages/core` (`eyetracking_core`): theme, `ApiClient` (http + bearer token, `detail` to `ApiException`, 401 hook), in-memory `TokenStore`, wire models, `MessageBanner`, `PageFrame`.
- `apps/participant` (`participant_app`): sign in, invitation (also `?invitation=<token>` in the URL), home with readiness checklist, information sheet and consent (withdraw with confirmation), profile, demographics (dynamic form), download my data.
- `apps/admin` (`research_admin`): sign in, studies (admin creates), study tabs: Participants (table, detail, reveal identity with 403 message), Invitations (copy token/code), Information sheet, Demographics form editor, Members and staff accounts (admin only).
- Layering per feature: `domain` (entities, repository ports) → `application` (ChangeNotifier controllers) → `data` (ApiClient repositories) → `presentation`. `bootstrap.dart` wires real repositories; tests pass fakes through `AppDependencies`.
- Only third-party dependency: `http`. State: ChangeNotifier + ListenableBuilder + one InheritedWidget (`AppScope`).

## Run (backend on :8000; its CORS list allows web ports 8080, 5173, 3000)
- Participant: `cd apps/participant && flutter run -d chrome --web-port=8080 --dart-define=API_BASE_URL=http://localhost:8000`
- Admin: `cd apps/admin && flutter run -d chrome --web-port=5173 --dart-define=API_BASE_URL=http://localhost:8000`
- Tests: `flutter analyze` and `flutter test` in `packages/core`, `apps/participant`, `apps/admin`.

## Results (2026-09-29)
- `flutter analyze`: clean in all three.
- `flutter test`: core 24, participant 34, admin 25, all passing (consent submit gating, required demographics field, sign-in error banner, participants table readiness, 360/800/1440 px layouts, expired session).
- `flutter build web` compiles for both apps.
- Data layers checked once against a live scratch backend (login, invitation, consent, profile, demographics, export, sheet/form publish, members, identity 403 vs grant); the throwaway driver was not kept.

## Missing
- No browser click-through of the built apps against the backend; no Android build or device run; no screenshots.
- Token is memory only (page reload signs out); no password reset.
- Voice and face preference are free text until an approved set exists.
- Participants table has no search, filter, paging or export; invitations and members have no list endpoint, so only this session's invitations are shown.
- Sheet text is plain text; times are shown in UTC; no screen-reader audit.
