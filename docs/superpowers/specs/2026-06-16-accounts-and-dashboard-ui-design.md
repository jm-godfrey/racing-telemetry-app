# Accounts & Dashboard UI Design

**Date:** 2026-06-16
**Status:** Approved (design phase)

## Goal

Turn the telemetry app from a single-user, stock-Bootstrap tool into a multi-user
application with a polished, responsive UI. A visitor logs in (or signs up) with a
username and password, lands on a personalised dashboard ("Welcome back, <username>")
showing their summary stats, recent races, and an upload box, and navigates via a
near-black navbar to a "My Races" list and into a relaid-out race detail page. Visual
theme: clean and responsive, mainly white with racing-red and near-black accents
("sporty & modern").

## Scope

In scope:
- Real multi-user accounts (username + password, no email) via Devise.
- Per-user race ownership and scoping; users only ever see their own races.
- A white/red/black "sporty modern" theme applied through Bootstrap Sass variables.
- New pages: dashboard (home), themed login & sign-up, restyled "My Races" table,
  relaid-out race detail page, near-black navbar.
- Shared, reusable view components (Haml partials + a `RaceDecorator`).

Out of scope (YAGNI / deferred):
- Password reset / email of any kind (no email captured; forgotten passwords are a
  manual/admin reset).
- Public roles/admin UI beyond per-user ownership.
- Renaming races, sharing races between users, teams.
- Speed-trace / lap-compare charts, Leaflet basemap (already deferred elsewhere).

## Decisions (from brainstorming)

- **Auth model:** full multi-user accounts — each user sees only their own races.
- **Login field:** username only. No email anywhere. Devise modules:
  `:database_authenticatable, :registerable, :validatable`. No `:recoverable`,
  `:confirmable`, or `:rememberable` unless trivially default.
- **Login required globally:** every page requires authentication (app acts as a lock
  screen for unauthenticated users).
- **Dashboard contents:** summary stat strip + recent-race cards + a prominent upload box.
- **My Races page:** a clean, themed table (not cards).
- **Race detail page:** relaid out — header with name/status/stats, map and lap table
  side-by-side on desktop and stacked on mobile.
- **Visual feel:** sporty & modern — soft shadows, rounded corners (~`0.5rem`), bold
  racing-red primary, near-black (`#1a1a1a`) navbar/text, generous whitespace.
- **`$danger` kept distinct** from the brand red so destructive actions don't blend in.
- **Card track thumbnails:** inline SVG `<polyline>` (no per-card JS), not canvas.
- **Existing dev races may be wiped** when `user_id` is introduced (no backfill needed).

## Architecture

### 1. Authentication & data model

**`User` model (Devise, username-only):**
- Generate a Devise `User` with a `username` column instead of `email`.
- Columns: `username` (string, not null, unique case-insensitive), Devise's
  `encrypted_password`, and timestamps. No `email` column.
- Devise config: `config.authentication_keys = [:username]`.
- Model: `devise :database_authenticatable, :registerable, :validatable`. Because
  `:validatable` validates `email` by default, override `email_required?` and
  `email_changed?` to return `false` so it skips email entirely, and add our own
  validations for `username`: presence, case-insensitive uniqueness, length 3–30.

**Race ownership:**
- Migration: add `user_id` (FK to `users`, indexed, `null: false`) to `races`. Existing
  rows are wiped (dev data only) so the not-null FK can be added cleanly — i.e. delete
  existing races in the migration (or recreate the dev DB) before adding the constraint.
- Associations: `Race belongs_to :user`; `User has_many :races, dependent: :destroy`.

**Access control:**
- `ApplicationController`: `before_action :authenticate_user!` globally.
- All `RacesController` actions scope through `current_user.races` (index, show, create,
  destroy, start_finish) so a user can never load another user's race. `create` sets
  `user: current_user`.
- CanCanCan `Ability`: `can :manage, Race, user_id: user.id` as defence-in-depth.
  `CanCan::AccessDenied` is already mapped to 403 in `config/application.rb`.

**Routes:**
- `devise_for :users` (login, logout, sign-up paths).
- `root "dashboard#show"` (the new home).
- `resources :races, only: %i[index new create show destroy]` with the existing member
  `patch :start_finish`. The races index becomes the "My Races" page.

### 2. Theme & shared components (Approach C)

**Bootstrap Sass variables (`app/packs/styles/variables.scss`):**
- `$primary: #e10600` (racing red); `$dark: #1a1a1a` (near-black); body bg white/`#fafafa`;
  body text near-black. `$danger` left as Bootstrap's default (distinct from brand red).
- `$border-radius: 0.5rem` (and friends) for rounded cards/buttons; shadows enabled; bold
  heading weight. Variables set **before** importing Bootstrap.

**Custom SCSS (`app/packs/styles/dashboard.scss`, imported from the styles entrypoint):**
- Stat-tile styling, card hover-lift, mini track-thumbnail box framing, status-badge
  tweaks, login/sign-up centered-card background. Kept thin — Bootstrap does the rest.

**`RaceDecorator` (Draper, `app/decorators/race_decorator.rb`):**
Centralises race presentation so dashboard cards, My Races rows, and the race header
share it:
- `status_badge` — themed Bootstrap badge (Ready=success, Processing=warning,
  Failed=danger, Pending=secondary).
- `best_lap_display` — formatted best lap time (`Lap#formatted_time`) or "—".
- `uploaded_ago` — `time_ago_in_words` → "2d ago".
- `thumbnail_svg_points` — a downsampled set of located lat/lon points, projected into a
  fixed viewBox, as an SVG `points` string. Returns nil when there's no usable track data
  (card then skips the thumbnail).

**Shared Haml partials (`app/views/shared/`):**
- `_race_card.html.haml` — boxed card: name, `status_badge`, lap count, `best_lap_display`,
  inline SVG `<polyline>` thumbnail; links to the race.
- `_stat_tile.html.haml` — one stat tile (label + big value) for the dashboard strip.
- `_page_header.html.haml` — consistent page title + optional actions/stats row.

### 3. Pages

**Navbar** (`app/views/layouts/application.html.haml`): near-black
(`navbar-dark bg-dark`), brand on the left, right side: Dashboard, My Races, and a
username dropdown with Log out. Active link uses the red accent. Hamburger on mobile.
Suppressed on Devise (login/sign-up) screens — e.g. a separate minimal layout or a
conditional.

**Login & Sign-up** (themed Devise views under `app/views/devise/`): centered card on a
clean background, no navbar. Login = username + password + "Create account" link.
Sign-up = username + password + confirmation. `simple_form`, red primary button, inline
validation errors.

**Dashboard** (`DashboardController#show`, route `/`):
- Header: "Welcome back, <username>".
- Stat strip: total races, total laps, overall best lap (across the user's races) as
  `_stat_tile`s.
- Recent races: the user's latest 3–5 races as `_race_card`s in a responsive grid, with
  the upload box rendered as a distinct call-to-action card in the same grid, plus a
  "View all" link to My Races.
- Empty state (zero races): stat tiles show zeros; the grid shows only the upload card
  with an "Upload your first race" prompt.

**My Races** (`races#index`, `/races`): themed table — Name, Status badge, Laps, Best,
Uploaded ("2d ago"), actions. Row hover; click name/row to open; delete via an action
with a confirm. "Upload race" button in the page header.

**Race detail** (`races#show`, `/races/:id`): `_page_header` with race name, status badge,
and key stats (lap count · best lap · duration). Below: a responsive two-column layout —
the existing speed-coloured `<canvas>` map on the left, the lap table on the right —
stacking to one column on mobile. The "Set start/finish line" control and the existing
canvas + lap-highlight JS behaviour are preserved, just relocated into the new layout.

### 4. Error handling & edge cases

- Unauthenticated access to any page → redirect to login (Devise).
- Accessing/deleting another user's race → not found via `current_user.races` scoping,
  with CanCanCan `AccessDenied` → 403 as a backstop.
- Login/sign-up validation errors → re-render themed form with inline errors.
- Dashboard with zero races → friendly empty state (see above).
- Failed/processing races → status badge shown; cards with no located samples skip the
  SVG thumbnail gracefully.

### 5. Testing

Follows repo conventions (model / request / feature / decorator specs; FactoryBot;
`js: true` features use headless Chrome).

- **Model:** `User` username validations (presence, case-insensitive uniqueness,
  length); `Race belongs_to :user`; `User has_many :races, dependent: :destroy`.
- **Decorator:** `RaceDecorator` status badge, best-lap display, uploaded-ago, and
  thumbnail points (incl. nil when no track data).
- **Request:** unauthenticated requests redirect to login; a user sees only their own
  races on index/show; cross-user access is forbidden (403/redirect); sign-up creates a
  user and logs in; dashboard renders stats + recent races; existing `races_spec` updated
  to log in first.
- **Feature (`js: true`):** sign up → dashboard "Welcome back" → upload a race → see it
  as a card → open it → relaid-out detail page renders (canvas + lap table). Plus a
  two-user isolation scenario (user A cannot see user B's races).

## Component summary

| Unit | Purpose | Depends on |
|------|---------|-----------|
| `User` (model) | Username/password account | Devise |
| `Race#user` | Ownership | `User` |
| `Ability` | Per-user authorization | CanCanCan, `User`, `Race` |
| `DashboardController` | Personalised home | `current_user.races`, `RaceDecorator` |
| `RaceDecorator` | Race presentation (badge, best lap, ago, SVG points) | Draper, `Race`, `Lap` |
| `_race_card` / `_stat_tile` / `_page_header` | Reusable view fragments | `RaceDecorator` |
| Devise views | Themed login/sign-up | Devise, simple_form |
| Theme (`variables.scss` + `dashboard.scss`) | White/red/black sporty look | Bootstrap 5 |

## Deferred

Password reset/email, teams/sharing, race renaming, admin UI, charts, Leaflet basemap.
