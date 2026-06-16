# Accounts & Dashboard UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add username/password multi-user accounts and give the telemetry app a polished, responsive white/red/black "sporty modern" UI — a personalised dashboard, themed login/sign-up, a restyled My Races table, and a relaid-out race detail page.

**Architecture:** Devise provides username-only auth (no email). Every `Race` gains a `user_id`; `RacesController` scopes through `current_user.races` and CanCanCan backs it up. Presentation logic lives in a Draper `RaceDecorator` and reusable Haml partials shared across the dashboard, My Races table, and race detail header. The look comes from Bootstrap Sass variable overrides plus one thin custom SCSS file; card track previews are inline SVG (no per-card JS).

**Tech Stack:** Rails 8, Devise, CanCanCan, Draper, PostgreSQL, Hamlit (Haml), simple_form + Bootstrap 5, Shakapacker, RSpec + FactoryBot + Capybara/headless-Chrome.

**Spec:** `docs/superpowers/specs/2026-06-16-accounts-and-dashboard-ui-design.md`.

**Conventions (don't fight them):**
- Views are `.haml`. Forms use `simple_form`. Decorators are Draper (`app/decorators/`).
- `login_as(user)` (Warden) is available in feature specs; `sign_in user` (Devise) is added for request specs in Task 1.
- Run one spec: `bundle exec rspec path/to/spec.rb`. Full suite: `bundle exec rake`.
- `js: true` feature specs use headless Chrome and compile webpack on first run.
- The Devise initializer already exists (`config/initializers/devise.rb`) — `devise:install` is done.

---

## File structure

**Auth & models**
- `app/models/user.rb` — Devise user, username-only.
- `db/migrate/<ts>_devise_create_users.rb` — users table.
- `db/migrate/<ts>_add_user_to_races.rb` — `races.user_id` (wipes existing dev races).
- `app/models/race.rb` — add `belongs_to :user`.
- `app/models/ability.rb` — per-user race rules.
- `config/initializers/devise.rb` — username auth keys.
- `config/routes.rb` — `devise_for`, dashboard root.
- `app/controllers/application_controller.rb` — `authenticate_user!`, permitted params.
- `app/controllers/races_controller.rb` — scope to `current_user.races`.

**Presentation**
- `app/decorators/race_decorator.rb` — status badge, best lap, uploaded-ago, SVG points.
- `app/views/shared/_stat_tile.html.haml`, `_race_card.html.haml`, `_page_header.html.haml`.

**Pages**
- `app/controllers/dashboard_controller.rb` + `app/views/dashboard/show.html.haml`.
- `app/views/devise/sessions/new.html.haml`, `app/views/devise/registrations/new.html.haml`.
- `app/views/races/index.html.haml`, `show.html.haml` — restyled/relaid-out.
- `app/views/layouts/application.html.haml` — themed navbar.

**Theme**
- `app/packs/styles/variables.scss` — palette + radii.
- `app/packs/styles/dashboard.scss` — thin custom layer (+ import in entrypoint).

**Specs** mirror the above under `spec/`.

---

## Task 1: User model, Devise username-only auth, routes

**Files:**
- Create: `db/migrate/<ts>_devise_create_users.rb`
- Create: `app/models/user.rb`
- Create: `spec/factories/users.rb`
- Modify: `config/initializers/devise.rb`
- Modify: `config/routes.rb`
- Modify: `app/controllers/application_controller.rb`
- Modify: `spec/rails_helper.rb`
- Test: `spec/models/user_spec.rb`

- [ ] **Step 1: Generate the users migration**

Run: `bin/rails g migration DeviseCreateUsers`

Replace the body with:
```ruby
class DeviseCreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string :username, null: false
      t.string :encrypted_password, null: false, default: ""
      t.timestamps null: false
    end
    add_index :users, :username, unique: true
  end
end
```

- [ ] **Step 2: Migrate**

Run: `bin/rails db:migrate`
Expected: `create_table(:users)` succeeds.

- [ ] **Step 3: Configure Devise for username login**

In `config/initializers/devise.rb`:
- Find `# config.authentication_keys = [:email]` and replace with:
  `config.authentication_keys = [:username]`
- Find `config.case_insensitive_keys = [:email]` and change to:
  `config.case_insensitive_keys = [:username]`
- Find `config.strip_whitespace_keys = [:email]` and change to:
  `config.strip_whitespace_keys = [:username]`

- [ ] **Step 4: Write the User model**

`app/models/user.rb`:
```ruby
class User < ApplicationRecord
  devise :database_authenticatable, :registerable, :validatable

  has_many :races, dependent: :destroy

  validates :username,
            presence: true,
            uniqueness: { case_sensitive: false },
            length: { in: 3..30 }

  # Devise's :validatable expects an email column; we have none.
  def email_required?
    false
  end

  def email_changed?
    false
  end

  def will_save_change_to_email?
    false
  end
end
```

- [ ] **Step 5: Add Devise routes**

In `config/routes.rb`, add inside the `Rails.application.routes.draw` block, above `resources :races`:
```ruby
  devise_for :users
```

- [ ] **Step 6: Permit the username param on sign-up**

In `app/controllers/application_controller.rb`, add a `before_action` and method. The file's private section currently has only `update_headers_to_disable_caching`; add:
```ruby
  before_action :configure_permitted_parameters, if: :devise_controller?
```
(place it just below the existing `before_action :update_headers_to_disable_caching` line), and add this method inside the `private` section:
```ruby
    def configure_permitted_parameters
      devise_parameter_sanitizer.permit(:sign_up, keys: [:username])
      devise_parameter_sanitizer.permit(:account_update, keys: [:username])
    end
```

- [ ] **Step 7: Enable Devise sign-in helper for request specs**

In `spec/rails_helper.rb`, find the line `config.include Devise::Test::ControllerHelpers, type: :controller` and add directly beneath it:
```ruby
  config.include Devise::Test::IntegrationHelpers, type: :request
```

- [ ] **Step 8: Write the users factory**

`spec/factories/users.rb`:
```ruby
FactoryBot.define do
  factory :user do
    sequence(:username) { |n| "driver#{n}" }
    password { "password123" }
  end
end
```

- [ ] **Step 9: Write the model spec**

`spec/models/user_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe User do
  it "is valid with a username and password" do
    expect(build(:user)).to be_valid
  end

  it "requires a username" do
    expect(build(:user, username: nil)).not_to be_valid
  end

  it "requires a username of at least 3 characters" do
    expect(build(:user, username: "ab")).not_to be_valid
  end

  it "rejects a duplicate username case-insensitively" do
    create(:user, username: "Alice")
    expect(build(:user, username: "alice")).not_to be_valid
  end

  it "does not require an email" do
    user = build(:user)
    expect(user).to respond_to(:email_required?)
    expect(user.email_required?).to be(false)
  end
end
```

- [ ] **Step 10: Run the spec**

Run: `bundle exec rspec spec/models/user_spec.rb`
Expected: PASS (5 examples).

- [ ] **Step 11: Commit**

```bash
git add app/models/user.rb db/migrate db/schema.rb config/initializers/devise.rb config/routes.rb app/controllers/application_controller.rb spec/rails_helper.rb spec/factories/users.rb spec/models/user_spec.rb
git commit -m "Add username-only Devise User model and auth config"
```

---

## Task 2: Race ownership, global auth, scoping, CanCanCan

Adds `races.user_id`, wires every race through `current_user`, requires login app-wide, and updates the existing specs (which currently assume no auth) to log in and own their races.

**Files:**
- Create: `db/migrate/<ts>_add_user_to_races.rb`
- Modify: `app/models/race.rb`
- Modify: `app/models/ability.rb`
- Modify: `app/controllers/application_controller.rb`
- Modify: `app/controllers/races_controller.rb`
- Modify: `spec/factories/races.rb`
- Modify: `spec/requests/races_spec.rb`
- Modify: `spec/features/race_telemetry_spec.rb`
- Test: `spec/requests/race_ownership_spec.rb`

- [ ] **Step 1: Generate the ownership migration**

Run: `bin/rails g migration AddUserToRaces`

Replace the body with (this wipes existing ownerless dev data so the not-null FK applies cleanly):
```ruby
class AddUserToRaces < ActiveRecord::Migration[8.0]
  def up
    # Dev data only — remove existing ownerless races and their children.
    execute "DELETE FROM telemetry_samples"
    execute "DELETE FROM laps"
    execute "DELETE FROM races"
    add_reference :races, :user, null: false, foreign_key: true
  end

  def down
    remove_reference :races, :user, foreign_key: true
  end
end
```

- [ ] **Step 2: Migrate**

Run: `bin/rails db:migrate`
Expected: `add_reference(:races, :user)` succeeds.

- [ ] **Step 3: Add the association to Race**

In `app/models/race.rb`, add below `has_one_attached :csv_file`:
```ruby
  belongs_to :user
```

- [ ] **Step 4: Write the failing ownership request spec**

`spec/requests/race_ownership_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe "Race ownership", type: :request do
  it "redirects unauthenticated users to the login page" do
    get races_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it "shows a user only their own races" do
    alice = create(:user)
    bob = create(:user)
    create(:race, user: alice, name: "Alice Race")
    create(:race, user: bob, name: "Bob Race")

    sign_in alice
    get races_path
    expect(response.body).to include("Alice Race")
    expect(response.body).not_to include("Bob Race")
  end

  it "forbids opening another user's race" do
    alice = create(:user)
    bob = create(:user)
    bob_race = create(:race, user: bob)

    sign_in alice
    get race_path(bob_race)
    expect(response).to have_http_status(:not_found).or have_http_status(:forbidden)
  end
end
```

- [ ] **Step 5: Run to verify it fails**

Run: `bundle exec rspec spec/requests/race_ownership_spec.rb`
Expected: FAIL — login not required / races not scoped yet.

- [ ] **Step 6: Require authentication app-wide**

In `app/controllers/application_controller.rb`, add directly below the existing
`before_action :update_headers_to_disable_caching` line:
```ruby
  before_action :authenticate_user!
```

- [ ] **Step 7: Scope RacesController to the current user**

Replace the contents of `app/controllers/races_controller.rb` with:
```ruby
class RacesController < ApplicationController
  before_action :set_race, only: %i[show destroy start_finish]

  def index
    @races = current_user.races.order(created_at: :desc)
  end

  def new
    @race = current_user.races.new
  end

  def create
    file = params.dig(:race, :csv_file)
    @race = current_user.races.new(name: file&.original_filename || "Untitled race")
    @race.csv_file.attach(file) if file

    if file && @race.save
      ParseRaceJob.perform_later(@race.id)
      redirect_to @race, notice: "Race uploaded. Parsing telemetry…"
    else
      @race.errors.add(:csv_file, "is required") if file.blank?
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @samples_json = @race.telemetry_samples.order(:sequence)
                         .pluck(:offset_ms, :lat, :lon, :speed, :lap_id)
                         .map { |t, lat, lon, sp, lap| { t:, lat:, lon:, sp:, lap: } }
    @laps = @race.laps.order(:number)
  end

  def destroy
    @race.destroy
    redirect_to races_path, notice: "Race deleted."
  end

  def start_finish
    @race.update!(start_finish_params)
    DetectLapsJob.perform_later(@race.id)
    redirect_to @race, notice: "Start/finish line set. Detecting laps…"
  end

  private

  def set_race
    @race = current_user.races.find(params[:id])
  end

  def start_finish_params
    params.require(:race).permit(
      :start_finish_lat_a, :start_finish_lon_a,
      :start_finish_lat_b, :start_finish_lon_b
    )
  end
end
```

Note: scoping `set_race` through `current_user.races` makes another user's race raise `ActiveRecord::RecordNotFound` → 404, which the ownership spec accepts.

- [ ] **Step 8: Add CanCanCan rules (defence in depth)**

In `app/models/ability.rb`, replace the body of `initialize` (the commented example block) with:
```ruby
    return if user.blank?

    can :manage, Race, user_id: user.id
```

- [ ] **Step 9: Give every race factory a user**

In `spec/factories/races.rb`, add `user` as the first attribute inside the factory block, directly above `sequence(:name) ...`:
```ruby
    user
```

- [ ] **Step 10: Update the existing races request spec to log in**

In `spec/requests/races_spec.rb`, directly below the line `before { ActiveJob::Base.queue_adapter = :test }`, add:
```ruby

  let(:user) { create(:user) }
  before { sign_in user }
```
Then change the race-creation expectation. Find:
```ruby
    expect(Race.last.name).to eq("telemetry_sample.csv")
```
and leave it as-is, but find the line that creates a race for the index test:
```ruby
    create(:race, name: "Brands Hatch AM")
```
and change it to:
```ruby
    create(:race, user: user, name: "Brands Hatch AM")
```
Also find the show and destroy examples' `race = create(:race)` lines and change each to:
```ruby
    race = create(:race, user: user)
```

- [ ] **Step 11: Update the feature spec to log in**

In `spec/features/race_telemetry_spec.rb`, add a logged-in user before each scenario. Directly below the `around do |example| ... end` block (before the first `scenario`), add:
```ruby
  let(:user) { create(:user) }
  before { login_as(user, scope: :user) }
```
Then, in the two scenarios that call `create(:race, ...)`, add `user: user` to each, e.g. change:
```ruby
    race = create(:race, status: :ready, sample_count: 2)
```
to:
```ruby
    race = create(:race, user: user, status: :ready, sample_count: 2)
```
(there are two such lines — update both).

- [ ] **Step 12: Run the affected specs**

Run: `bundle exec rspec spec/requests/race_ownership_spec.rb spec/requests/races_spec.rb spec/models/race_spec.rb`
Expected: PASS (ownership 3, races request 6 incl. root, race model 3).

- [ ] **Step 13: Run the feature spec**

Run: `bundle exec rspec spec/features/race_telemetry_spec.rb`
Expected: PASS (3 examples) — now logged in.

- [ ] **Step 14: Commit**

```bash
git add db/migrate db/schema.rb app/models/race.rb app/models/ability.rb app/controllers spec/factories/races.rb spec/requests/races_spec.rb spec/requests/race_ownership_spec.rb spec/features/race_telemetry_spec.rb
git commit -m "Scope races to the current user and require authentication"
```

---

## Task 3: White/red/black "sporty modern" theme

Recolours Bootstrap via Sass variables and adds a thin custom SCSS layer for the bits Bootstrap lacks. No behaviour change — validated visually and by later feature specs.

**Files:**
- Modify: `app/packs/styles/variables.scss`
- Create: `app/packs/styles/dashboard.scss`
- Modify: `app/packs/entrypoints/styles.js`

- [ ] **Step 1: Override Bootstrap variables**

Replace the contents of `app/packs/styles/variables.scss` with:
```scss
@import "~bootstrap/scss/functions";

// Brand palette — white / racing-red / near-black.
$primary: #e10600;   // racing red
$dark: #1a1a1a;      // near-black (navbar, headings)
// $danger left as Bootstrap default so destructive actions stay distinct.

$body-color: #1a1a1a;
$body-bg: #fafafa;

// Sporty-modern shape language.
$border-radius: 0.5rem;
$border-radius-sm: 0.375rem;
$border-radius-lg: 0.75rem;
$headings-font-weight: 700;
$enable-shadows: true;

@import "~bootstrap/scss/variables";
```

- [ ] **Step 2: Add the thin custom layer**

`app/packs/styles/dashboard.scss`:
```scss
// Custom pieces Bootstrap doesn't give us directly.

.stat-tile {
  background: #fff;
  border-radius: 0.75rem;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.08);
  padding: 1.25rem 1.5rem;

  .stat-tile__value {
    font-size: 2rem;
    font-weight: 700;
    line-height: 1;
    color: #1a1a1a;
  }

  .stat-tile__label {
    font-size: 0.8rem;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: #6c757d;
  }
}

.race-card {
  transition: transform 0.12s ease, box-shadow 0.12s ease;

  &:hover {
    transform: translateY(-3px);
    box-shadow: 0 6px 18px rgba(0, 0, 0, 0.12);
  }

  .race-card__thumb {
    width: 100%;
    height: 90px;
    background: #f1f1f1;
    border-radius: 0.5rem;

    polyline {
      fill: none;
      stroke: #e10600;
      stroke-width: 2;
      stroke-linejoin: round;
      stroke-linecap: round;
    }
  }
}

.upload-card {
  border: 2px dashed #ced4da;
  background: #fff;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  text-align: center;
  color: #6c757d;

  &:hover {
    border-color: #e10600;
    color: #e10600;
  }
}

.auth-wrapper {
  min-height: 80vh;
  display: flex;
  align-items: center;
  justify-content: center;
}

.auth-card {
  width: 100%;
  max-width: 380px;
}

// Race detail two-column layout (stacks on mobile via Bootstrap grid).
.race-table-rows tbody tr {
  cursor: pointer;
}
```

- [ ] **Step 3: Import the custom layer**

In `app/packs/entrypoints/styles.js`, add a line below `import '../styles/layout';`:
```js
import '../styles/dashboard';
```

- [ ] **Step 4: Commit**

```bash
git add app/packs/styles/variables.scss app/packs/styles/dashboard.scss app/packs/entrypoints/styles.js
git commit -m "Add white/red/black sporty theme via Bootstrap variables"
```

---

## Task 4: Themed navbar + auth pages (login / sign-up)

**Files:**
- Modify: `app/views/layouts/application.html.haml`
- Create: `app/views/devise/sessions/new.html.haml`
- Create: `app/views/devise/registrations/new.html.haml`
- Test: `spec/features/authentication_spec.rb`

- [ ] **Step 1: Write the failing auth feature spec**

`spec/features/authentication_spec.rb`:
```ruby
require "rails_helper"

RSpec.feature "Authentication", js: true do
  scenario "a visitor signs up and lands on the dashboard" do
    visit new_user_registration_path
    fill_in "Username", with: "speedy"
    fill_in "Password", with: "password123"
    fill_in "Password confirmation", with: "password123"
    click_button "Create account"

    expect(page).to have_content("Welcome back, speedy")
  end

  scenario "an existing user logs in" do
    create(:user, username: "racer", password: "password123")
    visit new_user_session_path
    fill_in "Username", with: "racer"
    fill_in "Password", with: "password123"
    click_button "Log in"

    expect(page).to have_content("Welcome back, racer")
  end

  scenario "a logged-in user can log out" do
    login_as(create(:user, username: "outgoing"), scope: :user)
    visit root_path
    click_button "Log out"

    expect(page).to have_content("Log in")
  end
end
```

Note: this spec depends on the dashboard (Task 7) showing "Welcome back, <username>". It will fully pass after Task 7; for now it drives the auth views and navbar. Run it at the end of Task 7.

- [ ] **Step 2: Restyle the navbar in the layout**

In `app/views/layouts/application.html.haml`, replace the `%header.navbar...` block
(currently lines ~24–34, from `%header.navbar.navbar-expand-lg.bg-light.mb-3` through the
Home `nav-link`) with:
```haml
    - unless controller.devise_controller?
      %header.navbar.navbar-expand-lg.navbar-dark.bg-dark.mb-4
        .container
          = link_to root_path, class: "navbar-brand fw-bold" do
            %i.bi-flag-fill.text-danger
            Telemetry
          %button.navbar-toggler{ type: :button, data: { bs_toggle: :collapse, bs_target: "#navbar-content" }, aria: { controls: "navbar-content", expanded: "false", label: "Toggle navigation" } }
            %span.navbar-toggler-icon
          #navbar-content.navbar-collapse.collapse
            - if user_signed_in?
              %nav.navbar-nav.ms-auto.align-items-lg-center
                = link_to "Dashboard", root_path, class: "nav-link#{' active' if current_page?(root_path)}"
                = link_to "My Races", races_path, class: "nav-link#{' active' if current_page?(races_path)}"
                .nav-item.dropdown
                  %a.nav-link.dropdown-toggle{ href: "#", role: "button", data: { bs_toggle: "dropdown" }, aria: { expanded: "false" } }
                    %i.bi-person-circle.me-1
                    = current_user.username
                  %ul.dropdown-menu.dropdown-menu-end
                    %li
                      = button_to "Log out", destroy_user_session_path, method: :delete, class: "dropdown-item"
```

The new navbar uses a bootstrap-icon brand (`bi-flag-fill`), so the deleted
`images/logo.png` is no longer referenced. Leave the rest of the layout (the `%head`,
flash block, `%main`, `%footer`) unchanged.

- [ ] **Step 3: Create the themed login view**

`app/views/devise/sessions/new.html.haml`:
```haml
.auth-wrapper
  .auth-card.card.shadow-sm
    .card-body.p-4
      %h1.h4.fw-bold.text-center.mb-1
        %i.bi-flag-fill.text-danger
        Telemetry
      %p.text-muted.text-center.mb-4 Log in to your account
      = simple_form_for(resource, as: resource_name, url: session_path(resource_name)) do |f|
        = f.input :username, autofocus: true, input_html: { autocomplete: "username" }
        = f.input :password, input_html: { autocomplete: "current-password" }
        = f.button :submit, "Log in", class: "btn btn-primary w-100"
      %p.text-center.mt-3.mb-0
        New here?
        = link_to "Create account", new_registration_path(resource_name)
```

- [ ] **Step 4: Create the themed sign-up view**

`app/views/devise/registrations/new.html.haml`:
```haml
.auth-wrapper
  .auth-card.card.shadow-sm
    .card-body.p-4
      %h1.h4.fw-bold.text-center.mb-1
        %i.bi-flag-fill.text-danger
        Telemetry
      %p.text-muted.text-center.mb-4 Create your account
      = simple_form_for(resource, as: resource_name, url: registration_path(resource_name)) do |f|
        = f.input :username, autofocus: true, input_html: { autocomplete: "username" }
        = f.input :password, input_html: { autocomplete: "new-password" }
        = f.input :password_confirmation, input_html: { autocomplete: "new-password" }
        = f.button :submit, "Create account", class: "btn btn-primary w-100"
      %p.text-center.mt-3.mb-0
        Already have an account?
        = link_to "Log in", new_session_path(resource_name)
```

- [ ] **Step 5: Commit**

```bash
git add app/views/layouts/application.html.haml app/views/devise spec/features/authentication_spec.rb
git commit -m "Add themed navbar and login/sign-up pages"
```

---

## Task 5: RaceDecorator

Centralises race presentation: status badge, best-lap display, uploaded-ago, and inline-SVG thumbnail points.

**Files:**
- Create: `app/decorators/race_decorator.rb`
- Test: `spec/decorators/race_decorator_spec.rb`

- [ ] **Step 1: Write the failing decorator spec**

`spec/decorators/race_decorator_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe RaceDecorator do
  let(:user) { create(:user) }

  it "renders a themed status badge" do
    race = create(:race, user: user, status: :ready).decorate
    expect(race.status_badge).to include("badge")
    expect(race.status_badge).to include("Ready")
  end

  describe "#best_lap_display" do
    it "shows a dash when there is no best lap" do
      race = create(:race, user: user).decorate
      expect(race.best_lap_display).to eq("—")
    end

    it "shows the formatted best lap time" do
      race = create(:race, user: user)
      create(:lap, race: race, lap_time_ms: 101_234, best: true)
      expect(race.decorate.best_lap_display).to eq("1:41.234")
    end
  end

  it "renders an uploaded-ago string" do
    race = create(:race, user: user).decorate
    expect(race.uploaded_ago).to match(/ago\z/)
  end

  describe "#thumbnail_svg_points" do
    it "is nil when there are fewer than two located samples" do
      race = create(:race, user: user).decorate
      expect(race.thumbnail_svg_points).to be_nil
    end

    it "produces a space-separated points string from located samples" do
      race = create(:race, user: user)
      create(:telemetry_sample, race: race, sequence: 0, lat: 53.0, lon: -1.0)
      create(:telemetry_sample, race: race, sequence: 1, lat: 53.001, lon: -1.001)
      points = race.decorate.thumbnail_svg_points
      expect(points).to be_a(String)
      expect(points.split(" ").length).to eq(2)
      expect(points).to match(/\A[\d.,\s]+\z/)
    end
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/decorators/race_decorator_spec.rb`
Expected: FAIL — `uninitialized constant RaceDecorator`.

- [ ] **Step 3: Implement the decorator**

`app/decorators/race_decorator.rb`:
```ruby
class RaceDecorator < ApplicationDecorator
  delegate_all

  STATUS_VARIANTS = {
    "pending" => "secondary",
    "processing" => "warning",
    "ready" => "success",
    "failed" => "danger"
  }.freeze

  def status_badge
    variant = STATUS_VARIANTS.fetch(object.status, "secondary")
    h.content_tag(:span, object.status.titleize, class: "badge text-bg-#{variant}")
  end

  def best_lap_display
    object.best_lap&.formatted_time || "—"
  end

  def uploaded_ago
    "#{h.time_ago_in_words(object.created_at)} ago"
  end

  # Inline-SVG polyline points for a mini track preview, projected into a
  # width x height viewBox. Returns nil when there's no usable track data.
  def thumbnail_svg_points(width: 100, height: 60, pad: 4)
    coords = object.telemetry_samples.located.order(:sequence).pluck(:lat, :lon)
    return nil if coords.length < 2

    step = [coords.length / 40, 1].max
    sampled = coords.each_slice(step).map(&:first)

    lats = sampled.map(&:first)
    lons = sampled.map(&:last)
    min_lat, max_lat = lats.minmax
    min_lon, max_lon = lons.minmax
    lat_span = (max_lat - min_lat).nonzero? || 1.0
    lon_span = (max_lon - min_lon).nonzero? || 1.0
    inner_w = width - pad * 2
    inner_h = height - pad * 2

    sampled.map do |lat, lon|
      x = pad + ((lon - min_lon) / lon_span) * inner_w
      y = pad + (1 - (lat - min_lat) / lat_span) * inner_h
      "#{x.round(1)},#{y.round(1)}"
    end.join(" ")
  end
end
```

- [ ] **Step 4: Run to verify it passes**

Run: `bundle exec rspec spec/decorators/race_decorator_spec.rb`
Expected: PASS (6 examples).

- [ ] **Step 5: Commit**

```bash
git add app/decorators/race_decorator.rb spec/decorators/race_decorator_spec.rb
git commit -m "Add RaceDecorator for race presentation"
```

---

## Task 6: Shared view partials

Reusable fragments used by the dashboard, My Races, and race detail pages.

**Files:**
- Create: `app/views/shared/_stat_tile.html.haml`
- Create: `app/views/shared/_race_card.html.haml`
- Create: `app/views/shared/_page_header.html.haml`

- [ ] **Step 1: Create the stat tile partial**

`app/views/shared/_stat_tile.html.haml`:
```haml
.stat-tile
  .stat-tile__value= value
  .stat-tile__label= label
```
Usage contract: `render "shared/stat_tile", value: "7", label: "Races"`.

- [ ] **Step 2: Create the race card partial**

`app/views/shared/_race_card.html.haml` (expects a decorated `race`):
```haml
= link_to race_path(race), class: "text-decoration-none text-reset" do
  .card.race-card.shadow-sm.h-100
    .card-body
      .d-flex.justify-content-between.align-items-start.mb-2
        %h3.h6.fw-bold.mb-0= race.name
        = race.status_badge
      - if race.thumbnail_svg_points
        %svg.race-card__thumb{ viewBox: "0 0 100 60", preserveAspectRatio: "xMidYMid meet" }
          %polyline{ points: race.thumbnail_svg_points }
      - else
        .race-card__thumb.d-flex.align-items-center.justify-content-center.text-muted.small
          No track data
      .d-flex.justify-content-between.mt-3.small.text-muted
        %span= "#{race.lap_count} laps"
        %span= "best #{race.best_lap_display}"
```

- [ ] **Step 3: Create the page header partial**

`app/views/shared/_page_header.html.haml`:
```haml
.d-flex.flex-wrap.justify-content-between.align-items-center.mb-4
  %div
    %h1.h3.fw-bold.mb-1= title
    - if local_assigns[:subtitle]
      .text-muted= subtitle
  - if local_assigns[:actions]
    %div= actions
```
Usage contract: `render "shared/page_header", title: "My Races", actions: link_to(...)`. `subtitle` and `actions` are optional.

- [ ] **Step 4: Commit**

```bash
git add app/views/shared
git commit -m "Add shared stat-tile, race-card, and page-header partials"
```

---

## Task 7: Dashboard (home)

The personalised landing page: welcome header, summary stat strip, recent-race cards, and a prominent upload box.

**Files:**
- Create: `app/controllers/dashboard_controller.rb`
- Create: `app/views/dashboard/show.html.haml`
- Modify: `config/routes.rb`
- Test: `spec/requests/dashboard_spec.rb`

- [ ] **Step 1: Write the failing request spec**

`spec/requests/dashboard_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe "Dashboard", type: :request do
  let(:user) { create(:user, username: "speedy") }
  before { sign_in user }

  it "greets the user by name" do
    get root_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Welcome back, speedy")
  end

  it "shows the user's race count and only their recent races" do
    create(:race, user: user, name: "My Recent Race")
    create(:race, user: create(:user), name: "Someone Else Race")

    get root_path
    expect(response.body).to include("My Recent Race")
    expect(response.body).not_to include("Someone Else Race")
  end

  it "shows an empty state when the user has no races" do
    get root_path
    expect(response.body).to include("Upload your first race")
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/requests/dashboard_spec.rb`
Expected: FAIL — root still points at `races#index`, no dashboard.

- [ ] **Step 3: Create the controller**

`app/controllers/dashboard_controller.rb`:
```ruby
class DashboardController < ApplicationController
  def show
    races = current_user.races.order(created_at: :desc)
    @recent_races = races.limit(5).decorate
    @race_count = races.count
    @lap_count = current_user.races.sum(:lap_count)
    @best_lap_ms = Lap.where(race: current_user.races, best: true).minimum(:lap_time_ms)
  end
end
```

- [ ] **Step 4: Point root at the dashboard**

In `config/routes.rb`, change:
```ruby
  root "races#index"
```
to:
```ruby
  root "dashboard#show"
```

- [ ] **Step 4b: Update the stale root-page test**

The first plan left a test in `spec/requests/races_spec.rb` named "uses the races index as
the root page" (it does `get root_path` and expects `"Races"`). Root is now the dashboard,
so replace that whole `it` block with one that reflects the new root:
```ruby
  it "uses the dashboard as the root page" do
    get root_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Welcome back")
  end
```

- [ ] **Step 5: Create the dashboard view**

`app/views/dashboard/show.html.haml`:
```haml
%h1.h3.fw-bold.mb-4
  Welcome back, #{current_user.username}
  %i.bi-flag-fill.text-danger

.row.g-3.mb-4
  .col-6.col-md-4
    = render "shared/stat_tile", value: @race_count, label: "Races"
  .col-6.col-md-4
    = render "shared/stat_tile", value: @lap_count, label: "Laps"
  .col-12.col-md-4
    - best = @best_lap_ms ? Lap.new(lap_time_ms: @best_lap_ms).formatted_time : "—"
    = render "shared/stat_tile", value: best, label: "Best lap"

.d-flex.justify-content-between.align-items-center.mb-3
  %h2.h5.fw-bold.mb-0 Recent races
  = link_to "View all", races_path, class: "btn btn-sm btn-outline-dark"

.row.g-3
  - @recent_races.each do |race|
    .col-12.col-sm-6.col-lg-4
      = render "shared/race_card", race: race
  .col-12.col-sm-6.col-lg-4
    = link_to new_race_path, class: "card upload-card h-100 text-decoration-none p-4" do
      %i.bi-cloud-arrow-up.fs-1
      %div.fw-bold.mt-2 Upload a new race
      - if @race_count.zero?
        .small Upload your first race
      - else
        .small Drop a CSV or browse files
```

- [ ] **Step 6: Run to verify it passes**

Run: `bundle exec rspec spec/requests/dashboard_spec.rb`
Expected: PASS (3 examples).

- [ ] **Step 7: Run the auth feature spec (now that the dashboard exists)**

Run: `bundle exec rspec spec/features/authentication_spec.rb`
Expected: PASS (3 examples) — sign-up/login land on "Welcome back, …".

- [ ] **Step 8: Commit**

```bash
git add app/controllers/dashboard_controller.rb app/views/dashboard config/routes.rb spec/requests/dashboard_spec.rb
git commit -m "Add personalised dashboard home page"
```

---

## Task 8: Restyle the My Races table

**Files:**
- Modify: `app/views/races/index.html.haml`
- Test: extend `spec/requests/races_spec.rb`

- [ ] **Step 1: Add a failing expectation for the themed columns**

In `spec/requests/races_spec.rb`, inside the top-level `describe`, add:
```ruby
  it "shows status, laps, best, and uploaded columns on the index" do
    create(:race, user: user, name: "Cadwell Park")
    get races_path
    expect(response.body).to include("Cadwell Park")
    expect(response.body).to include("Uploaded")
    expect(response.body).to include("Best")
  end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/requests/races_spec.rb -e "status, laps, best"`
Expected: FAIL — current index has no "Uploaded"/"Best" headers.

- [ ] **Step 3: Rewrite the index view**

Replace the contents of `app/views/races/index.html.haml` with:
```haml
= render "shared/page_header", title: "My Races",
    actions: link_to("Upload race", new_race_path, class: "btn btn-primary")

- if @races.any?
  .card.shadow-sm
    .table-responsive
      %table.table.table-hover.align-middle.race-table-rows.mb-0
        %thead
          %tr
            %th Name
            %th Status
            %th Laps
            %th Best
            %th Uploaded
            %th
        %tbody
          - @races.decorate.each do |race|
            %tr{ data: { href: race_path(race) } }
              %td= link_to race.name, race_path(race), class: "fw-semibold text-reset text-decoration-none"
              %td= race.status_badge
              %td= race.lap_count
              %td= race.best_lap_display
              %td.text-muted= race.uploaded_ago
              %td.text-end
                = link_to race_path(race), data: { turbo_method: :delete, turbo_confirm: "Delete this race?" }, class: "text-danger", aria: { label: "Delete" } do
                  %i.bi-trash
- else
  .text-center.text-muted.py-5
    %i.bi-flag.fs-1
    %p.mt-2 No races yet. Upload a CSV to get started.
    = link_to "Upload race", new_race_path, class: "btn btn-primary"
```

- [ ] **Step 4: Run to verify it passes**

Run: `bundle exec rspec spec/requests/races_spec.rb`
Expected: PASS (all examples, including the new column test).

- [ ] **Step 5: Commit**

```bash
git add app/views/races/index.html.haml spec/requests/races_spec.rb
git commit -m "Restyle My Races as a themed table"
```

---

## Task 9: Relayout the race detail page

Header with name/status/stats; map and lap table side-by-side on desktop, stacked on mobile. Existing canvas + lap-highlight JS behaviour is preserved (the `#track-map` data attributes and `.lap-table` markup are unchanged).

**Files:**
- Modify: `app/views/races/show.html.haml`
- Modify: `app/controllers/races_controller.rb` (decorate `@race` for the view)

- [ ] **Step 1: Decorate the race in `show`**

In `app/controllers/races_controller.rb`, at the end of the `show` action (after the
`@laps = ...` line), add:
```ruby
    @race = @race.decorate
```

- [ ] **Step 2: Rewrite the show view**

Replace the contents of `app/views/races/show.html.haml` with:
```haml
= render "shared/page_header",
    title: @race.name,
    actions: link_to("Delete", race_path(@race), data: { turbo_method: :delete, turbo_confirm: "Delete this race?" }, class: "btn btn-outline-danger btn-sm")

.d-flex.flex-wrap.align-items-center.gap-2.mb-4
  = @race.status_badge
  %span.text-muted= "#{@race.lap_count} laps"
  %span.text-muted ·
  %span.text-muted= "best #{@race.best_lap_display}"
  %span.text-muted ·
  %span.text-muted= "#{@race.sample_count} samples"

.row.g-4
  .col-12.col-lg-8
    .card.shadow-sm
      .card-body
        #track-map{ data: { track_map: true,
                            race_id: @race.id,
                            samples: @samples_json.to_json,
                            start_finish: { lat_a: @race.start_finish_lat_a, lon_a: @race.start_finish_lon_a, lat_b: @race.start_finish_lat_b, lon_b: @race.start_finish_lon_b }.to_json,
                            update_url: start_finish_race_path(@race) } }
          %canvas.track-canvas.w-100{ width: 900, height: 480 }
          %button#set-start-finish.btn.btn-outline-primary.mt-3{ type: "button" } Set start/finish line
  .col-12.col-lg-4
    = render "lap_table", race: @race, laps: @laps

= link_to "Back to races", races_path, class: "btn btn-link mt-3"
```

- [ ] **Step 3: Run the race feature spec**

Run: `bundle exec rspec spec/features/race_telemetry_spec.rb`
Expected: PASS (3 examples) — canvas, lap highlight, and start/finish still work in the new layout.

- [ ] **Step 4: Run the races request spec**

Run: `bundle exec rspec spec/requests/races_spec.rb`
Expected: PASS — `show` still renders.

- [ ] **Step 5: Commit**

```bash
git add app/views/races/show.html.haml app/controllers/races_controller.rb
git commit -m "Relayout race detail with side-by-side map and lap table"
```

---

## Task 10: Full-journey + isolation feature spec, full suite

**Files:**
- Create: `spec/features/dashboard_journey_spec.rb`

- [ ] **Step 1: Write the journey + isolation feature spec**

`spec/features/dashboard_journey_spec.rb`:
```ruby
require "rails_helper"

RSpec.feature "Dashboard journey", js: true do
  around do |example|
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :inline
    example.run
    ActiveJob::Base.queue_adapter = original
  end

  scenario "a user uploads a race from the dashboard and opens it" do
    login_as(create(:user, username: "pilot"), scope: :user)
    visit root_path
    expect(page).to have_content("Welcome back, pilot")

    click_link "Upload a new race"
    attach_file "Telemetry CSV", Rails.root.join("spec/factories/files/telemetry_sample.csv")
    click_button "Upload"

    expect(page).to have_css("canvas.track-canvas")
    expect(page).to have_content("Ready")

    visit races_path
    expect(page).to have_content("telemetry_sample.csv")
  end

  scenario "a user cannot see another user's races" do
    alice = create(:user, username: "alice")
    create(:race, user: create(:user, username: "bob"), name: "Bob Secret Race")

    login_as(alice, scope: :user)
    visit races_path
    expect(page).not_to have_content("Bob Secret Race")
  end
end
```

- [ ] **Step 2: Run the new feature spec**

Run: `bundle exec rspec spec/features/dashboard_journey_spec.rb`
Expected: PASS (2 examples).

- [ ] **Step 3: Run the full suite**

Run: `bundle exec rake`
Expected: all specs PASS (models, decorator, requests, features).

- [ ] **Step 4: Commit**

```bash
git add spec/features/dashboard_journey_spec.rb
git commit -m "Add dashboard journey and user-isolation feature specs"
```

- [ ] **Step 5: Manual smoke test**

```bash
bin/dev                    # terminal 1
bin/shakapacker-dev-server # terminal 2
```
Visit `http://localhost:3000` → redirected to login → create an account → land on the
dashboard → upload `public/short_example_telemetry_log.csv` → see it as a card → open it
→ confirm the themed two-column race page. (Sample log is near-stationary, so no laps form
— expected.)

---

## Self-review notes (coverage check)

- Username-only Devise accounts, no email: Task 1. ✓
- Login required app-wide; per-user race scoping; CanCanCan: Task 2. ✓
- Existing dev races wiped on `user_id` introduction: Task 2 Step 1. ✓
- White/red/black sporty theme via Bootstrap variables + thin custom SCSS: Task 3. ✓
- `$danger` kept distinct from brand red: Task 3 Step 1. ✓
- Themed near-black navbar with username dropdown + logout, hidden on auth pages: Task 4. ✓
- Themed login + sign-up: Task 4. ✓
- `RaceDecorator` (status badge, best lap, uploaded-ago, inline-SVG thumbnail points): Task 5. ✓
- Reusable partials (stat tile, race card, page header): Task 6. ✓
- Dashboard: welcome header, stat strip, recent cards, upload box, empty state: Task 7. ✓
- My Races themed table: Task 8. ✓
- Race detail relayout (side-by-side, stacks on mobile), canvas/lap-highlight preserved: Task 9. ✓
- Full journey + two-user isolation feature specs: Tasks 2, 7, 10. ✓
- Inline-SVG card thumbnails (no per-card JS): Tasks 5–6. ✓

**Deferred (per spec):** password reset/email, teams/sharing, race renaming, admin UI, charts, Leaflet basemap.
