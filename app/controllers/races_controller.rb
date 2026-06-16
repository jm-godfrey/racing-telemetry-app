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
