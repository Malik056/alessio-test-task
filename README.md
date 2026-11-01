# Dummy Shop

A small Flutter app built against [dummyjson.com](https://dummyjson.com):
login → paginated product list → product detail.

Test user: `emilys` / `emilyspass`

```bash
flutter pub get
flutter run

flutter test                      # 84 unit + widget tests
flutter test integration_test     # end-to-end on a device/simulator, real API
```

## Features

- **Login** (`POST /auth/login`) with inline validation, loading and error
  states. The access token is stored in the iOS Keychain / Android Keystore via
  `flutter_secure_storage`, along with the refresh token.
- **Session handling**:
  - On startup the access token's expiry (JWT `exp`) is checked locally. A valid
    token goes straight to the list with no network call. An expired one is
    refreshed (`POST /auth/refresh`), and if the refresh token is also expired
    or rejected, the user goes to login.
  - Any request that gets a 401 refreshes the token once and is retried.
    If the refresh is rejected, the tokens are cleared and the request fails
    with a "session expired" error.
    (`/products` ignores the token, so in this app this only matters for
    authenticated endpoints added later.)
  - **Logout** clears both tokens. Session changes (login, logout, refresh)
    run one at a time, so a logout during a refresh can't be undone by the
    refresh's late response.
- **Product list** (`GET /products?skip&limit`) with loading, error (with
  retry), empty, pull-to-refresh and infinite-scroll pagination (pages of 20,
  next page prefetched about 400px before the end). A failed page is retried
  automatically after 2s, then 5s. After the third failure in a row the footer
  shows the error with a **Try again** button.
- **Product detail** with an image gallery, price/discount, rating, stock and
  description.

## Architecture (MVVM)

```
lib/
├── main.dart                 composition root (wires concrete classes)
├── app.dart                  MaterialApp + DI via provider
├── core/                     ApiClient (http wrapper, refresh-on-401), ApiException, JWT expiry
├── data/
│   ├── models/               User, AuthTokens, Product, ProductPage (plain Dart, fromJson)
│   ├── services/             TokenStorage (secure), SessionManager (token lifecycle)
│   └── repositories/         AuthRepository, ProductRepository
└── ui/
    ├── startup/              StartupScreen: restores the session, then routes
    ├── login/                LoginScreen (View) + LoginViewModel
    ├── products/             ProductListScreen (View) + ProductListViewModel
    ├── product_detail/       ProductDetailScreen (View only, see below)
    └── widgets/              shared presentational widgets
```

Data flows one way: **View → ViewModel → Repository → ApiClient / TokenStorage**.

- **Views** are thin. They render view model state and forward user intents.
  Navigation and snackbars stay in the view because they need a `BuildContext`.
- **ViewModels** are `ChangeNotifier`s with no Flutter widget imports, so they
  can be unit-tested without a widget tree. Each one is scoped to its screen with
  `ChangeNotifierProvider`, so it is disposed with the screen.
- **Repositories** are the only layer that knows endpoints and JSON shapes.
- **ApiClient** maps every failure (no network, timeout, non-2xx, bad JSON) to
  an `ApiException` with a message that is safe to show. Server messages such as
  "Invalid credentials" are passed through.
- **Dependency injection** uses constructor injection everywhere. `provider`
  only exposes the repositories built in `main.dart`, so tests can swap in mocks
  or in-memory fakes.

## Key decisions

| Decision | Why |
|---|---|
| `provider` + `ChangeNotifier` | This is the MVVM approach Flutter's own architecture guide recommends. It has minimal boilerplate for a 3-screen app and no code generation. Riverpod or Bloc would also work, but they would add ceremony without adding value at this size. |
| `http` instead of `dio` | Two endpoints don't need interceptors. `http`'s `MockClient` makes the networking layer easy to test. |
| `TokenStorage` interface | Keeps platform channels out of the tests (`InMemoryTokenStorage`). The secure implementation stores both tokens as one JSON value under a single key, so a write is all-or-nothing and storage never holds half a session. It caches the tokens in memory so we don't hit the Keychain on every request. |
| Hand-written `fromJson` | Three small models. `json_serializable`/`freezed` would add a build step for little gain. |
| Status enum + fields for list state | `loading / success / empty / error` are the full-screen states. "Loading more" and "load more failed" are separate flags because they show up *on top of* a successful list, not instead of it. |
| Failed refresh keeps the list | Losing content you can already see because a refresh failed is a poor experience. The error is shown as a snackbar instead. |
| Generation counter in `ProductListViewModel` | If a pull-to-refresh replaces the list while a next-page request is in flight, the stale page is dropped instead of being appended to the fresh list (tested). |
| Next-page retry: backoff, then a button | Scrolling never retries a failed page. Otherwise, offline, every scroll event at the bottom would send a request that fails in milliseconds (tens per second). Instead the view model retries on a timer (2s, then 5s), then stops and hands control to the user with **Try again**, which loads immediately and restarts the cycle. A successful refresh, a reload, or leaving the screen cancels a pending retry. |
| No view model for the detail page | `/products` already returns every field the detail page shows, so a second request would cost a round trip and add a loading state for no benefit. If the detail page needed more data (e.g. reviews), I'd add a `ProductDetailViewModel` that calls `GET /products/{id}`. |
| Bearer token attached to requests | `/products` is public, but `ApiClient` attaches the stored token, so authenticated endpoints such as `/auth/products` work without changes. Note that `/products` ignores the token entirely (even an expired or invalid one returns 200), so in this app a 401 can only come from startup or from future authenticated endpoints. |
| `SessionManager` separate from `ApiClient` | `ApiClient` only knows an `Authenticator` interface (get a token, refresh after a 401). The refresh request uses a second `ApiClient` *without* an authenticator, so a failing refresh can never trigger another refresh. |
| Session changes run one at a time | Login, logout and refresh go through one queue in `SessionManager`. Without it, a logout during a refresh cleared storage, and then the refresh response arrived and saved a fresh token pair, so the next start logged the user back in. Now the logout runs after the refresh and storage ends up empty. A refresh queued behind a logout finds no session and makes no request. The logout button doesn't wait for the queue; it navigates immediately, and the queue still applies the logout before any later login. This is the same idea as OkHttp's synchronized `Authenticator` and dio's `QueuedInterceptor`. |
| Single shared refresh request | Concurrent callers share one in-flight refresh, and a 401 for a token that has already been replaced reuses the current token. Many backends rotate refresh tokens and invalidate the old one on use, and some revoke the whole session when an old one is reused. Against those, two parallel refreshes would log the user out by mistake. dummyjson does *not* invalidate old refresh tokens (see below), so here this only avoids redundant calls, but the client stays correct against a stricter server. |
| Offline at startup keeps the session | A failed refresh only ends the session when the server *rejects* it (401/403). On a network error, timeout or 5xx the tokens are kept and the user continues, because the products are public. The refresh is retried on the next launch. |
| 30-second expiry leeway | Tokens about to expire are treated as expired, which absorbs clock skew and request latency. |
| No app-wide "session expired" navigation | Sending the user back to login from any screen would need a stream from `SessionManager` that the root widget listens to. I left it out because `/products` never returns a 401, so it could never fire. It's the next step if authenticated endpoints such as `/auth/products` are used. |

## Testing

- `test/core/api_client_test.dart`: URL/query building, JSON body, bearer
  header, mapping of HTTP/network/timeout/JSON errors.
- `test/core/jwt_test.dart`: reading `exp`, non-JWT / no-`exp` tokens.
- `test/core/api_client_test.dart` (401 group): refresh-and-retry once, no retry
  when refresh is rejected, no infinite loop, no refresh without a token.
- `test/data/session_manager_test.dart`: startup cases (no session, valid
  token → no network call, expired → refresh, within leeway, both expired,
  rejected, offline, opaque token). Also covers 401 refreshes: one shared call
  for concurrent 401s, reusing an already-refreshed token, rejection clears the
  tokens, network/5xx errors keep the session.
  Login/logout during an in-flight refresh: logout wins, logout waits for the
  refresh, a new login isn't overwritten, a refresh queued behind a logout
  makes no request. These tests fail against the previous implementation.
- `test/data/token_storage_test.dart`: both tokens stored under one key,
  read back by a new instance, clear, and unreadable data treated as no
  session.
- `test/data/`: model parsing (including a missing `brand`), `hasMore` math,
  repositories (tokens saved only on successful login, logout clears them,
  correct pagination params).
- `test/ui/*_view_model_test.dart`: the core of the suite. Covers every state
  transition: validation, loading flags, success/empty/error, pagination
  append and end-of-list, de-duplicating concurrent `loadMore` calls, refresh
  success/failure, the refresh-vs-pagination race, and no notifications after
  dispose. Failed-page retries use `fake_async`: no requests from scrolling
  while a retry is pending, exact retry timing, giving up after three failures,
  **Try again** restarting the cycle, and refresh/dispose cancelling the timer.
- `test/ui/product_list_screen_test.dart`: widget tests for the loading, empty
  and error→retry states, plus the footer going from "Retrying…" to
  **Try again** to the loaded page.
- `test/ui/app_startup_test.dart`: startup routes to the list or to login.
- `integration_test/app_flow_test.dart`: runs the real app against the live API.
  It covers wrong password → error, login → token stored in the Keychain,
  paginating past page 1 with no duplicates, opening a detail page, and logout
  clearing the token. It also covers two startup cases against the real
  `/auth/refresh`: an expired access token is refreshed silently, and a
  rejected refresh token lands on login. Verified on the iOS simulator.

### Why not refresh on every app start?

Refreshing unconditionally on launch is not the usual approach. It adds a
network round trip (and a spinner) before the first screen, breaks offline
launches, and for no benefit while the access token is still valid. The common
pattern, used here, is:

1. **Proactive, local check**: refresh at startup only if the access token has
   expired or is about to.
2. **Reactive**: refresh on a 401 and retry once.

Apps do sometimes validate on every launch, but for a different reason: to
find out whether the server has revoked the session (password changed, account
locked, remote logout). Banking or enterprise apps typically do this with a
`/me` call. That is a product/security decision, not a requirement of token
refresh. Note also that with rotating refresh tokens, refreshing on every
launch effectively makes the session never expire for active users. That may
or may not be what the product wants.

### Token lifetimes in this app

All of this was measured against the live API (November 2026), not taken from
the docs.

| Token | Lifetime | Read from |
|---|---|---|
| Access token | 60 minutes | JWT `exp` (dummyjson's default; `/auth/login` accepts `expiresInMins` to change it, which this app doesn't send) |
| Refresh token | 30 days | JWT `exp` |

**The product API never returns 401, so the refresh-on-401 path is never
reached.** `GET /products` returns 200 with a valid token, an expired one, an
invalid one, and no token at all. The token-protected equivalent is
`/auth/products`, but the task specifies `/products`. As a result, the
refresh-and-retry logic in `ApiClient` never runs in this app. It is covered
only by unit tests and is ready for authenticated endpoints added later. In
practice, the session is only checked when the app starts.

**Does the access token expire? Yes, 60 minutes after it was issued, but
nothing notices while the app is running.** The app keeps sending the expired
token to `/products`, which ignores it, so the list keeps working. The expiry is
only acted on at the **next launch**: the startup check sees the token has
expired and calls `/auth/refresh` before showing the list.

**How the refresh token expires.** It expires 30 days after it was issued.
Every successful refresh returns a new pair, including a refresh token with a
fresh 30 days, so the session slides forward. Refreshes only happen at a launch
after the access token has expired. So:

- If the user opens the app at least once every 30 days, the session never
  expires.
- If the user doesn't open the app for over 30 days, the refresh token has
  expired by the next launch. The startup check detects this locally (no
  network call), clears both tokens and shows the login screen.
- If the refresh token expires *while the app is open*, nothing happens until
  the next launch, which then shows the login screen.

**There is no server-side revocation.** dummyjson's tokens are stateless JWTs.
After a refresh, the *old* refresh token still works (re-using one returned
200), and logging out only deletes the tokens from the device. A copied token
stays valid until its `exp`. A production backend would track refresh tokens
so it could revoke them on logout, password change or reuse.

## Trade-offs / what I'd add with more time
- Image caching (`cached_network_image`), search/category filters, localisation
  and a `go_router`-based router if the app grew.
- iOS Keychain entries survive an app reinstall. A production app would clear
  stale tokens on the first launch after install.
