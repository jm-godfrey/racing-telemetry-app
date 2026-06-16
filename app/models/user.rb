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
