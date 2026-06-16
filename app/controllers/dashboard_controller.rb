class DashboardController < ApplicationController
  def show
    races = current_user.races.order(created_at: :desc)
    @recent_races = races.limit(5).decorate
    @race_count = races.count
    @lap_count = current_user.races.sum(:lap_count)
    @best_lap_ms = Lap.where(race: current_user.races, best: true).minimum(:lap_time_ms)
  end
end
