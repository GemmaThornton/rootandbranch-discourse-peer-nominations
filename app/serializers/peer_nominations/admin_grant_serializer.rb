# frozen_string_literal: true

module PeerNominations
  # JSON shape returned by /peer-nominations/admin/users/:user_id/received.
  # Powers the admin-only "Peer nominations received" panel on user profiles.
  # Includes the reason text, nominator + badge metadata, and original
  # topic state so the UI can label closed/archived topics correctly.
  class AdminGrantSerializer < ApplicationSerializer
    attributes :id,
               :granted_at,
               :reason,
               :nominator,
               :badge,
               :topic

    def nominator
      u = object.nominator
      return nil unless u
      {
        id:              u.id,
        username:        u.username,
        name:            u.name.presence,
        avatar_template: u.avatar_template,
      }
    end

    def badge
      b = object.badge
      return nil unless b
      {
        id:    b.id,
        name:  b.display_name,
        icon:  b.icon,
      }
    end

    def topic
      t = object.topic
      return nil unless t
      {
        id:       t.id,
        title:    t.title,
        slug:     t.slug,
        url:      t.url,
        closed:   t.closed,
        archived: t.archived,
      }
    end
  end
end
