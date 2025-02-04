# frozen_string_literal: true

# Copyright (c) Aptos
# SPDX-License-Identifier: Apache-2.0

class User < ApplicationRecord
  include RailsStateMachine::Model

  # Include default devise modules. Others available are:
  # :lockable, :timeoutable, :recoverable,
  devise :database_authenticatable, :confirmable,
         :rememberable, :trackable, :validatable,
         :omniauthable, omniauth_providers: %i[discord github],
                        authentication_keys: [:username]

  validates :username, uniqueness: { case_sensitive: false }, allow_nil: true
  validates :email, uniqueness: { case_sensitive: false }, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true

  validate_hex :mainnet_address

  has_many :authorizations, dependent: :destroy

  # https://github.com/makandra/rails_state_machine
  # TODO: this state machine
  state_machine :kyc_status do
    state :not_started, initial: true
  end

  def self.from_omniauth(auth, current_user = nil)
    # find an existing user or create a user and authorizations
    # schema of auth https://github.com/omniauth/omniauth/wiki/Auth-Hash-Schema

    # returning users
    authorization = Authorization.find_by(provider: auth.provider, uid: auth.uid)
    return authorization.user if authorization

    # if user is already logged in, add new oauth to existing user
    if current_user
      current_user.add_oauth_authorization(auth).save!
      return current_user
    end

    # Totally new user
    user = create_new_user_from_oauth(auth)
    user.save!
    user
  end

  def self.create_new_user_from_oauth(auth)
    # Create a blank user: no email or username
    user = User.new({
                      password: Devise.friendly_token(32)
                    })
    user.add_oauth_authorization(auth)
    user
  end

  # Maintaining state if a user was not able to be saved
  # def self.new_with_session(params, session)
  #   super.tap do |user|
  #     if (data = session['devise.oauth.data'])
  #       user.email = data['info']['email'] if user.email.blank?
  #       user.add_oauth_authorization(data)
  #     end
  #   end
  # end

  def providers
    authorizations.map(&:provider)
  end

  def add_oauth_authorization(data)
    expires_at = begin
      Time.at(data['credentials']['expires_at'])
    rescue StandardError
      nil
    end
    auth = {
      provider: data['provider'],
      uid: data['uid'],
      token: data['credentials']['token'],
      expires: data['credentials']['expires'],
      secret: data['credentials']['secret'],
      refresh_token: data['credentials']['refresh_token'],
      expires_at:,

      email: data['info']['email'].downcase,
      profile_url: data['info']['image']
    }
    case data['provider']
    when 'github'
      auth = auth.merge({
                          username: data['info']['nickname'].downcase,
                          full_name: data['info']['name']
                        })
    when 'discord'
      raw_info = data['extra']['raw_info']
      auth = auth.merge({
                          username: "#{raw_info['username'].downcase}##{raw_info['discriminator']}",
                          full_name: data['info']['name'],
                          profile_url: data['info']['image']
                        })
    else
      raise 'Unknown Provider!'
    end
    authorizations.build(auth)
  end

  private

  # This is to allow username instead of email login in devise (for aptos admins)
  def email_required?
    false
  end

  # This is to allow username instead of email login in devise (for aptos admins)
  def will_save_change_to_email?
    false
  end
end
