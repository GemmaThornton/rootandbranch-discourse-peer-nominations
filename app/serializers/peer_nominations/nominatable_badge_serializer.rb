# frozen_string_literal: true

module PeerNominations
  class NominatableBadgeSerializer < ApplicationSerializer
    attributes :id, :name, :description, :icon, :image_url

    def image_url
      object.image_upload&.url
    end
  end
end
