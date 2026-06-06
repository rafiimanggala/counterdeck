class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :builder_token

  # Anonymous, per-browser identity for the deck builder (no user accounts).
  # Stored in a signed, long-lived cookie so a visitor keeps their own decks.
  def builder_token
    cookies.signed.permanent[:builder_token] ||= SecureRandom.uuid
  end
end
